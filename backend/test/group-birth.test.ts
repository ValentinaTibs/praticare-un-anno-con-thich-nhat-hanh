import { describe, it, expect } from 'vitest';
import { prisma } from '../src/config/prisma.js';
import { processMissedConfirmations } from '../src/services/confirmation.service.js';
import { startDueGroups } from '../src/services/cycle.service.js';
import { createTestApp, givenAdmin, givenGroup, givenUser, loginAs } from './helpers.js';

type App = Awaited<ReturnType<typeof createTestApp>>;

const minutesAgo = (minutes: number) => new Date(Date.now() - minutes * 60 * 1000);
const daysAgo = (days: number) => minutesAgo(days * 24 * 60);

// Requests closed, start date just reached, job not run yet.
const givenDueCycle = (startsAt = minutesAgo(1)) =>
  prisma.registrationCycle.create({
    data: { status: 'closed', openedAt: minutesAgo(60), closedAt: minutesAgo(30), scheduledClosedAt: minutesAgo(30), startsAt },
  });

const givenRequester = async (cycle: { id: string }, overrides: Parameters<typeof givenUser>[0] = {}) => {
  const user = await givenUser({ reviewedByAdmin: true, ...overrides });
  await prisma.participationRequest.create({ data: { cycleId: cycle.id, userId: user.id } });
  return user;
};

const groups = async (app: App) => {
  const headers = await loginAs(app, await givenAdmin());
  return (await app.inject({ method: 'GET', url: '/api/groups', headers })).json();
};

describe('Nascita del gruppo', () => {
  it('alla data di inizio il richiedente revisionato entra nel gruppo e smette di essere in attesa', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle();
    const requester = await givenRequester(cycle);

    await startDueGroups();

    expect(await groups(app)).toMatchObject([{ cycleId: cycle.id, memberCount: 1 }]);
    const res = await app.inject({ method: 'GET', url: '/api/cycles/next', headers: await loginAs(app, requester) });
    expect(res.statusCode).toBe(403);
  });

  it('un ciclo con la data di inizio ancora futura non fa nascere il gruppo', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle(new Date(Date.now() + 60 * 1000));
    const requester = await givenRequester(cycle);

    await startDueGroups();

    expect(await groups(app)).toEqual([]);
    const next = await app.inject({ method: 'GET', url: '/api/cycles/next', headers: await loginAs(app, requester) });
    expect(next.json()).toMatchObject({ requested: true });
  });

  it('chi entra nel gruppo vale come appena confermato', async () => {
    const app = await createTestApp();
    const startsAt = minutesAgo(1);
    const cycle = await givenDueCycle(startsAt);
    const requester = await givenRequester(cycle, { lastConfirmedAt: daysAgo(40) });

    await startDueGroups();

    const me = await app.inject({ method: 'GET', url: '/api/users/me', headers: await loginAs(app, requester) });
    expect(me.json().lastConfirmedAt).toBe(startsAt.toISOString());
  });

  it('una conferma rimasta in sospeso non sospende chi è appena entrato nel gruppo', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle();
    const requester = await givenRequester(cycle);
    await prisma.confirmationRequest.create({ data: { userId: requester.id, dueAt: minutesAgo(1) } });

    await startDueGroups();
    await processMissedConfirmations();

    const headers = await loginAs(app, requester);
    expect((await app.inject({ method: 'GET', url: '/api/users/me', headers })).json().status).toBe('active');
    expect((await app.inject({ method: 'GET', url: '/api/confirmations/pending', headers })).json()).toBeNull();
  });

  it('il richiedente sospeso non entra nel gruppo e la sua richiesta decade', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle();
    await givenRequester(cycle);
    const suspended = await givenRequester(cycle, { status: 'suspended' });
    const admin = await loginAs(app, await givenAdmin());

    await startDueGroups();

    const res = await app.inject({ method: 'GET', url: '/api/groups', headers: admin });
    expect(res.json()).toMatchObject([{ cycleId: cycle.id, memberCount: 1 }]);
    await app.inject({ method: 'PATCH', url: `/api/admin/${suspended.id}/reactivate`, headers: admin });
    const next = await app.inject({ method: 'GET', url: '/api/cycles/next', headers: await loginAs(app, suspended) });
    expect(next.json()).toMatchObject({ requested: false });
  });

  it('senza richiedenti revisionati il gruppo non nasce', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle();
    await givenRequester(cycle, { reviewedByAdmin: false });

    await startDueGroups();

    expect(await groups(app)).toEqual([]);
  });

  it('senza richiedenti il gruppo non nasce', async () => {
    const app = await createTestApp();
    await givenDueCycle();

    await startDueGroups();

    expect(await groups(app)).toEqual([]);
  });

  it('il richiedente non revisionato resta in attesa e la sua richiesta decade', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle();
    await givenRequester(cycle);
    const notReviewed = await givenRequester(cycle, { reviewedByAdmin: false });

    await startDueGroups();

    expect(await groups(app)).toMatchObject([{ cycleId: cycle.id, memberCount: 1 }]);
    const res = await app.inject({ method: 'GET', url: '/api/cycles/next', headers: await loginAs(app, notReviewed) });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ requested: false });
  });

  it('il Super Admin vede i partecipanti del percorso iniziato al posto dei richiedenti', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle();
    await givenRequester(cycle);
    await givenRequester(cycle);
    await givenRequester(cycle, { reviewedByAdmin: false });
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));

    await startDueGroups();

    const res = await app.inject({ method: 'GET', url: '/api/cycles', headers });
    expect(res.json()).toMatchObject([{ id: cycle.id, participants: 2, requesters: 0 }]);
  });

  it('una revisione arrivata dopo la data di inizio non fa nascere un gruppo in ritardo', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle();
    const late = await givenRequester(cycle, { reviewedByAdmin: false });
    const admin = await loginAs(app, await givenAdmin());

    await startDueGroups();
    await app.inject({ method: 'PATCH', url: `/api/admin/${late.id}/review`, headers: admin });
    await startDueGroups();

    expect((await app.inject({ method: 'GET', url: '/api/groups', headers: admin })).json()).toEqual([]);
  });

  it('una revisione arrivata dopo la nascita non aggiunge nessuno al gruppo', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle();
    await givenRequester(cycle);
    const late = await givenRequester(cycle, { reviewedByAdmin: false });
    const admin = await loginAs(app, await givenAdmin());

    await startDueGroups();
    await app.inject({ method: 'PATCH', url: `/api/admin/${late.id}/review`, headers: admin });
    await startDueGroups();

    const res = await app.inject({ method: 'GET', url: '/api/groups', headers: admin });
    expect(res.json()).toMatchObject([{ cycleId: cycle.id, memberCount: 1 }]);
  });

  it('chi è già stato revisionato in un percorso finito entra senza una nuova revisione', async () => {
    const app = await createTestApp();
    const past = await prisma.registrationCycle.create({
      data: {
        status: 'closed',
        startsAt: daysAgo(400),
        group: { create: { startedAt: daysAgo(400), endedAt: daysAgo(35) } },
      },
      include: { group: true },
    });
    const cycle = await givenDueCycle();
    const veteran = await givenRequester(cycle, { group: { connect: { id: past.group!.id } } });
    const headers = await loginAs(app, veteran);

    await startDueGroups();

    const me = (await app.inject({ method: 'GET', url: '/api/users/me', headers })).json();
    expect(me.group.startedAt).toBe(cycle.startsAt.toISOString());
  });

  it('un utente già in un gruppo attivo non viene spostato nel nuovo gruppo', async () => {
    const app = await createTestApp();
    const active = await givenGroup();
    const cycle = await givenDueCycle();
    const member = await givenRequester(cycle, { group: { connect: { id: active.id } } });
    const headers = await loginAs(app, member);

    await startDueGroups();

    const me = (await app.inject({ method: 'GET', url: '/api/users/me', headers })).json();
    expect(me.group.id).toBe(active.id);
  });

  it('dopo uno spegnimento del server il gruppo nasce alla ripartenza con la sua data di inizio', async () => {
    const app = await createTestApp();
    const startsAt = daysAgo(3);
    const cycle = await givenDueCycle(startsAt);
    await givenRequester(cycle);

    await startDueGroups();

    expect(await groups(app)).toMatchObject([{ cycleId: cycle.id, startedAt: startsAt.toISOString() }]);
  });

  it('eseguire di nuovo il controllo non crea un secondo gruppo per lo stesso ciclo', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle();
    await givenRequester(cycle);

    await startDueGroups();
    await startDueGroups();

    expect(await groups(app)).toMatchObject([{ cycleId: cycle.id, memberCount: 1 }]);
  });

  it('due controlli in parallelo creano un solo gruppo senza errori', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle();
    await givenRequester(cycle);
    await givenRequester(cycle);

    const runs = await Promise.allSettled([startDueGroups(), startDueGroups(), startDueGroups()]);

    expect(runs.map(({ status }) => status)).toEqual(['fulfilled', 'fulfilled', 'fulfilled']);
    expect(await groups(app)).toMatchObject([{ cycleId: cycle.id, memberCount: 2 }]);
  });

  it('alla data di inizio le email dei rimossi vengono cancellate, anche senza altre richieste', async () => {
    const app = await createTestApp();
    const cycle = await givenDueCycle(new Date(Date.now() + 60 * 1000));
    const later = await givenDueCycle(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000));
    const removed = await givenRequester(cycle, { email: 'rimosso@test.local' });
    const removedLater = await givenRequester(later, { email: 'rimosso-dopo@test.local' });
    const headers = await loginAs(app, await givenAdmin());
    for (const user of [removed, removedLater]) {
      expect((await app.inject({ method: 'DELETE', url: `/api/admin/${user.id}`, headers })).statusCode).toBe(204);
    }
    await prisma.registrationCycle.update({ where: { id: cycle.id }, data: { startsAt: minutesAgo(1) } });

    await startDueGroups();

    expect(await prisma.removedRequester.findMany()).toEqual([{ cycleId: later.id, email: 'rimosso-dopo@test.local' }]);
  });
});
