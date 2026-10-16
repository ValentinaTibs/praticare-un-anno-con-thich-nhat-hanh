import { describe, it, expect } from 'vitest';
import { createTestApp, givenUser, givenAdmin, givenBlockedPhone, firebaseTokenFor, loginAs } from './helpers.js';

describe('Cicli di registrazione', () => {
  it('senza cicli lo stato è chiuso', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenUser());

    const res = await app.inject({ method: 'GET', url: '/api/cycles/status', headers });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ open: false });
  });

  it('il Super Admin apre un ciclo e lo stato diventa aperto', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));

    const open = await app.inject({ method: 'POST', url: '/api/cycles/open', headers });
    expect(open.statusCode).toBe(201);

    const status = await app.inject({ method: 'GET', url: '/api/cycles/status', headers });
    expect(status.json()).toMatchObject({ open: true });
  });

  it('un admin semplice non può aprire un ciclo', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());

    const res = await app.inject({ method: 'POST', url: '/api/cycles/open', headers });

    expect(res.statusCode).toBe(403);
  });

  it('non si può aprire un ciclo se ce n\'è già uno aperto', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    await app.inject({ method: 'POST', url: '/api/cycles/open', headers });

    const res = await app.inject({ method: 'POST', url: '/api/cycles/open', headers });

    expect(res.statusCode).toBe(409);
  });

  it('il Super Admin chiude il ciclo aperto', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    await app.inject({ method: 'POST', url: '/api/cycles/open', headers });

    const close = await app.inject({ method: 'POST', url: '/api/cycles/close', headers });
    expect(close.statusCode).toBe(200);

    const status = await app.inject({ method: 'GET', url: '/api/cycles/status', headers });
    expect(status.json()).toMatchObject({ open: false });
  });

  it('aprire un ciclo sblocca i numeri rimossi, non quelli bannati', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    await givenBlockedPhone('+393330000001', { permanent: false });
    await givenBlockedPhone('+393330000002', { permanent: true });

    await app.inject({ method: 'POST', url: '/api/cycles/open', headers });
    await app.inject({ method: 'POST', url: '/api/cycles/close', headers });

    const removed = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-firebase',
      payload: { idToken: firebaseTokenFor('+393330000001') },
    });
    expect(removed.json()).toMatchObject({ status: 'register' });

    const banned = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-firebase',
      payload: { idToken: firebaseTokenFor('+393330000002') },
    });
    expect(banned.statusCode).toBe(403);
  });
});
