import { describe, it, expect } from 'vitest';
import { createTestApp, givenUser, givenAdmin, firebaseTokenFor, loginAs } from './helpers.js';

function verifyFirebase(app: Awaited<ReturnType<typeof createTestApp>>, email: string) {
  return app.inject({
    method: 'POST',
    url: '/api/auth/verify-firebase',
    payload: { idToken: firebaseTokenFor(email) },
  });
}

describe('Gestione utenti da parte degli admin', () => {
  it('un utente sospeso non può più accedere finché non viene riattivato', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser();

    await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/suspend`, headers });
    expect((await verifyFirebase(app, target.email)).statusCode).toBe(403);

    await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/reactivate`, headers });
    expect((await verifyFirebase(app, target.email)).statusCode).toBe(200);
  });

  it('un utente bannato non può più accedere e riceve l\'email di contatto', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser();

    const ban = await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/ban`, headers });
    expect(ban.statusCode).toBe(200);

    const login = await verifyFirebase(app, target.email);
    expect(login.statusCode).toBe(403);
    expect(login.json()).toMatchObject({ contact: 'admin@example.com' });
  });

  it('un admin non può riattivare né sospendere un utente bannato', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser();
    await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/ban`, headers });

    const reactivate = await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/reactivate`, headers });
    expect(reactivate.statusCode).toBe(409);

    const suspend = await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/suspend`, headers });
    expect(suspend.statusCode).toBe(409);

    expect((await verifyFirebase(app, target.email)).statusCode).toBe(403);
  });

  it('solo il Super Admin può revocare il ban, e l\'utente torna ad accedere', async () => {
    const app = await createTestApp();
    const target = await givenUser();
    const asAdmin = await loginAs(app, await givenAdmin());
    await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/ban`, headers: asAdmin });

    const denied = await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/unban`, headers: asAdmin });
    expect(denied.statusCode).toBe(403);

    const asSuperAdmin = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    const allowed = await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/unban`, headers: asSuperAdmin });
    expect(allowed.statusCode).toBe(200);
    expect(allowed.json()).toMatchObject({ status: 'active' });

    expect((await verifyFirebase(app, target.email)).statusCode).toBe(200);
  });

  it('non si può revocare il ban a un utente che non è bannato', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    const target = await givenUser();

    const unban = await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/unban`, headers });
    expect(unban.statusCode).toBe(409);
  });

  it('un utente rimosso sparisce e la sua email è bloccata fino al prossimo ciclo', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser();

    const remove = await app.inject({ method: 'DELETE', url: `/api/admin/${target.id}`, headers });
    expect(remove.statusCode).toBe(204);

    const lookup = await app.inject({ method: 'GET', url: `/api/users/${target.id}`, headers });
    expect(lookup.statusCode).toBe(404);

    const login = await verifyFirebase(app, target.email);
    expect(login.statusCode).toBe(403);
    expect(login.json().message).toMatch(/chiuse/i);
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
