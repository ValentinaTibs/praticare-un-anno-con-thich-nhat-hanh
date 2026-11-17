import { prisma } from '../config/prisma.js';
import { env } from '../config/env.js';
import { addDays } from '../utils/date.js';
import { pushToUser } from './push.service.js';
import { Prisma, UserStatus } from '@prisma/client';

// Only members of a group whose journey is under way take part in confirmation rounds:
// waiting users, ex-members included, are never asked to confirm nor suspended for it.
const inActiveGroup = (now: Date): Prisma.UserWhereInput => ({
  group: { startedAt: { lte: now }, OR: [{ endedAt: null }, { endedAt: { gt: now } }] },
});

export async function issueConfirmationRequests() {
  const now = new Date();
  const cutoff = addDays(now, -env.CONFIRMATION_INTERVAL_DAYS);

  const users = await prisma.user.findMany({
    where: {
      status: UserStatus.active,
      role: 'user',
      ...inActiveGroup(now),
      lastConfirmedAt: { lt: cutoff },
      confirmationRequests: {
        none: { status: 'pending' },
      },
    },
    select: { id: true },
  });

  for (const user of users) {
    await prisma.confirmationRequest.create({
      data: {
        userId: user.id,
        dueAt: addDays(new Date(), env.CONFIRMATION_GRACE_DAYS),
      },
    });

    await pushToUser(user.id, 'Azione richiesta', 'Conferma la tua partecipazione');
  }
}

export async function processMissedConfirmations() {
  const now = new Date();
  // A waiting user's request lapses instead: it may be left from a journey that has ended.
  await prisma.confirmationRequest.deleteMany({
    where: { status: 'pending', dueAt: { lt: now }, user: { NOT: inActiveGroup(now) } },
  });

  const overdue = await prisma.confirmationRequest.findMany({
    where: { status: 'pending', dueAt: { lt: now } },
    include: { user: { select: { id: true } } },
  });

  for (const req of overdue) {
    await prisma.$transaction([
      prisma.confirmationRequest.update({
        where: { id: req.id },
        data: { status: 'missed' },
      }),
      prisma.user.update({
        where: { id: req.user.id },
        data: { status: UserStatus.suspended },
      }),
    ]);
  }
}
