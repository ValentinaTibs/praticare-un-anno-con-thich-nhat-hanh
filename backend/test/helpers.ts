import type { Prisma } from '@prisma/client';
import { buildApp } from '../src/app.js';
import { prisma } from '../src/config/prisma.js';

export async function createTestApp() {
  return buildApp();
}

// An idToken that the mocked Firebase (see setup.ts) verifies as this email, already verified.
export function firebaseTokenFor(email: string) {
  return `test:${email}`;
}

// An idToken for an email whose owner has not clicked the verification link yet.
export function unverifiedFirebaseTokenFor(email: string) {
  return `unverified:${email}`;
}

let userCounter = 0;

export async function givenUser(overrides: Partial<Prisma.UserCreateInput> = {}) {
  userCounter += 1;
  return prisma.user.create({
    data: {
      name: 'Test',
      surname: 'User',
      email: `user${userCounter}@test.local`,
      motivation: 'Testing',
      lastConfirmedAt: new Date(),
      ...overrides,
    },
  });
}

export async function givenMember(group: { id: string }, overrides: Partial<Prisma.UserCreateInput> = {}) {
  return givenUser({ group: { connect: { id: group.id } }, ...overrides });
}

export async function givenAdmin(overrides: Partial<Prisma.UserCreateInput> = {}) {
  return givenUser({ role: 'admin', reviewedByAdmin: true, ...overrides });
}

// Logs in through the real login route, so the token is the one a client would get.
export async function loginAs(app: Awaited<ReturnType<typeof createTestApp>>, user: { email: string }) {
  const res = await app.inject({
    method: 'POST',
    url: '/api/auth/verify-firebase',
    payload: { idToken: firebaseTokenFor(user.email) },
  });
  if (res.statusCode !== 200) throw new Error(`login failed: ${res.statusCode} ${res.body}`);
  return { authorization: `Bearer ${res.json().accessToken}` };
}

export async function givenOpenCycle(scheduledClosedAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)) {
  const openedAt = new Date();
  return prisma.registrationCycle.create({
    data: { status: 'open', openedAt, scheduledClosedAt, group: { create: { startedAt: openedAt } } },
    include: { group: true },
  });
}

// A group from a cycle that has already closed.
export async function givenGroup() {
  const cycle = await prisma.registrationCycle.create({
    data: { status: 'closed', openedAt: new Date(), closedAt: new Date(), group: { create: { startedAt: new Date() } } },
    include: { group: true },
  });
  return cycle.group!;
}

// permanent: banned for good; otherwise removed by an admin and blocked until the next cycle.
export async function givenBlockedEmail(email: string, { permanent }: { permanent: boolean }) {
  return prisma.bannedEmail.create({ data: { email, permanent } });
}

// Opens the group's sharing channel directly: the spec allows only scheduled opening, which doesn't exist yet.
export async function givenOpenSharingChannel(
  group: { id: string },
  scheduledClosedAt = new Date(Date.now() + 60 * 60 * 1000),
) {
  return prisma.sharingChannel.create({
    data: { groupId: group.id, status: 'open', openedAt: new Date(), scheduledClosedAt },
  });
}
