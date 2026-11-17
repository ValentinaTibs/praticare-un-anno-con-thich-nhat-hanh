import { Prisma } from '@prisma/client';
import { prisma } from '../config/prisma.js';
import { journeyEndsAt } from '../utils/date.js';

// A cycle past its closing date counts as closed even before the job marks it,
// so requests stop exactly at the date the Super Admin set.
export function findOpenCycle() {
  return prisma.registrationCycle.findFirst({
    where: {
      status: 'open',
      OR: [{ scheduledClosedAt: null }, { scheduledClosedAt: { gt: new Date() } }],
    },
  });
}

export async function closeExpiredCycles() {
  const now = new Date();
  await prisma.registrationCycle.updateMany({
    where: { status: 'open', scheduledClosedAt: { lte: now } },
    data: { status: 'closed', closedAt: now },
  });
}

// Brings to life the groups of cycles whose journey has started. Late runs catch up after
// downtime: the group still starts on the cycle's date, and runs can't create it twice.
// A cycle that fails doesn't hold back the others: the errors are thrown together at the end,
// and the next run tries that cycle again.
export async function startDueGroups() {
  const now = new Date();
  const cycles = await prisma.registrationCycle.findMany({
    where: {
      startsAt: { lte: now },
      group: null,
      OR: [{ participationRequests: { some: {} } }, { removedRequesters: { some: {} } }],
    },
    include: {
      participationRequests: {
        where: {
          user: {
            status: 'active',
            reviewedByAdmin: true,
            // One journey at a time: a request made while a due group was still to be created
            // may belong to someone who has just joined that group.
            OR: [{ groupId: null }, { group: { endedAt: { lte: now } } }],
          },
        },
        select: { userId: true },
      },
    },
    orderBy: { startsAt: 'asc' },
  });

  const errors: unknown[] = [];
  for (const cycle of cycles) {
    const memberIds = cycle.participationRequests.map(({ userId }) => userId);

    try {
      await prisma.$transaction(async (tx) => {
        // Every request lapses here, so a review arriving later can't bring a group to life.
        await tx.participationRequest.deleteMany({ where: { cycleId: cycle.id } });
        // The emails of removed requesters only kept them from asking again in this cycle:
        // with the journey started they serve no purpose, and a removal deletes all data.
        await tx.removedRequester.deleteMany({ where: { cycleId: cycle.id } });
        // A catch-up after the whole journey has passed would make a group that never was.
        if (memberIds.length === 0 || journeyEndsAt(cycle.startsAt, cycle.durationDays) <= now) return;

        await tx.group.create({
          data: {
            cycleId: cycle.id,
            startedAt: cycle.startsAt,
            members: { connect: memberIds.map((id) => ({ id })) },
          },
        });
        await tx.user.updateMany({ where: { id: { in: memberIds } }, data: { lastConfirmedAt: cycle.startsAt } });
        // A round left pending from before must not suspend someone who has just been confirmed.
        await tx.confirmationRequest.updateMany({
          where: { userId: { in: memberIds }, status: 'pending' },
          data: { status: 'confirmed', confirmedAt: cycle.startsAt },
        });
      });
    } catch (error) {
      // Another run created this group first: the unique index on the cycle stopped this one.
      if (!(error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002')) errors.push(error);
    }
  }
  if (errors.length > 0) throw new AggregateError(errors, `Groups not started for ${errors.length} cycle(s)`);
}
