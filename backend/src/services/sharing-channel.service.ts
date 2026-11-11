import { env } from '../config/env.js';
import { prisma } from '../config/prisma.js';
import { pushToChannelMembers, pushToGroup } from './push.service.js';
import { addMinutes, calendarDateInRome, wallTimeInRome } from '../utils/date.js';

type Schedule = { dayOfWeek: number; startTime: string; durationMinutes: number };

// ISO day of the week of a YYYY-MM-DD calendar date: 1 = Monday … 7 = Sunday.
function isoDayOfWeek(date: string) {
  return new Date(`${date}T00:00:00.000Z`).getUTCDay() || 7;
}

function daysBefore(date: string, days: number) {
  const day = new Date(`${date}T00:00:00.000Z`);
  day.setUTCDate(day.getUTCDate() - days);
  return day.toISOString().slice(0, 10);
}

// The start of the most recent weekly appointment that is not in the future.
function latestAppointmentStart(schedule: Schedule, now: Date) {
  const today = calendarDateInRome(now);
  for (let back = 0; back <= 7; back += 1) {
    const date = daysBefore(today, back);
    if (isoDayOfWeek(date) !== schedule.dayOfWeek) continue;
    const start = wallTimeInRome(date, schedule.startTime);
    if (start <= now) return start;
  }
  throw new Error('No weekly appointment in the last 8 days');
}

async function openDueChannels(now: Date) {
  const schedule = await prisma.sharingChannelSchedule.findUnique({ where: { id: 1 } });
  if (!schedule) return;

  const opensAt = latestAppointmentStart(schedule, now);
  const closesAt = addMinutes(opensAt, schedule.durationMinutes);
  // A change of schedule counts from the next appointment: never open late.
  if (opensAt <= schedule.updatedAt || now >= closesAt) return;

  const groups = await prisma.group.findMany({
    where: {
      startedAt: { lte: now },
      OR: [{ endedAt: null }, { endedAt: { gt: now } }],
      // A channel still open under the previous schedule ends at its own time first.
      sharingChannels: { none: { status: 'open' } },
    },
    select: { id: true },
  });

  for (const group of groups) {
    // The unique (group, opening time) pair keeps this appointment from opening twice.
    const [channel] = await prisma.sharingChannel.createManyAndReturn({
      data: [{ groupId: group.id, status: 'open', openedAt: opensAt, scheduledClosedAt: closesAt }],
      skipDuplicates: true,
    });
    if (!channel) continue;

    await pushToGroup(group.id, 'Cerchio', 'Il cerchio è aperto', {
      type: 'sharing_channel:opened',
      channelId: channel.id,
    });
  }
}

// Messages and members go when the channel closes: nothing of it is kept.
async function closeChannel(channelId: string, now: Date) {
  await pushToChannelMembers(channelId, 'Canale di condivisione chiuso', 'La sessione è terminata', {
    type: 'sharing_channel:closed',
    channelId,
  });

  await prisma.sharingChannel.update({
    where: { id: channelId },
    data: { status: 'closed', closedAt: now },
  });

  await prisma.sharingChannelPost.deleteMany({ where: { sharingChannelId: channelId } });
  await prisma.sharingChannelMember.deleteMany({ where: { sharingChannelId: channelId } });
}

async function closeDueChannels(now: Date) {
  const channels = await prisma.sharingChannel.findMany({
    where: { status: 'open', scheduledClosedAt: { lte: now } },
    select: { id: true },
  });
  for (const channel of channels) await closeChannel(channel.id, now);
}

async function warnChannelsClosingSoon(now: Date) {
  const minutes = env.SHARING_CHANNEL_WARN_MINUTES;
  const channels = await prisma.sharingChannel.findMany({
    where: { status: 'open', closingWarningAt: null, scheduledClosedAt: { lte: addMinutes(now, minutes) } },
    select: { id: true },
  });

  for (const channel of channels) {
    // Only the tick that marks the channel sends the warning.
    const { count } = await prisma.sharingChannel.updateMany({
      where: { id: channel.id, closingWarningAt: null },
      data: { closingWarningAt: now },
    });
    if (!count) continue;

    await pushToChannelMembers(channel.id, 'Il cerchio sta per chiudere', `Il cerchio si chiude tra ${minutes} minuti`, {
      type: 'sharing_channel:closing_soon',
      channelId: channel.id,
    });
  }
}

// Opens and closes every group's sharing channel following the weekly schedule.
export async function runSharingChannelTick(now: Date) {
  await closeDueChannels(now);
  await warnChannelsClosingSoon(now);
  await openDueChannels(now);
}
