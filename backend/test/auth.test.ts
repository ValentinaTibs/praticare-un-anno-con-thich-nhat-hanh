import { describe, it, expect } from 'vitest';
import {
  createTestApp,
  givenUser,
  givenOpenCycle,
  givenBlockedPhone,
  firebaseTokenFor,
  loginAs,
} from './helpers.js';

function verifyFirebase(app: Awaited<ReturnType<typeof createTestApp>>, phoneNumber: string) {
  return app.inject({
    method: 'POST',
    url: '/api/auth/verify-firebase',
    payload: { idToken: firebaseTokenFor(phoneNumber) },
  });
}

function register(app: Awaited<ReturnType<typeof createTestApp>>, phoneNumber: string) {
  return app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { idToken: firebaseTokenFor(phoneNumber), name: 'Anna', surname: 'Rossi', motivation: 'Crescere' },
  });
}

describe('POST /api/auth/verify-firebase', () => {
  it('un utente attivo ottiene un token e legge il proprio profilo', async () => {
    const app = await createTestApp();
    await givenUser({ phoneNumber: '+393331112222', name: 'Anna' });

    const login = await verifyFirebase(app, '+393331112222');
    expect(login.statusCode).toBe(200);

    const me = await app.inject({
      method: 'GET',
      url: '/api/users/me',
      headers: { authorization: `Bearer ${login.json().accessToken}` },
    });
    expect(me.statusCode).toBe(200);
    expect(me.json()).toMatchObject({ name: 'Anna', phoneNumber: '+393331112222' });
  });

  it('rifiuta un token Firebase non valido', async () => {
    const app = await createTestApp();

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-firebase',
      payload: { idToken: 'not-a-valid-token' },
    });

    expect(res.statusCode).toBe(401);
  });

  it('un numero sconosciuto viene mandato alla registrazione', async () => {
    const app = await createTestApp();

    const res = await verifyFirebase(app, '+393339990000');

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'register' });
  });

  it('un utente bannato riceve 403 con l\'email di contatto', async () => {
    const app = await createTestApp();
    await givenUser({ phoneNumber: '+393331110000', status: 'banned' });

    const res = await verifyFirebase(app, '+393331110000');

    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ contact: 'admin@example.com' });
  });

  it('un numero bannato per sempre riceve 403 con l\'email di contatto', async () => {
    const app = await createTestApp();
    await givenBlockedPhone('+393332220000', { permanent: true });

    const res = await verifyFirebase(app, '+393332220000');

    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ contact: 'admin@example.com' });
  });

  it('un numero rimosso non può rientrare a ciclo chiuso', async () => {
    const app = await createTestApp();
    await givenBlockedPhone('+393333330000', { permanent: false });

    const res = await verifyFirebase(app, '+393333330000');

    expect(res.statusCode).toBe(403);
    expect(res.json().message).toMatch(/closed/i);
  });

  it('un numero rimosso viene mandato alla registrazione a ciclo aperto', async () => {
    const app = await createTestApp();
    await givenBlockedPhone('+393334440000', { permanent: false });
    await givenOpenCycle();

    const res = await verifyFirebase(app, '+393334440000');

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'register' });
  });
});

describe('POST /api/auth/register', () => {
  it('a ciclo chiuso la registrazione è rifiutata', async () => {
    const app = await createTestApp();

    const res = await register(app, '+393335550000');

    expect(res.statusCode).toBe(403);
  });

  it('a ciclo aperto crea l\'utente, che poi può accedere', async () => {
    const app = await createTestApp();
    await givenOpenCycle();

    const res = await register(app, '+393336660000');
    expect(res.statusCode).toBe(201);

    const headers = await loginAs(app, { phoneNumber: '+393336660000' });
    const me = await app.inject({ method: 'GET', url: '/api/users/me', headers });
    expect(me.json()).toMatchObject({ name: 'Anna', surname: 'Rossi', status: 'active' });
  });

  it('un numero già registrato riceve 409', async () => {
    const app = await createTestApp();
    await givenOpenCycle();
    await givenUser({ phoneNumber: '+393337770000' });

    const res = await register(app, '+393337770000');

    expect(res.statusCode).toBe(409);
  });

  it('un numero rimosso può registrarsi di nuovo a ciclo aperto', async () => {
    const app = await createTestApp();
    await givenOpenCycle();
    await givenBlockedPhone('+393338880000', { permanent: false });

    const res = await register(app, '+393338880000');
    expect(res.statusCode).toBe(201);

    const login = await verifyFirebase(app, '+393338880000');
    expect(login.json()).toMatchObject({ status: 'ok' });
  });
});
