import { prisma } from '../config/prisma.js';

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

// Brings to life the groups of cycles whose journey has started.
export async function startDueGroups() {
  const cycles = await prisma.registrationCycle.findMany({
    where: { startsAt: { lte: new Date() }, group: null },
    include: {
      participationRequests: {
        where: { user: { status: 'active', reviewedByAdmin: true } },
        select: { userId: true },
      },
    },
  });

  for (const cycle of cycles) {
    const memberIds = cycle.participationRequests.map(({ userId }) => userId);

    await prisma.$transaction(async (tx) => {
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
  }
}
