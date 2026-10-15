import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createTestApp, db, makeUser } from './helpers.js';

describe('POST /api/auth/send-otp', () => {
  it('returns 200', async () => {
    const app = await createTestApp();
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/send-otp',
      payload: { phoneNumber: '+391234567890' },
    });
    expect(res.statusCode).toBe(200);
  });
});

describe('POST /api/auth/verify-otp', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns register status for unknown phone', async () => {
    const app = await createTestApp();
    db.bannedPhone.findUnique.mockResolvedValue(null);
    db.user.findUnique.mockResolvedValue(null);

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-otp',
      payload: { phoneNumber: '+391234567890', code: '123456' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'register' });
  });

  it('returns tokens for a known active user', async () => {
    const app = await createTestApp();
    const user = makeUser();
    db.bannedPhone.findUnique.mockResolvedValue(null);
    db.user.findUnique.mockResolvedValue(user);
    db.refreshToken.create.mockResolvedValue({});

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-otp',
      payload: { phoneNumber: user.phoneNumber, code: '123456' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'ok', accessToken: expect.any(String) });
  });

  it('returns 403 with contact email for banned user', async () => {
    const app = await createTestApp();
    const user = makeUser({ status: 'banned' });
    db.bannedPhone.findUnique.mockResolvedValue(null);
    db.user.findUnique.mockResolvedValue(user);

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-otp',
      payload: { phoneNumber: user.phoneNumber, code: '123456' },
    });

    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ contact: expect.any(String) });
  });

  it('returns 403 for permanently banned phone trying to register', async () => {
    const app = await createTestApp();
    db.user.findUnique.mockResolvedValue(null);
    db.bannedPhone.findUnique.mockResolvedValue({ permanent: true });

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-otp',
      payload: { phoneNumber: '+39banned', code: '123456' },
    });

    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ contact: expect.any(String) });
  });

  it('blocks removed phone if no open cycle', async () => {
    const app = await createTestApp();
    db.user.findUnique.mockResolvedValue(null);
    db.bannedPhone.findUnique.mockResolvedValue({ permanent: false });
    db.registrationCycle.findFirst.mockResolvedValue(null);

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-otp',
      payload: { phoneNumber: '+39removed', code: '123456' },
    });

    expect(res.statusCode).toBe(403);
    expect(res.json().message).toMatch(/closed/i);
  });

  it('allows removed phone when a cycle is open', async () => {
    const app = await createTestApp();
    db.user.findUnique.mockResolvedValue(null);
    db.bannedPhone.findUnique.mockResolvedValue({ permanent: false });
    db.registrationCycle.findFirst.mockResolvedValue({ id: 'cycle-1', status: 'open' });

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-otp',
      payload: { phoneNumber: '+39removed', code: '123456' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'register' });
  });
});

describe('POST /api/auth/register', () => {
  beforeEach(() => vi.clearAllMocks());

  it('requires an open cycle', async () => {
    const app = await createTestApp();
    db.bannedPhone.findUnique.mockResolvedValue(null);
    db.registrationCycle.findFirst.mockResolvedValue(null);

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { phoneNumber: '+391111', code: '123456', name: 'A', surname: 'B', motivation: 'C' },
    });

    expect(res.statusCode).toBe(403);
  });

  it('creates user when cycle is open', async () => {
    const app = await createTestApp();
    const user = makeUser();
    db.bannedPhone.findUnique.mockResolvedValue(null);
    db.registrationCycle.findFirst.mockResolvedValue({ id: 'cycle-1', status: 'open' });
    db.user.findUnique.mockResolvedValue(null);
    db.user.create.mockResolvedValue(user);
    db.refreshToken.create.mockResolvedValue({});

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { phoneNumber: user.phoneNumber, code: '123456', name: 'Test', surname: 'User', motivation: 'Join' },
    });

    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({ accessToken: expect.any(String) });
  });
});
