import { describe, it, expect } from 'vitest';
import { prisma } from '../src/config/prisma.js';
import {
  createTestApp,
  givenUser,
  givenAdmin,
  givenGroup,
  givenMember,
  givenOpenSharingChannel,
  firebaseTokenFor,
  loginAs,
} from './helpers.js';

// The actions an admin takes on someone else's account, all subject to the role check.
// Reactivation is not among them: any admin reactivates anyone (see its own test).
function actionsOn(id: string) {
  return [
    ['PATCH', `/api/admin/${id}/suspend`],
    ['PATCH', `/api/admin/${id}/ban`],
    ['DELETE', `/api/admin/${id}`],
  ] as const;
}

// Runs once right after the next user lookup by a route (findTarget), as if another
// admin acted in that instant: the write that follows must not overwrite that change.
let afterNextLookup: (() => Promise<unknown>) | null = null;
prisma.$use(async (params, next) => {
  const result = await next(params);
  if (afterNextLookup && params.model === 'User' && params.action === 'findUniqueOrThrow') {
    const hook = afterNextLookup;
    afterNextLookup = null;
    await hook();
  }
  return result;
});

// Bans [user] the way PATCH /ban does.
function banInTheMeantime(user: { id: string; email: string }) {
  afterNextLookup = () =>
    prisma.$transaction([
      prisma.user.update({ where: { id: user.id }, data: { status: 'banned' } }),
      prisma.bannedEmail.upsert({
        where: { email: user.email },
        update: {},
        create: { email: user.email },
      }),
    ]);
}

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

  it('un utente rimosso sparisce e può registrarsi di nuovo subito, a ciclo chiuso', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser();

    const remove = await app.inject({ method: 'DELETE', url: `/api/admin/${target.id}`, headers });
    expect(remove.statusCode).toBe(204);

    const lookup = await app.inject({ method: 'GET', url: `/api/users/${target.id}`, headers });
    expect(lookup.statusCode).toBe(404);

    const login = await verifyFirebase(app, target.email);
    expect(login.json()).toMatchObject({ status: 'register' });

    const again = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { idToken: firebaseTokenFor(target.email), name: 'Anna', surname: 'Rossi', motivation: 'Ricominciare' },
    });
    expect(again.statusCode).toBe(201);
  });

  it('un utente bannato non può essere rimosso: account e blocco permanente restano', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser();
    await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/ban`, headers });

    const remove = await app.inject({ method: 'DELETE', url: `/api/admin/${target.id}`, headers });
    expect(remove.statusCode).toBe(409);
    expect(remove.json().message).toBe('Un utente bannato non può essere rimosso');

    const lookup = await app.inject({ method: 'GET', url: `/api/users/${target.id}`, headers });
    expect(lookup.json()).toMatchObject({ status: 'banned' });

    const login = await verifyFirebase(app, target.email);
    expect(login.statusCode).toBe(403);
    expect(login.json()).toMatchObject({ contact: 'admin@example.com' });
  });

  it('chi ha scritto nel cerchio aperto viene rimosso insieme ai suoi messaggi', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const anna = await givenMember(group);
    const marco = await loginAs(app, await givenMember(group));
    const asAnna = await loginAs(app, anna);
    for (const member of [asAnna, marco]) {
      await app.inject({ method: 'POST', url: '/api/sharing-channel/join', headers: member });
    }
    await app.inject({ method: 'POST', url: '/api/sharing-channel/posts', headers: asAnna, payload: { content: 'Ciao' } });

    const remove = await app.inject({ method: 'DELETE', url: `/api/admin/${anna.id}`, headers });
    expect(remove.statusCode).toBe(204);

    const posts = await app.inject({ method: 'GET', url: '/api/sharing-channel/posts', headers: marco });
    expect(posts.json()).toEqual([]);
  });

  it('un admin non può sospendere, bannare o rimuovere il Super Admin, che continua ad accedere', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const superAdmin = await givenAdmin({ role: 'super_admin' });

    for (const [method, url] of actionsOn(superAdmin.id)) {
      const res = await app.inject({ method, url, headers });
      expect(res.statusCode, `${method} ${url}`).toBe(403);
      expect(res.json().message).toBe('Non puoi eseguire questa azione su questo utente');
    }

    expect((await verifyFirebase(app, superAdmin.email)).statusCode).toBe(200);
  });

  it('nessuno può sospendere, bannare o rimuovere sé stesso', async () => {
    const app = await createTestApp();
    for (const role of ['admin', 'super_admin'] as const) {
      const self = await givenAdmin({ role });
      const headers = await loginAs(app, self);

      for (const [method, url] of actionsOn(self.id)) {
        const res = await app.inject({ method, url, headers });
        expect(res.statusCode, `${role} ${method} ${url}`).toBe(403);
      }
      expect((await verifyFirebase(app, self.email)).statusCode).toBe(200);
    }
  });

  it('solo il Super Admin può sospendere un admin', async () => {
    const app = await createTestApp();
    const target = await givenAdmin();

    const asAdmin = await loginAs(app, await givenAdmin());
    const denied = await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/suspend`, headers: asAdmin });
    expect(denied.statusCode).toBe(403);

    const asSuperAdmin = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    const allowed = await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/suspend`, headers: asSuperAdmin });
    expect(allowed.statusCode).toBe(200);
    expect(allowed.json()).toMatchObject({ status: 'suspended' });
  });

  it('qualunque admin riattiva un admin o il Super Admin sospeso', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());

    for (const role of ['admin', 'super_admin'] as const) {
      const target = await givenAdmin({ role, status: 'suspended' });
      const res = await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/reactivate`, headers });
      expect(res.statusCode, role).toBe(200);
      expect(res.json()).toMatchObject({ status: 'active' });
      expect((await verifyFirebase(app, target.email)).statusCode, role).toBe(200);
    }
  });

  it('nessuno può revisionare il proprio account', async () => {
    const app = await createTestApp();
    const self = await givenAdmin({ reviewedByAdmin: false });
    const headers = await loginAs(app, self);

    const res = await app.inject({ method: 'PATCH', url: `/api/admin/${self.id}/review`, headers });
    expect(res.statusCode).toBe(403);
    expect(res.json().message).toBe('Non puoi revisionare il tuo account');

    const pending = await app.inject({ method: 'GET', url: '/api/users?reviewed=false', headers });
    expect(pending.json().users.map((u: { id: string }) => u.id)).toContain(self.id);
  });

  it('un ban arrivato durante la rimozione non viene annullato', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser();

    banInTheMeantime(target);
    const remove = await app.inject({ method: 'DELETE', url: `/api/admin/${target.id}`, headers });
    expect(remove.statusCode).toBe(409);
    expect(remove.json().message).toBe('Un utente bannato non può essere rimosso');

    expect(await prisma.user.findUnique({ where: { id: target.id } })).toMatchObject({ status: 'banned' });
    expect(await prisma.bannedEmail.findUnique({ where: { email: target.email } })).not.toBeNull();
  });

  it('un ban arrivato durante una sospensione o una riattivazione non viene annullato', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const target = await givenUser();
    banInTheMeantime(target);
    const suspend = await app.inject({ method: 'PATCH', url: `/api/admin/${target.id}/suspend`, headers });
    expect(suspend.statusCode).toBe(409);
    expect(suspend.json().message).toBe('Solo un utente attivo può essere sospeso');

    const other = await givenUser({ status: 'suspended' });
    banInTheMeantime(other);
    const reactivate = await app.inject({ method: 'PATCH', url: `/api/admin/${other.id}/reactivate`, headers });
    expect(reactivate.statusCode).toBe(409);
    expect(reactivate.json().message).toBe('Solo un utente sospeso può essere riattivato');

    for (const user of [target, other]) {
      expect(await prisma.user.findUnique({ where: { id: user.id } })).toMatchObject({ status: 'banned' });
    }
  });

  it('le azioni su un utente che non esiste rispondono 404', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const missing = '00000000-0000-0000-0000-000000000000';

    for (const [method, url] of [
      ...actionsOn(missing),
      ['PATCH', `/api/admin/${missing}/reactivate`] as const,
      ['PATCH', `/api/admin/${missing}/review`] as const,
    ]) {
      const res = await app.inject({ method, url, headers });
      expect(res.statusCode, `${method} ${url}`).toBe(404);
      expect(res.json().message).toBe('Elemento non trovato');
    }
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
