import { Prisma, PrismaClient, Role, UserStatus } from '@prisma/client';
import { startOfDayInRome } from '../src/utils/date.js';
import { mockUsers, type MockUser } from './mock-users.js';

const DAY = 24 * 60 * 60 * 1000;
const SUPER_ADMIN_EMAIL = 'superadmin@example.com';
const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '::1', '[::1]']);

export function isLocalDatabase(url: string | undefined) {
  if (!url) return false;
  try {
    return LOCAL_HOSTS.has(new URL(url).hostname);
  } catch {
    return false;
  }
}

const daysAgo = (days: number) => new Date(Date.now() - days * DAY);

// The calendar date in Italy, days from now, as startOfDayInRome expects it.
const dateInRome = (days: number) =>
  new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Rome' }).format(new Date(Date.now() + days * DAY));

async function ensureSuperAdmin(prisma: PrismaClient) {
  const existing = await prisma.user.findFirst({ where: { role: Role.super_admin } });
  if (existing) return existing;
  return prisma.user.create({
    data: {
      name: 'Super',
      surname: 'Admin',
      email: SUPER_ADMIN_EMAIL,
      motivation: 'System seed',
      role: Role.super_admin,
      reviewedByAdmin: true,
      lastConfirmedAt: new Date(),
    },
  });
}

// A started journey with its group, unless one of this kind is already there.
async function ensureGroup(prisma: PrismaClient, kind: NonNullable<MockUser['group']>, openedBy: string) {
  const ended: Prisma.GroupWhereInput = kind === 'active' ? { endedAt: null } : { endedAt: { not: null } };
  const existing = await prisma.group.findFirst({ where: ended, orderBy: { startedAt: 'desc' } });
  if (existing) return existing;

  const startedAt = daysAgo(kind === 'active' ? 2 : 250);
  const durationDays = kind === 'active' ? 365 : 180;
  const cycle = await prisma.registrationCycle.create({
    data: {
      status: 'closed',
      openedBy,
      openedAt: new Date(startedAt.getTime() - 14 * DAY),
      scheduledClosedAt: startedAt,
      closedAt: startedAt,
      startsAt: startedAt,
      durationDays,
      group: {
        create: {
          startedAt,
          endedAt: kind === 'active' ? null : new Date(startedAt.getTime() + durationDays * DAY),
        },
      },
    },
    include: { group: true },
  });
  return cycle.group!;
}

async function ensureOpenCycle(prisma: PrismaClient, openedBy: string) {
  const now = new Date();
  await prisma.registrationCycle.updateMany({
    where: { status: 'open', scheduledClosedAt: { lte: now } },
    data: { status: 'closed', closedAt: now },
  });
  const existing = await prisma.registrationCycle.findFirst({ where: { status: 'open' } });
  if (existing) return existing;
  return prisma.registrationCycle.create({
    data: {
      status: 'open',
      openedBy,
      openedAt: new Date(),
      scheduledClosedAt: new Date(Date.now() + 7 * DAY),
      startsAt: startOfDayInRome(dateInRome(14))!,
    },
  });
}

/**
 * Adds what is missing and changes nothing that exists, so it can run again and again:
 * users are matched by email, and existing groups and the open cycle are reused. The only
 * thing it brings back is a mock requester's request, if they have no other in progress.
 */
export async function seedMockData(prisma: PrismaClient) {
  const superAdmin = await ensureSuperAdmin(prisma);
  const active = await ensureGroup(prisma, 'active', superAdmin.id);
  const archived = await ensureGroup(prisma, 'archived', superAdmin.id);
  const cycle = await ensureOpenCycle(prisma, superAdmin.id);

  const { count: users } = await prisma.user.createMany({
    data: mockUsers.map((u) => {
      const groupId = u.group === 'active' ? active.id : u.group === 'archived' ? archived.id : null;
      return {
        email: u.email,
        name: u.name,
        surname: u.surname,
        motivation: u.motivation,
        role: u.role ?? Role.user,
        status: u.status ?? UserStatus.active,
        reviewedByAdmin: u.reviewed ?? false,
        groupId,
        lastConfirmedAt: new Date(),
      };
    }),
    skipDuplicates: true,
  });

  const { count: bannedEmails } = await prisma.bannedEmail.createMany({
    data: mockUsers.filter((u) => u.status === 'banned').map((u) => ({ email: u.email })),
    skipDuplicates: true,
  });

  // Who is still a waiting, active user with no request in progress: changes made
  // from the panel since the last run are respected.
  const requesters = await prisma.user.findMany({
    where: {
      email: { in: mockUsers.filter((u) => u.requested).map((u) => u.email) },
      status: UserStatus.active,
      OR: [{ groupId: null }, { group: { endedAt: { lte: new Date() } } }],
      participationRequests: { none: { cycle: { startsAt: { gt: new Date() } } } },
    },
    orderBy: { email: 'asc' },
    select: { id: true },
  });
  const { count: requests } = await prisma.participationRequest.createMany({
    // Hours apart, so that the list has a realistic order.
    data: requesters.map(({ id }, i) => ({
      cycleId: cycle.id,
      userId: id,
      createdAt: new Date(Date.now() - (i + 1) * 3 * 60 * 60 * 1000),
    })),
    skipDuplicates: true,
  });

  return { users, bannedEmails, requests, cycle };
}
