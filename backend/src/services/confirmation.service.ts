import { prisma } from '../config/prisma.js';
import { env } from '../config/env.js';
import { addDays } from '../utils/date.js';
import { pushToUser } from './push.service.js';
import { UserStatus } from '@prisma/client';

export async function issueConfirmationRequests() {
  const cutoff = addDays(new Date(), -env.CONFIRMATION_INTERVAL_DAYS);

  const users = await prisma.user.findMany({
    where: {
      status: UserStatus.active,
      role: 'user',
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

    await pushToUser(user.id, 'Action required', 'Please confirm your participation');
  }
}

export async function processMissedConfirmations() {
  const overdue = await prisma.confirmationRequest.findMany({
    where: { status: 'pending', dueAt: { lt: new Date() } },
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
