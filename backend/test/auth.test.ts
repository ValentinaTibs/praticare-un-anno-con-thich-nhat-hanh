import { describe, it, expect } from 'vitest';
import {
  createTestApp,
  givenUser,
  givenOpenCycle,
  givenBlockedEmail,
  firebaseTokenFor,
  unverifiedFirebaseTokenFor,
  loginAs,
} from './helpers.js';

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
    await givenBlockedEmail('bannata@test.local', { permanent: true });

    const res = await verifyFirebase(app, 'bannata@test.local');

    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ contact: 'admin@example.com' });
  });

  it('un\'email rimossa non può rientrare a ciclo chiuso', async () => {
    const app = await createTestApp();
    await givenBlockedEmail('rimossa@test.local', { permanent: false });

    const res = await verifyFirebase(app, 'rimossa@test.local');

    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ code: 'registrations_closed' });
  });

  it('un\'email rimossa viene mandata alla registrazione a ciclo aperto', async () => {
    const app = await createTestApp();
    await givenBlockedEmail('rimossa@test.local', { permanent: false });
    await givenOpenCycle();

    const res = await verifyFirebase(app, 'rimossa@test.local');

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'register' });
  });
});

describe('POST /api/auth/register', () => {
  it('a ciclo chiuso la registrazione è rifiutata', async () => {
    const app = await createTestApp();

    const res = await register(app, 'anna@test.local');

    expect(res.statusCode).toBe(403);
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

  it('un\'email rimossa può registrarsi di nuovo a ciclo aperto', async () => {
    const app = await createTestApp();
    await givenOpenCycle();
    await givenBlockedEmail('rimossa@test.local', { permanent: false });

    const res = await register(app, 'rimossa@test.local');
    expect(res.statusCode).toBe(201);

    const login = await verifyFirebase(app, 'rimossa@test.local');
    expect(login.json()).toMatchObject({ status: 'ok' });
  });
});
