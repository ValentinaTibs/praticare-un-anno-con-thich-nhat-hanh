import { describe, it, expect } from 'vitest';
import { prisma } from '../src/config/prisma.js';
import { closeExpiredCycles } from '../src/services/cycle.service.js';
import {
  createTestApp,
  givenUser,
  givenAdmin,
  givenBlockedEmail,
  givenOpenCycle,
  firebaseTokenFor,
  loginAs,
} from './helpers.js';

type App = Awaited<ReturnType<typeof createTestApp>>;
type Headers = { authorization: string };

const inDays = (days: number) => new Date(Date.now() + days * 24 * 60 * 60 * 1000);

const openCycle = (app: App, headers: Headers, scheduledClosedAt: unknown = inDays(7).toISOString()) =>
  app.inject({ method: 'POST', url: '/api/cycles/open', headers, payload: { scheduledClosedAt } });
const cycleStatus = async (app: App, headers: Headers) =>
  (await app.inject({ method: 'GET', url: '/api/cycles/status', headers })).json();

describe('Cicli di registrazione', () => {
  it('senza cicli lo stato è chiuso', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenUser());

    const res = await app.inject({ method: 'GET', url: '/api/cycles/status', headers });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ open: false });
  });

  it('il Super Admin apre un ciclo con la data di chiusura e lo stato la mostra', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    const closesAt = inDays(7).toISOString();

    const open = await openCycle(app, headers, closesAt);
    expect(open.statusCode).toBe(201);

    expect(await cycleStatus(app, headers)).toMatchObject({ open: true, scheduledClosedAt: closesAt });
  });

  it('aprire un ciclo crea il nuovo gruppo', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));

    const open = await openCycle(app, headers);

    expect(open.json().group).toMatchObject({ cycleId: open.json().id });
  });

  it('senza data di chiusura il ciclo non si apre', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));

    const res = await app.inject({ method: 'POST', url: '/api/cycles/open', headers, payload: {} });

    expect(res.statusCode).toBe(400);
    expect(await cycleStatus(app, headers)).toMatchObject({ open: false });
  });

  it('con una data di chiusura già passata il ciclo non si apre', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));

    const res = await openCycle(app, headers, inDays(-1).toISOString());

    expect(res.statusCode).toBe(400);
  });

  it('un admin semplice non può aprire un ciclo', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());

    const res = await openCycle(app, headers);

    expect(res.statusCode).toBe(403);
  });

  it('non si può aprire un ciclo se ce n\'è già uno aperto', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    await openCycle(app, headers);

    const res = await openCycle(app, headers);

    expect(res.statusCode).toBe(409);
  });

  it('il Super Admin può chiudere il ciclo prima della data', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    await openCycle(app, headers);

    const close = await app.inject({ method: 'POST', url: '/api/cycles/close', headers });
    expect(close.statusCode).toBe(200);

    expect(await cycleStatus(app, headers)).toMatchObject({ open: false });
  });

  it('alla data di chiusura il ciclo si chiude da solo', async () => {
    const cycle = await givenOpenCycle(inDays(-1));

    await closeExpiredCycles();

    const closed = await prisma.registrationCycle.findUniqueOrThrow({ where: { id: cycle.id } });
    expect(closed.status).toBe('closed');
    expect(closed.closedAt).not.toBeNull();
  });

  it('il job non chiude un ciclo prima della sua data', async () => {
    const cycle = await givenOpenCycle(inDays(1));

    await closeExpiredCycles();

    const stillOpen = await prisma.registrationCycle.findUniqueOrThrow({ where: { id: cycle.id } });
    expect(stillOpen.status).toBe('open');
  });

  it('passata la data le registrazioni sono rifiutate anche prima del job', async () => {
    const app = await createTestApp();
    await givenOpenCycle(inDays(-1));
    const headers = await loginAs(app, await givenUser());

    expect(await cycleStatus(app, headers)).toMatchObject({ open: false });

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { idToken: firebaseTokenFor('anna@test.local'), name: 'Anna', surname: 'Rossi', motivation: 'Praticare' },
    });
    expect(res.statusCode).toBe(403);
  });

  it('passata la data si può aprire un nuovo ciclo anche prima del job', async () => {
    const app = await createTestApp();
    await givenOpenCycle(inDays(-1));
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));

    const res = await openCycle(app, headers);

    expect(res.statusCode).toBe(201);
  });

  it('aprire un ciclo sblocca le email rimosse, non quelli bannati', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    await givenBlockedEmail('removed@test.local', { permanent: false });
    await givenBlockedEmail('banned@test.local', { permanent: true });

    await openCycle(app, headers);
    await app.inject({ method: 'POST', url: '/api/cycles/close', headers });

    const removed = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-firebase',
      payload: { idToken: firebaseTokenFor('removed@test.local') },
    });
    expect(removed.json()).toMatchObject({ status: 'register' });

    const banned = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-firebase',
      payload: { idToken: firebaseTokenFor('banned@test.local') },
    });
    expect(banned.statusCode).toBe(403);
  });
});
