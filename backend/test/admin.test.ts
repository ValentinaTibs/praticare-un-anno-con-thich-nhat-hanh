import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createTestApp, db, makeUser, makeAdmin } from './helpers.js';

async function loginAs(app: Awaited<ReturnType<typeof createTestApp>>, user: ReturnType<typeof makeUser>) {
  db.user.findUnique.mockResolvedValueOnce(user);
  db.refreshToken.create.mockResolvedValue({});
  const res = await app.inject({
    method: 'POST',
    url: '/api/auth/verify-otp',
    payload: { phoneNumber: user.phoneNumber, code: '123456' },
  });
  db.user.findUnique.mockResolvedValue(user);
  return res.json<{ accessToken: string }>().accessToken;
}

describe('Admin — ban', () => {
  beforeEach(() => vi.clearAllMocks());

  it('PATCH /:id/ban sets status to banned and blocks phone permanently', async () => {
    const app = await createTestApp();
    const token = await loginAs(app, makeAdmin());
    const target = makeUser({ id: 'target-1', phoneNumber: '+39999' });

    db.user.findUniqueOrThrow.mockResolvedValue(target);
    db.user.update.mockResolvedValue({ ...target, status: 'banned' });
    db.bannedPhone.upsert.mockResolvedValue({});
    db.$transaction.mockResolvedValue([{ status: 'banned' }, {}]);

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/admin/${target.id}/ban`,
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'banned' });
  });

  it('DELETE /:id removes user and temporarily blocks phone', async () => {
    const app = await createTestApp();
    const token = await loginAs(app, makeAdmin());
    const target = makeUser({ id: 'target-2', phoneNumber: '+39888' });

    db.user.findUniqueOrThrow.mockResolvedValue(target);
    db.mainChannelPost.updateMany.mockResolvedValue({ count: 0 });
    db.bannedPhone.upsert.mockResolvedValue({});
    db.user.delete.mockResolvedValue(target);
    db.$transaction.mockResolvedValue([{}, target]);

    const res = await app.inject({
      method: 'DELETE',
      url: `/api/admin/${target.id}`,
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(204);
    expect(db.mainChannelPost.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ data: { isDraft: true } }),
    );
  });

  it('PATCH /:id/review marks user as reviewed', async () => {
    const app = await createTestApp();
    const token = await loginAs(app, makeAdmin());

    db.user.update.mockResolvedValue({ id: 'user-1', reviewedByAdmin: true });

    const res = await app.inject({
      method: 'PATCH',
      url: '/api/admin/user-1/review',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ reviewedByAdmin: true });
  });

  it('PATCH /:id/role requires super_admin', async () => {
    const app = await createTestApp();
    const token = await loginAs(app, makeAdmin()); // regular admin, not super_admin

    const res = await app.inject({
      method: 'PATCH',
      url: '/api/admin/user-1/role',
      headers: { authorization: `Bearer ${token}` },
      payload: { role: 'admin' },
    });

    expect(res.statusCode).toBe(403);
  });
});
