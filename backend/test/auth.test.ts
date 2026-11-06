import { describe, it, expect } from 'vitest';
import {
  createTestApp,
  givenUser,
  givenAdmin,
  givenGroup,
  givenMember,
  givenOpenCycle,
  givenBannedEmail,
  firebaseTokenFor,
  unverifiedFirebaseTokenFor,
  loginAs,
} from './helpers.js';
import { prisma } from '../src/config/prisma.js';

type App = Awaited<ReturnType<typeof createTestApp>>;

function verifyFirebase(app: App, email: string, idToken = firebaseTokenFor(email)) {
  return app.inject({
    method: 'POST',
    url: '/api/auth/verify-firebase',
    payload: { idToken },
  });
}

function register(app: App, email: string, idToken = firebaseTokenFor(email)) {
  return app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { idToken, name: 'Anna', surname: 'Rossi', motivation: 'Crescere' },
  });
}

describe('POST /api/auth/verify-firebase', () => {
  it('l\'accesso dice il gruppo dell\'utente, come /api/users/me', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    const member = await givenMember(group);

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-firebase',
      payload: { idToken: firebaseTokenFor(member.email) },
    });

    expect(res.json().user.group).toMatchObject({ id: group.id, endedAt: null });
  });

  it('un utente attivo ottiene un token e legge il proprio profilo', async () => {
    const app = await createTestApp();
    await givenUser({ email: 'anna@test.local', name: 'Anna' });

    const login = await verifyFirebase(app, 'anna@test.local');
    expect(login.statusCode).toBe(200);

    const me = await app.inject({
      method: 'GET',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${login.json().accessToken}` },
    });
    expect(me.statusCode).toBe(200);
    expect(me.json()).toMatchObject({ name: 'Anna', email: 'anna@test.local' });
  });

  it('rifiuta un token Firebase non valido', async () => {
    const app = await createTestApp();

    const res = await verifyFirebase(app, 'anna@test.local', 'not-a-valid-token');

    expect(res.statusCode).toBe(401);
  });

  it('un\'email non ancora verificata riceve 403', async () => {
    const app = await createTestApp();
    await givenUser({ email: 'anna@test.local' });

    const res = await verifyFirebase(app, 'anna@test.local', unverifiedFirebaseTokenFor('anna@test.local'));

    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ code: 'email_not_verified' });
  });

  it('l\'email nel token è confrontata senza distinguere maiuscole e minuscole', async () => {
    const app = await createTestApp();
    const anna = await givenUser({ email: 'anna@test.local' });

    const res = await verifyFirebase(app, ' Anna@Test.Local ');

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'ok', user: { id: anna.id, email: 'anna@test.local' } });
  });

  it('un\'email sconosciuta viene mandata alla registrazione', async () => {
    const app = await createTestApp();

    const res = await verifyFirebase(app, 'nuova@test.local');

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'register', email: 'nuova@test.local' });
  });

  it('un utente bannato riceve 403 con l\'email di contatto', async () => {
    const app = await createTestApp();
    await givenUser({ email: 'bannato@test.local', status: 'banned' });

    const res = await verifyFirebase(app, 'bannato@test.local');

    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ contact: 'admin@example.com' });
  });

  it('un\'email bannata per sempre riceve 403 con l\'email di contatto', async () => {
    const app = await createTestApp();
    await givenBannedEmail('bannata@test.local');

    const res = await verifyFirebase(app, 'bannata@test.local');

    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ contact: 'admin@example.com' });
  });
});

describe('POST /api/auth/register', () => {
  it('a ciclo chiuso la registrazione riesce e l\'utente può accedere', async () => {
    const app = await createTestApp();

    const res = await register(app, 'anna@test.local');
    expect(res.statusCode).toBe(201);

    const login = await verifyFirebase(app, 'anna@test.local');
    expect(login.json()).toMatchObject({ status: 'ok', user: { id: res.json().user.id, status: 'active' } });
  });

  it('a ciclo aperto crea l\'utente, che poi può accedere', async () => {
    const app = await createTestApp();
    await givenOpenCycle();

    const res = await register(app, 'anna@test.local');
    expect(res.statusCode).toBe(201);

    const headers = await loginAs(app, { email: 'anna@test.local' });
    const me = await app.inject({ method: 'GET', url: '/api/users/me', headers });
    expect(me.json()).toMatchObject({ name: 'Anna', surname: 'Rossi', status: 'active', email: 'anna@test.local' });
  });

  it('l\'utente nasce in attesa, senza gruppo e non revisionato, anche a ciclo aperto', async () => {
    const app = await createTestApp();
    await givenOpenCycle();

    const res = await register(app, 'anna@test.local');
    expect(res.statusCode).toBe(201);

    const me = await app.inject({ method: 'GET', url: '/api/users/me', headers: await loginAs(app, { email: 'anna@test.local' }) });
    expect(me.json()).toMatchObject({ status: 'active', group: null });

    const adminHeaders = await loginAs(app, await givenAdmin());
    const pending = await app.inject({ method: 'GET', url: '/api/users?reviewed=false', headers: adminHeaders });
    expect(pending.json().users.map((u: { id: string }) => u.id)).toContain(res.json().user.id);
  });

  it('rifiuta un token Firebase non valido', async () => {
    const app = await createTestApp();
    await givenOpenCycle();

    const res = await register(app, 'anna@test.local', 'not-a-valid-token');

    expect(res.statusCode).toBe(401);
  });

  it('un\'email non ancora verificata riceve 403 e l\'utente non viene creato', async () => {
    const app = await createTestApp();
    await givenOpenCycle();

    const res = await register(app, 'anna@test.local', unverifiedFirebaseTokenFor('anna@test.local'));
    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ code: 'email_not_verified' });

    const login = await verifyFirebase(app, 'anna@test.local');
    expect(login.json()).toMatchObject({ status: 'register' });
  });

  it('salva l\'email in minuscolo', async () => {
    const app = await createTestApp();
    await givenOpenCycle();

    const res = await register(app, 'Anna@Test.Local');
    expect(res.statusCode).toBe(201);
    expect(res.json().user.email).toBe('anna@test.local');

    const login = await verifyFirebase(app, 'anna@test.local');
    expect(login.json()).toMatchObject({ status: 'ok', user: { id: res.json().user.id } });
  });

  it('un\'email già registrata riceve 409', async () => {
    const app = await createTestApp();
    await givenOpenCycle();
    await givenUser({ email: 'anna@test.local' });

    const res = await register(app, 'anna@test.local');

    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ message: 'Email già registrata' });
  });

  it('registrarsi due volte con la stessa email dà 409 la seconda volta', async () => {
    const app = await createTestApp();
    await givenOpenCycle();

    expect((await register(app, 'anna@test.local')).statusCode).toBe(201);
    expect((await register(app, 'ANNA@test.local')).statusCode).toBe(409);
  });
});

describe('POST /api/auth/logout', () => {
  const logout = (app: App, refreshToken: string, headers: Record<string, string> = {}) =>
    app.inject({ method: 'POST', url: '/api/auth/logout', payload: { refreshToken }, headers });
  const refresh = (app: App, refreshToken: string) =>
    app.inject({ method: 'POST', url: '/api/auth/refresh', payload: { refreshToken } });

  async function signedIn(app: App) {
    const user = await givenUser();
    const login = await verifyFirebase(app, user.email);
    return { user, tokens: login.json() as { accessToken: string; refreshToken: string } };
  }

  it('revoca il refresh token di chi esce', async () => {
    const app = await createTestApp();
    const { tokens } = await signedIn(app);

    const res = await logout(app, tokens.refreshToken, { authorization: `Bearer ${tokens.accessToken}` });

    expect(res.statusCode).toBe(200);
    expect((await refresh(app, tokens.refreshToken)).statusCode).toBe(401);
  });

  it('lo revoca anche con il token d\'accesso scaduto, senza costringere a un refresh', async () => {
    const app = await createTestApp();
    const { tokens } = await signedIn(app);

    const res = await logout(app, tokens.refreshToken, { authorization: 'Bearer scaduto' });

    expect(res.statusCode).toBe(200);
    expect((await refresh(app, tokens.refreshToken)).statusCode).toBe(401);
  });

  it('lo revoca anche per un utente sospeso nel frattempo', async () => {
    const app = await createTestApp();
    const { user, tokens } = await signedIn(app);
    await prisma.user.update({ where: { id: user.id }, data: { status: 'suspended' } });

    const res = await logout(app, tokens.refreshToken, { authorization: `Bearer ${tokens.accessToken}` });

    expect(res.statusCode).toBe(200);
    expect((await refresh(app, tokens.refreshToken)).statusCode).toBe(401);
  });

  it('non revoca gli altri refresh token dello stesso utente', async () => {
    const app = await createTestApp();
    const { user, tokens } = await signedIn(app);
    const other = (await verifyFirebase(app, user.email)).json() as { refreshToken: string };

    await logout(app, tokens.refreshToken);

    expect((await refresh(app, other.refreshToken)).statusCode).toBe(200);
  });

  it('un refresh token sconosciuto non è un errore', async () => {
    const app = await createTestApp();

    expect((await logout(app, 'sconosciuto')).statusCode).toBe(200);
  });
});
