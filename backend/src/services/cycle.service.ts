import { prisma } from '../config/prisma.js';

// A cycle past its closing date counts as closed even before the job marks it,
// so registrations stop exactly at the date the Super Admin set.
export function findOpenCycle() {
  return prisma.registrationCycle.findFirst({
    where: {
      status: 'open',
      OR: [{ scheduledClosedAt: null }, { scheduledClosedAt: { gt: new Date() } }],
    },
    include: { group: true },
  });
}

export async function closeExpiredCycles() {
  const now = new Date();
  await prisma.registrationCycle.updateMany({
    where: { status: 'open', scheduledClosedAt: { lte: now } },
    data: { status: 'closed', closedAt: now },
  });
}
