import { prisma } from '../config/prisma.js';
import { pushToGroup } from './push.service.js';
import { addCalendarDays, calendarDateInRome, calendarDaysBetween, wallTimeInRome } from '../utils/date.js';

const EXCERPT_LENGTH = 100;

// The beginning of a post, as the text of its push notification.
export function postExcerpt(content: string) {
  const text = content.replace(/\s+/g, ' ').trim();
  return text.length <= EXCERPT_LENGTH ? text : `${text.slice(0, EXCERPT_LENGTH - 1).trimEnd()}…`;
}

type JourneyGroup = { id: string; startedAt: Date };

// Publishes in the group's Main Channel the templates whose journey day and time it
// has reached. A template that entered the sequence after that moment is skipped.
async function publishDueTemplates(group: JourneyGroup, now: Date) {
  const startDate = calendarDateInRome(group.startedAt);
  const today = calendarDateInRome(now);
  const journeyDay = calendarDaysBetween(startDate, today) + 1;

  const templates = await prisma.mainChannelTemplate.findMany({
    where: {
      status: 'scheduled',
      journeyDay: { lte: journeyDay },
      sequencedAt: { lt: now },
      publications: { none: { groupId: group.id } },
    },
    orderBy: [{ journeyDay: 'asc' }, { publishTime: 'asc' }],
  });

  for (const template of templates) {
    const dueAt = wallTimeInRome(addCalendarDays(startDate, template.journeyDay - 1), template.publishTime);
    if (dueAt > now || dueAt <= template.sequencedAt!) continue;

    const post = await prisma.$transaction(async (tx) => {
      // The (group, template) key keeps a template from being published twice.
      const { count } = await tx.mainChannelPublication.createMany({
        data: [{ groupId: group.id, templateId: template.id, publishedAt: dueAt }],
        skipDuplicates: true,
      });
      if (!count) return null;
      // A late post keeps its due time, so the channel stays in sequence order.
      return tx.mainChannelPost.create({
        data: {
          groupId: group.id,
          templateId: template.id,
          authorId: template.authorId,
          content: template.content,
          publishedAt: dueAt,
        },
      });
    });
    if (!post) continue;

    // After a restart, a late post is announced only on its own day.
    if (calendarDateInRome(dueAt) !== today) continue;
    await pushToGroup(group.id, 'Canale Principale', postExcerpt(post.content), {
      type: 'main_channel:new_post',
      postId: post.id,
    });
  }
}

// Copies the due templates of the sequence into the Main Channel of every active
// group, including those missed while the server was off.
export async function runMainChannelTick(now: Date) {
  const groups = await prisma.group.findMany({
    where: { startedAt: { lte: now }, OR: [{ endedAt: null }, { endedAt: { gt: now } }] },
    select: { id: true, startedAt: true },
  });
  for (const group of groups) await publishDueTemplates(group, now);
}
