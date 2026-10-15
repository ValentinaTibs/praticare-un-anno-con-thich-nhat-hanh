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
  db.user.findUnique.mockResolvedValue(user); // re-arm authenticate
  return res.json<{ accessToken: string }>().accessToken;
}

describe('Sharing channel', () => {
  beforeEach(() => vi.clearAllMocks());

  it('GET /status returns closed when no channel open', async () => {
    const app = await createTestApp();
    const token = await loginAs(app, makeUser());
    db.sharingChannel.findFirst.mockResolvedValue(null);

    const res = await app.inject({
      method: 'GET',
      url: '/api/sharing-channel/status',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'closed' });
  });

  it('GET /status returns open with scheduledClosedAt', async () => {
    const app = await createTestApp();
    const token = await loginAs(app, makeUser());
    const closeTime = new Date(Date.now() + 3600_000);
    db.sharingChannel.findFirst.mockResolvedValue({
      id: 'ch-1', status: 'open', openedAt: new Date(), scheduledClosedAt: closeTime,
    });
    db.sharingChannelMember.findFirst.mockResolvedValue(null);

    const res = await app.inject({
      method: 'GET',
      url: '/api/sharing-channel/status',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.json()).toMatchObject({ status: 'open', joined: false });
  });

  it('POST /open requires scheduledClosedAt', async () => {
    const app = await createTestApp();
    const token = await loginAs(app, makeAdmin());

    const res = await app.inject({
      method: 'POST',
      url: '/api/sharing-channel/open',
      headers: { authorization: `Bearer ${token}` },
      payload: {},
    });

    expect(res.statusCode).toBe(400);
  });

  it('POST /open creates channel with scheduled close time', async () => {
    const app = await createTestApp();
    const token = await loginAs(app, makeAdmin());
    const closeTime = new Date(Date.now() + 3600_000).toISOString();
    db.sharingChannel.findFirst.mockResolvedValue(null);
    db.sharingChannel.create.mockResolvedValue({
      id: 'ch-1', status: 'open', openedAt: new Date(), scheduledClosedAt: new Date(closeTime),
    });

    const res = await app.inject({
      method: 'POST',
      url: '/api/sharing-channel/open',
      headers: { authorization: `Bearer ${token}` },
      payload: { scheduledClosedAt: closeTime },
    });

    expect(res.statusCode).toBe(201);
    expect(db.sharingChannel.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ scheduledClosedAt: new Date(closeTime) }) }),
    );
  });

  it('POST /join returns history for new member', async () => {
    const app = await createTestApp();
    const user = makeUser();
    const token = await loginAs(app, user);
    const channel = { id: 'ch-1', status: 'open' };
    db.sharingChannel.findFirst.mockResolvedValue(channel);
    db.sharingChannelMember.findFirst.mockResolvedValue(null);
    db.sharingChannelMember.create.mockResolvedValue({});
    db.user.findUniqueOrThrow.mockResolvedValue(user);
    db.sharingChannelPost.findMany.mockResolvedValue([]);

    const res = await app.inject({
      method: 'POST',
      url: '/api/sharing-channel/join',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ joined: true, history: [] });
  });

  it('POST /join returns 409 if already a member', async () => {
    const app = await createTestApp();
    const token = await loginAs(app, makeUser());
    db.sharingChannel.findFirst.mockResolvedValue({ id: 'ch-1', status: 'open' });
    db.sharingChannelMember.findFirst.mockResolvedValue({ id: 'mem-1' });

    const res = await app.inject({
      method: 'POST',
      url: '/api/sharing-channel/join',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(409);
  });

  it('DELETE /leave removes membership', async () => {
    const app = await createTestApp();
    const user = makeUser();
    const token = await loginAs(app, user);
    db.sharingChannel.findFirst.mockResolvedValue({ id: 'ch-1', status: 'open' });
    db.sharingChannelMember.findFirst.mockResolvedValue({ id: 'mem-1' });
    db.sharingChannelMember.delete.mockResolvedValue({});
    db.user.findUniqueOrThrow.mockResolvedValue(user);

    const res = await app.inject({
      method: 'DELETE',
      url: '/api/sharing-channel/leave',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ left: true });
  });

  it('GET /posts returns 403 if not a member', async () => {
    const app = await createTestApp();
    const token = await loginAs(app, makeUser());
    db.sharingChannel.findFirst.mockResolvedValue({ id: 'ch-1', status: 'open' });
    db.sharingChannelMember.findFirst.mockResolvedValue(null);

    const res = await app.inject({
      method: 'GET',
      url: '/api/sharing-channel/posts',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(403);
  });
});
