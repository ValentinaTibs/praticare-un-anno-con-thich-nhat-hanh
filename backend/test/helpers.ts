import { vi } from 'vitest';
import { buildApp } from '../src/app.js';
import { prisma } from '../src/config/prisma.js';

export async function createTestApp() {
  const app = await buildApp();
  return app;
}

// Typed handle to the mocked prisma so tests can set up return values cleanly
export const db = prisma as unknown as {
  [K in keyof typeof prisma]: {
    [M in keyof (typeof prisma)[K]]: ReturnType<typeof vi.fn>;
  };
};

export function makeUser(overrides = {}) {
  return {
    id: 'user-1',
    name: 'Test',
    surname: 'User',
    phoneNumber: '+391234567890',
    motivation: 'Testing',
    role: 'user' as const,
    status: 'active' as const,
    reviewedByAdmin: false,
    lastConfirmedAt: new Date(),
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  };
}

export function makeAdmin(overrides = {}) {
  return makeUser({ id: 'admin-1', role: 'admin' as const, reviewedByAdmin: true, ...overrides });
}
