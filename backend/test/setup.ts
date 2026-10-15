import { vi } from 'vitest';

// ── Prisma ────────────────────────────────────────────────────────────────────
vi.mock('../src/config/prisma.js', () => ({
  prisma: {
    user: {
      findUnique: vi.fn(),
      findUniqueOrThrow: vi.fn(),
      findMany: vi.fn(),
      findFirst: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      updateMany: vi.fn(),
      delete: vi.fn(),
      count: vi.fn(),
    },
    userDevice: {
      findMany: vi.fn(),
      upsert: vi.fn(),
      deleteMany: vi.fn(),
    },
    refreshToken: {
      findUnique: vi.fn(),
      create: vi.fn(),
      delete: vi.fn(),
      deleteMany: vi.fn(),
    },
    bannedPhone: {
      findUnique: vi.fn(),
      upsert: vi.fn(),
      delete: vi.fn(),
      deleteMany: vi.fn(),
    },
    registrationCycle: {
      findFirst: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
    },
    mainChannelPost: {
      findMany: vi.fn(),
      findUniqueOrThrow: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      updateMany: vi.fn(),
      delete: vi.fn(),
      count: vi.fn(),
    },
    sharingChannel: {
      findFirst: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
    },
    sharingChannelMember: {
      findFirst: vi.fn(),
      findMany: vi.fn(),
      create: vi.fn(),
      delete: vi.fn(),
      deleteMany: vi.fn(),
    },
    sharingChannelPost: {
      findMany: vi.fn(),
      findUniqueOrThrow: vi.fn(),
      create: vi.fn(),
      delete: vi.fn(),
      deleteMany: vi.fn(),
    },
    confirmationRequest: {
      findFirst: vi.fn(),
      findMany: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
    },
    $transaction: vi.fn((ops: unknown[]) => Promise.all(ops)),
  },
}));

// ── Twilio ────────────────────────────────────────────────────────────────────
vi.mock('../src/config/twilio.js', () => ({
  twilioClient: {
    verify: {
      v2: {
        services: () => ({
          verifications: { create: vi.fn().mockResolvedValue({ status: 'pending' }) },
          verificationChecks: { create: vi.fn().mockResolvedValue({ status: 'approved' }) },
        }),
      },
    },
  },
  VERIFY_SERVICE_SID: 'VA_test',
}));

// ── Firebase ──────────────────────────────────────────────────────────────────
vi.mock('../src/config/firebase.js', () => ({
  fcm: {
    send: vi.fn().mockResolvedValue('message-id'),
    sendEachForMulticast: vi.fn().mockResolvedValue({ successCount: 1, failureCount: 0, responses: [] }),
  },
}));

// ── Socket.IO ─────────────────────────────────────────────────────────────────
vi.mock('../src/sockets/index.js', () => ({
  getIO: vi.fn(() => ({
    emit: vi.fn(),
    to: vi.fn(() => ({ emit: vi.fn() })),
    in: vi.fn(() => ({ socketsLeave: vi.fn() })),
    socketsLeave: vi.fn(),
  })),
  initSocketIO: vi.fn(),
}));
