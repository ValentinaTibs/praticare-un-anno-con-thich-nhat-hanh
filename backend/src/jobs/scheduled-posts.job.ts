import { prisma } from '../config/prisma.js';
import { pushToAll } from '../services/push.service.js';
import { scheduleJob } from './schedule.js';

export function startScheduledPostsJob() {
  scheduleJob('* * * * *', 'scheduled posts', async () => {
    const due = await prisma.mainChannelPost.findMany({
      where: {
        scheduledAt: { lte: new Date() },
        publishedAt: null,
        isDraft: false,
      },
    });

    for (const post of due) {
      await prisma.mainChannelPost.update({
        where: { id: post.id },
        data: { publishedAt: new Date() },
      });

      await pushToAll('Nuovo post', post.content.slice(0, 100), { type: 'main_channel:new_post' });
    }
  });
}
