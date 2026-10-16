import { describe, it, expect } from 'vitest';
import { createTestApp, givenUser, givenAdmin, firebaseTokenFor, loginAs } from './helpers.js';

function verifyFirebase(app: Awaited<ReturnType<typeof createTestApp>>, phoneNumber: string) {
  return app.inject({
    method: 'POST',
    url: '/api/auth/verify-firebase',
    payload: { idToken: firebaseTokenFor(phoneNumber) },
  });
}

describe('Gestione utenti da parte degli admin', () => {
  it('un utente sospeso non può più accedere finché non viene riattivato', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser();

    await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/suspend`, headers });
    expect((await verifyFirebase(app, target.phoneNumber)).statusCode).toBe(403);

    await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/reactivate`, headers });
    expect((await verifyFirebase(app, target.phoneNumber)).statusCode).toBe(200);
  });

  it('un utente bannato non può più accedere e riceve l\'email di contatto', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser();

    const ban = await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/ban`, headers });
    expect(ban.statusCode).toBe(200);

    const login = await verifyFirebase(app, target.phoneNumber);
    expect(login.statusCode).toBe(403);
    expect(login.json()).toMatchObject({ contact: 'admin@example.com' });
  });

  it('un utente rimosso sparisce e il suo numero è bloccato fino al prossimo ciclo', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser();

    const remove = await app.inject({ method: 'DELETE', url: `/api/admin/${target.id}`, headers });
    expect(remove.statusCode).toBe(204);

    const lookup = await app.inject({ method: 'GET', url: `/api/users/${target.id}`, headers });
    expect(lookup.statusCode).toBe(404);

    const login = await verifyFirebase(app, target.phoneNumber);
    expect(login.statusCode).toBe(403);
    expect(login.json().message).toMatch(/closed/i);
  });

  it('un admin segna un nuovo utente come esaminato', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser({ reviewedByAdmin: false });

    await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/review`, headers });

    const pending = await app.inject({ method: 'GET', url: '/api/users?reviewed=false', headers });
    expect(pending.json().users.map((u: { id: string }) => u.id)).not.toContain(target.id);
  });

  it('solo il Super Admin può cambiare il ruolo di un utente', async () => {
    const app = await createTestApp();
    const target = await givenUser();

    const asAdmin = await loginAs(app, await givenAdmin());
    const denied = await app.inject({
      method: 'PATCH',
      url: `/api/admin/${target.id}/role`,
      headers: asAdmin,
      payload: { role: 'admin' },
    });
    expect(denied.statusCode).toBe(403);

    const asSuperAdmin = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    const allowed = await app.inject({
      method: 'PATCH',
      url: `/api/admin/${target.id}/role`,
      headers: asSuperAdmin,
      payload: { role: 'admin' },
    });
    expect(allowed.statusCode).toBe(200);

    const lookup = await app.inject({ method: 'GET', url: `/api/users/${target.id}`, headers: asSuperAdmin });
    expect(lookup.json()).toMatchObject({ role: 'admin' });
  });
});
