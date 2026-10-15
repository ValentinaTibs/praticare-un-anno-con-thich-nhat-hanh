import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createTestApp, db, makeAdmin } from './helpers.js';

async function getAdminToken(app: Awaited<ReturnType<typeof createTestApp>>) {
  const admin = makeAdmin({ role: 'super_admin' });
  db.user.findUnique.mockResolvedValue(admin);
  db.refreshToken.create.mockResolvedValue({});

  const res = await app.inject({
    method: 'POST',
    url: '/api/auth/verify-otp',
    payload: { phoneNumber: admin.phoneNumber, code: '123456' },
  });

  db.user.findUnique.mockResolvedValue(admin); // re-arm for authenticate middleware
  return res.json<{ accessToken: string }>().accessToken;
}

describe('Registration cycles', () => {
  beforeEach(() => vi.clearAllMocks());

  it('GET /api/cycles/status returns closed when no cycle exists', async () => {
    const app = await createTestApp();
    const token = await getAdminToken(app);
    db.registrationCycle.findFirst.mockResolvedValue(null);

    const res = await app.inject({
      method: 'GET',
      url: '/api/cycles/status',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ open: false });
  });

  it('POST /api/cycles/open creates a cycle and unblocks removed phones', async () => {
    const app = await createTestApp();
    const token = await getAdminToken(app);
    db.registrationCycle.findFirst.mockResolvedValue(null);
    db.bannedPhone.deleteMany.mockResolvedValue({ count: 2 });
    db.registrationCycle.create.mockResolvedValue({ id: 'cycle-1', status: 'open', openedAt: new Date() });

    const res = await app.inject({
      method: 'POST',
      url: '/api/cycles/open',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(201);
    expect(db.bannedPhone.deleteMany).toHaveBeenCalledWith({ where: { permanent: false } });
  });

  it('POST /api/cycles/open returns 409 if already open', async () => {
    const app = await createTestApp();
    const token = await getAdminToken(app);
    db.registrationCycle.findFirst.mockResolvedValue({ id: 'cycle-1', status: 'open' });

    const res = await app.inject({
      method: 'POST',
      url: '/api/cycles/open',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(409);
  });

  it('POST /api/cycles/close closes the open cycle', async () => {
    const app = await createTestApp();
    const token = await getAdminToken(app);
    db.registrationCycle.findFirst.mockResolvedValue({ id: 'cycle-1', status: 'open' });
    db.registrationCycle.update.mockResolvedValue({ id: 'cycle-1', status: 'closed' });

    const res = await app.inject({
      method: 'POST',
      url: '/api/cycles/close',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(200);
    expect(db.registrationCycle.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ status: 'closed' }) }),
    );
  });
});
