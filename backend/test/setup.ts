import { vi, beforeEach, afterAll } from 'vitest';
import { prisma } from '../src/config/prisma.js';

// ── Firebase (external boundary) ──────────────────────────────────────────────
// Email auth: a token "test:<email>" verifies as that email, already verified;
// "unverified:<email>" as that email before the user clicked the verification link.
// Push: every send succeeds without reaching Google.
vi.mock('../src/config/firebase.js', () => ({
  firebaseAuth: {
    verifyIdToken: vi.fn(async (idToken: string) => {
      if (idToken.startsWith('test:')) return { email: idToken.slice('test:'.length), email_verified: true };
      if (idToken.startsWith('unverified:')) return { email: idToken.slice('unverified:'.length), email_verified: false };
      throw new Error('Invalid Firebase token');
    }),
  },
  fcm: {
    send: vi.fn().mockResolvedValue('message-id'),
    sendEachForMulticast: vi.fn().mockResolvedValue({ successCount: 1, failureCount: 0, responses: [] }),
  },
}));

// ── Database ──────────────────────────────────────────────────────────────────
beforeEach(async () => {
  const tables = await prisma.$queryRaw<{ tablename: string }[]>`
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND tablename <> '_prisma_migrations'`;
  const list = tables.map((t) => `"${t.tablename}"`).join(', ');
  await prisma.$executeRawUnsafe(`TRUNCATE ${list} CASCADE`);
});

afterAll(async () => {
  await prisma.$disconnect();
});
