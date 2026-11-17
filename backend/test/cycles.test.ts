import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fcm } from '../src/config/firebase.js';
import { prisma } from '../src/config/prisma.js';
import { closeExpiredCycles } from '../src/services/cycle.service.js';
import { startOfDayInRome } from '../src/utils/date.js';
import {
  createTestApp,
  givenUser,
  givenAdmin,
  givenGroup,
  givenMember,
  givenOpenCycle,
  loginAs,
} from './helpers.js';

type App = Awaited<ReturnType<typeof createTestApp>>;
type Headers = { authorization: string };

const inDays = (days: number) => new Date(Date.now() + days * 24 * 60 * 60 * 1000);

// The calendar date in Italy, days from now, as the API expects it.
const dateInDays = (days: number) =>
  new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Rome' }).format(inDays(days));

const openCycle = (app: App, headers: Headers, payload: Record<string, unknown> = {}) =>
  app.inject({
    method: 'POST',
    url: '/api/cycles/open',
    headers,
    payload: { scheduledClosedAt: inDays(7).toISOString(), startDate: dateInDays(14), ...payload },
  });
const updateCycle = (app: App, headers: Headers, id: string, payload: Record<string, unknown>) =>
  app.inject({ method: 'PATCH', url: `/api/cycles/${id}`, headers, payload });
const superAdmin = async (app: App) => loginAs(app, await givenAdmin({ role: 'super_admin' }));
const cycleStatus = async (app: App, headers: Headers) =>
  (await app.inject({ method: 'GET', url: '/api/cycles/status', headers })).json();

describe('Cicli', () => {
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

    const open = await openCycle(app, headers, { scheduledClosedAt: closesAt });
    expect(open.statusCode).toBe(201);

    expect(await cycleStatus(app, headers)).toMatchObject({ open: true, scheduledClosedAt: closesAt });
  });

  it('aprire un ciclo non crea il gruppo', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);

    const open = await openCycle(app, headers);

    expect(open.statusCode).toBe(201);
    expect(await prisma.group.count()).toBe(0);
  });

  it('la durata è di 365 giorni se non indicata', async () => {
    const app = await createTestApp();

    const open = await openCycle(app, await superAdmin(app));

    expect(open.json()).toMatchObject({ durationDays: 365 });
  });

  it('il percorso inizia alle 00:00 italiane della data indicata', async () => {
    const app = await createTestApp();

    const summer = await openCycle(app, await superAdmin(app), {
      scheduledClosedAt: '2099-07-01T00:00:00.000Z',
      startDate: '2099-07-10',
      durationDays: 100,
    });

    expect(summer.json()).toMatchObject({ startsAt: '2099-07-09T22:00:00.000Z', durationDays: 100 });
  });

  it('in inverno l\'ora italiana è un\'ora avanti rispetto a UTC', () => {
    expect(startOfDayInRome('2099-01-10')?.toISOString()).toBe('2099-01-09T23:00:00.000Z');
  });

  it('una data di inizio inesistente non è valida', () => {
    expect(startOfDayInRome('2099-02-30')).toBeNull();
  });

  it('senza data di inizio il ciclo non si apre', async () => {
    const app = await createTestApp();

    const res = await openCycle(app, await superAdmin(app), { startDate: undefined });

    expect(res.statusCode).toBe(400);
  });

  it('la chiusura non può superare l\'inizio del percorso', async () => {
    const app = await createTestApp();

    const res = await openCycle(app, await superAdmin(app), {
      scheduledClosedAt: inDays(20).toISOString(),
      startDate: dateInDays(14),
    });

    expect(res.statusCode).toBe(400);
  });

  it('la durata deve essere un numero positivo di giorni', async () => {
    const app = await createTestApp();

    const res = await openCycle(app, await superAdmin(app), { durationDays: 0 });

    expect(res.statusCode).toBe(400);
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

    const res = await openCycle(app, headers, { scheduledClosedAt: inDays(-1).toISOString() });

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

  it('passata la data il ciclo risulta chiuso anche prima del job', async () => {
    const app = await createTestApp();
    await givenOpenCycle(inDays(-1));
    const headers = await loginAs(app, await givenUser());

    expect(await cycleStatus(app, headers)).toMatchObject({ open: false });
  });

  it('passata la data si può aprire un nuovo ciclo anche prima del job', async () => {
    const app = await createTestApp();
    await givenOpenCycle(inDays(-1));
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));

    const res = await openCycle(app, headers);

    expect(res.statusCode).toBe(201);
  });

  it('con due aperture simultanee resta un solo ciclo aperto', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);

    const responses = await Promise.all([openCycle(app, headers), openCycle(app, headers)]);

    expect(responses.map((res) => res.statusCode).sort()).toEqual([201, 409]);
    expect(await prisma.registrationCycle.count({ where: { status: 'open' } })).toBe(1);
  });

  it('il database rifiuta un secondo ciclo aperto', async () => {
    await givenOpenCycle();

    await expect(givenOpenCycle()).rejects.toMatchObject({ code: 'P2002' });
  });

  describe('modifica', () => {
    it('il Super Admin modifica chiusura, inizio e durata prima dell\'inizio', async () => {
      const app = await createTestApp();
      const headers = await superAdmin(app);
      const { id } = (await openCycle(app, headers)).json();
      const closesAt = inDays(10).toISOString();

      const res = await updateCycle(app, headers, id, {
        scheduledClosedAt: closesAt,
        startDate: '2099-07-10',
        durationDays: 30,
      });

      expect(res.statusCode).toBe(200);
      expect(res.json()).toMatchObject({
        scheduledClosedAt: closesAt,
        startsAt: '2099-07-09T22:00:00.000Z',
        durationDays: 30,
      });
    });

    it('un admin semplice non può modificare un ciclo', async () => {
      const app = await createTestApp();
      const cycle = await givenOpenCycle();
      const headers = await loginAs(app, await givenAdmin());

      const res = await updateCycle(app, headers, cycle.id, { durationDays: 30 });

      expect(res.statusCode).toBe(403);
    });

    it('dopo l\'inizio non si può modificare nulla', async () => {
      const app = await createTestApp();
      const headers = await superAdmin(app);
      const group = await givenGroup();

      const res = await updateCycle(app, headers, group.cycleId, { durationDays: 30 });

      expect(res.statusCode).toBe(409);
    });

    it('anticipare l\'inizio prima della chiusura non è permesso', async () => {
      const app = await createTestApp();
      const headers = await superAdmin(app);
      const { id } = (await openCycle(app, headers)).json();

      const res = await updateCycle(app, headers, id, { startDate: dateInDays(3) });

      expect(res.statusCode).toBe(400);
    });

    it('una richiesta senza campi non è valida', async () => {
      const app = await createTestApp();
      const headers = await superAdmin(app);
      const { id } = (await openCycle(app, headers)).json();

      const res = await updateCycle(app, headers, id, {});

      expect(res.statusCode).toBe(400);
    });

    it('un ciclo inesistente dà 404', async () => {
      const app = await createTestApp();

      const res = await updateCycle(app, await superAdmin(app), 'inesistente', { durationDays: 30 });

      expect(res.statusCode).toBe(404);
    });

    it('una nuova data di chiusura riapre un ciclo chiuso', async () => {
      const app = await createTestApp();
      const headers = await superAdmin(app);
      const { id } = (await openCycle(app, headers)).json();
      await app.inject({ method: 'POST', url: '/api/cycles/close', headers });

      const res = await updateCycle(app, headers, id, { scheduledClosedAt: inDays(9).toISOString() });

      expect(res.json()).toMatchObject({ status: 'open', closedAt: null });
      expect(await cycleStatus(app, headers)).toMatchObject({ open: true, id });
    });

    it('rimandare la stessa data di chiusura non riapre un ciclo chiuso in anticipo', async () => {
      const app = await createTestApp();
      const headers = await superAdmin(app);
      const opened = (await openCycle(app, headers)).json();
      await app.inject({ method: 'POST', url: '/api/cycles/close', headers });

      const res = await updateCycle(app, headers, opened.id, {
        scheduledClosedAt: opened.scheduledClosedAt,
        durationDays: 400,
      });

      expect(res.json()).toMatchObject({ status: 'closed', durationDays: 400 });
    });

    it('un ciclo chiuso non si riapre se ce n\'è già uno aperto', async () => {
      const app = await createTestApp();
      const headers = await superAdmin(app);
      const { id } = (await openCycle(app, headers)).json();
      await app.inject({ method: 'POST', url: '/api/cycles/close', headers });
      await openCycle(app, headers);

      const res = await updateCycle(app, headers, id, { scheduledClosedAt: inDays(9).toISOString() });

      expect(res.statusCode).toBe(409);
    });

    it('spostare solo l\'inizio lascia chiuso un ciclo chiuso', async () => {
      const app = await createTestApp();
      const headers = await superAdmin(app);
      const { id } = (await openCycle(app, headers)).json();
      await app.inject({ method: 'POST', url: '/api/cycles/close', headers });

      const res = await updateCycle(app, headers, id, { startDate: dateInDays(3) });

      expect(res.statusCode).toBe(200);
      expect(res.json()).toMatchObject({ status: 'closed' });
    });
  });

  it('il Super Admin vede anche i cicli chiusi non ancora iniziati', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);
    const { id } = (await openCycle(app, headers)).json();
    await app.inject({ method: 'POST', url: '/api/cycles/close', headers });

    const res = await app.inject({ method: 'GET', url: '/api/cycles', headers });

    expect(res.json()).toMatchObject([{ id, status: 'closed' }]);
  });

  it('l\'elenco conta i richiedenti attivi e i membri del gruppo di ogni ciclo', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);
    const upcoming = await givenOpenCycle();
    for (const status of ['active', 'active', 'suspended'] as const) {
      const user = await givenUser({ status });
      await prisma.participationRequest.create({ data: { cycleId: upcoming.id, userId: user.id } });
    }
    const group = await givenGroup();
    await givenMember(group);

    const res = await app.inject({ method: 'GET', url: '/api/cycles', headers });

    expect(res.json()).toMatchObject([
      { id: upcoming.id, requesters: 2, participants: 0 },
      { id: group.cycleId, requesters: 0, participants: 1 },
    ]);
  });
});

// A phone of this user, identified by its push token.
const givenPhone = (user: { id: string }, fcmToken: string) =>
  prisma.userDevice.create({ data: { userId: user.id, fcmToken } });

const givenRequester = async (cycle: { id: string }, overrides: Parameters<typeof givenUser>[0] = {}) => {
  const user = await givenUser(overrides);
  await prisma.participationRequest.create({ data: { cycleId: cycle.id, userId: user.id } });
  return user;
};

// The texts of the push notifications Firebase was asked to deliver to this device.
const pushesReceivedBy = (fcmToken: string) =>
  vi
    .mocked(fcm.sendEachForMulticast)
    .mock.calls.filter(([message]) => message.tokens.includes(fcmToken))
    .map(([message]) => message.notification?.body);

describe('Notifiche dei cicli', () => {
  const OPENED = 'Sono aperte le richieste per il percorso che inizia il 12 gennaio';
  const MOVED = 'Il percorso a cui hai chiesto di partecipare inizierà il 19 gennaio invece del 12 gennaio';

  beforeEach(() => {
    vi.mocked(fcm.sendEachForMulticast).mockClear();
  });

  it('all\'apertura del ciclo gli utenti in attesa ricevono la data di inizio del percorso', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);
    await givenPhone(await givenUser(), 'phone-of-new-user');
    await givenPhone(await givenAdmin(), 'phone-of-waiting-admin');
    const endedGroup = await givenGroup();
    await prisma.group.update({ where: { id: endedGroup.id }, data: { endedAt: new Date() } });
    await givenPhone(await givenMember(endedGroup), 'phone-of-former-member');

    const res = await openCycle(app, headers, { startDate: '2099-01-12' });

    expect(res.statusCode).toBe(201);
    expect(pushesReceivedBy('phone-of-new-user')).toEqual([OPENED]);
    expect(pushesReceivedBy('phone-of-waiting-admin')).toEqual([OPENED]);
    expect(pushesReceivedBy('phone-of-former-member')).toEqual([OPENED]);
  });

  it('all\'apertura del ciclo non ricevono nulla i membri di un gruppo in corso, i sospesi e i bannati', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);
    await givenPhone(await givenMember(await givenGroup()), 'phone-of-member');
    await givenPhone(await givenUser({ status: 'suspended' }), 'phone-of-suspended');
    await givenPhone(await givenUser({ status: 'banned' }), 'phone-of-banned');

    await openCycle(app, headers, { startDate: '2099-01-12' });

    expect(pushesReceivedBy('phone-of-member')).toEqual([]);
    expect(pushesReceivedBy('phone-of-suspended')).toEqual([]);
    expect(pushesReceivedBy('phone-of-banned')).toEqual([]);
  });

  it('un ciclo che non si apre non manda notifiche', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);
    await givenOpenCycle();
    await givenPhone(await givenUser(), 'phone-of-new-user');

    const res = await openCycle(app, headers, { startDate: '2099-01-12' });

    expect(res.statusCode).toBe(409);
    expect(pushesReceivedBy('phone-of-new-user')).toEqual([]);
  });

  it('se la push non parte il ciclo si apre lo stesso', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);
    await givenPhone(await givenUser(), 'phone-of-new-user');
    vi.mocked(fcm.sendEachForMulticast).mockRejectedValueOnce(new Error('Firebase non raggiungibile'));

    const res = await openCycle(app, headers, { startDate: '2099-01-12' });

    expect(res.statusCode).toBe(201);
    expect(await cycleStatus(app, headers)).toMatchObject({ open: true });
  });

  it('se cambia la data di inizio i richiedenti ricevono la nuova data', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);
    const { id } = (await openCycle(app, headers, { startDate: '2099-01-12' })).json();
    const cycle = { id };
    await givenPhone(await givenRequester(cycle), 'phone-of-requester');
    await givenPhone(await givenUser(), 'phone-of-waiting-user');
    await givenPhone(await givenRequester(cycle, { status: 'suspended' }), 'phone-of-suspended-requester');
    vi.mocked(fcm.sendEachForMulticast).mockClear();

    const res = await updateCycle(app, headers, id, { startDate: '2099-01-19' });

    expect(res.statusCode).toBe(200);
    expect(pushesReceivedBy('phone-of-requester')).toEqual([MOVED]);
    expect(pushesReceivedBy('phone-of-waiting-user')).toEqual([]);
    expect(pushesReceivedBy('phone-of-suspended-requester')).toEqual([]);
  });

  it('chi ha chiesto di partecipare a un altro percorso non riceve il cambio di data', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);
    const { id } = (await openCycle(app, headers, { startDate: '2099-01-12' })).json();
    await app.inject({ method: 'POST', url: '/api/cycles/close', headers });
    const other = await givenOpenCycle(inDays(7), startOfDayInRome('2099-02-01')!);
    await givenPhone(await givenRequester(other), 'phone-of-other-requester');

    await updateCycle(app, headers, id, { startDate: '2099-01-19' });

    expect(pushesReceivedBy('phone-of-other-requester')).toEqual([]);
  });

  it('se la data di inizio resta la stessa i richiedenti non ricevono nulla', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);
    const { id } = (await openCycle(app, headers, { startDate: '2099-01-12' })).json();
    await givenPhone(await givenRequester({ id }), 'phone-of-requester');
    vi.mocked(fcm.sendEachForMulticast).mockClear();

    await updateCycle(app, headers, id, { startDate: '2099-01-12', durationDays: 30 });
    await updateCycle(app, headers, id, { scheduledClosedAt: inDays(10).toISOString() });

    expect(pushesReceivedBy('phone-of-requester')).toEqual([]);
  });

  it('se la push non parte la nuova data di inizio resta salvata', async () => {
    const app = await createTestApp();
    const headers = await superAdmin(app);
    const { id } = (await openCycle(app, headers, { startDate: '2099-01-12' })).json();
    await givenPhone(await givenRequester({ id }), 'phone-of-requester');
    vi.mocked(fcm.sendEachForMulticast).mockRejectedValueOnce(new Error('Firebase non raggiungibile'));

    const res = await updateCycle(app, headers, id, { startDate: '2099-01-19' });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ startsAt: startOfDayInRome('2099-01-19')!.toISOString() });
  });
});
