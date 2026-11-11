import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { fcm } from '../src/config/firebase.js';
import { createTestApp, givenAdmin, givenMember, givenGroup, givenUser, loginAs } from './helpers.js';
import { runSharingChannelTick } from '../src/services/sharing-channel.service.js';

type App = Awaited<ReturnType<typeof createTestApp>>;
type Headers = { authorization: string };

const saturdayAtNine = { dayOfWeek: 6, startTime: '09:00', durationMinutes: 60 };

const saveSchedule = (app: App, headers: Headers, payload: object) =>
  app.inject({ method: 'PUT', url: '/api/sharing-channel/schedule', headers, payload });
const readSchedule = (app: App, headers: Headers) =>
  app.inject({ method: 'GET', url: '/api/sharing-channel/schedule', headers });
const readStatus = (app: App, headers: Headers) =>
  app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers });
const join = (app: App, headers: Headers) =>
  app.inject({ method: 'POST', url: '/api/sharing-channel/join', headers });
const registerDevice =(app: App, headers: Headers, fcmToken: string) =>
  app.inject({ method: 'POST', url: '/api/auth/devices', headers, payload: { fcmToken } });

// The texts of the push notifications Firebase was asked to deliver to this device.
function pushesReceivedBy(fcmToken: string) {
  return vi
    .mocked(fcm.sendEachForMulticast)
    .mock.calls.filter(([message]) => message.tokens.includes(fcmToken))
    .map(([message]) => message.notification?.body);
}

beforeEach(() => {
  vi.mocked(fcm.sendEachForMulticast).mockClear();
});

describe('Programmazione del cerchio', () => {
  it('un admin salva l\'appuntamento settimanale e lo rilegge', async () => {
    const app = await createTestApp();
    const admin = await loginAs(app, await givenAdmin());

    const saved = await saveSchedule(app, admin, saturdayAtNine);
    expect(saved.statusCode).toBe(200);

    const read = await readSchedule(app, admin);
    expect(read.json()).toMatchObject(saturdayAtNine);
  });
});

describe('Apertura e chiusura automatiche', () => {
  it('all\'orario programmato il cerchio del gruppo si apre fino alla fine della durata', async () => {
    const app = await createTestApp();
    await saveSchedule(app, await loginAs(app, await givenAdmin()), saturdayAtNine);
    const member = await loginAs(app, await givenMember(await givenGroup()));

    // Saturday 5 January 2030, 09:00 in Italy (UTC+1 in winter)
    await runSharingChannelTick(new Date('2030-01-05T08:00:00.000Z'));

    const status = await readStatus(app, member);
    expect(status.json()).toMatchObject({ status: 'open', scheduledClosedAt: '2030-01-05T09:00:00.000Z' });
  });

  it('alla fine della durata il cerchio si chiude', async () => {
    const app = await createTestApp();
    await saveSchedule(app, await loginAs(app, await givenAdmin()), saturdayAtNine);
    const member = await loginAs(app, await givenMember(await givenGroup()));
    await runSharingChannelTick(new Date('2030-01-05T08:00:00.000Z'));

    await runSharingChannelTick(new Date('2030-01-05T09:00:00.000Z'));

    expect((await readStatus(app, member)).json()).toMatchObject({ status: 'closed' });
  });

  it('all\'apertura i membri del gruppo ricevono la push «Il cerchio è aperto»', async () => {
    const app = await createTestApp();
    await saveSchedule(app, await loginAs(app, await givenAdmin()), saturdayAtNine);
    const group = await givenGroup();
    await registerDevice(app, await loginAs(app, await givenMember(group)), 'phone-of-member');
    await registerDevice(app, await loginAs(app, await givenUser()), 'phone-of-waiting-user');

    await runSharingChannelTick(new Date('2030-01-05T08:00:00.000Z'));

    expect(pushesReceivedBy('phone-of-member')).toContain('Il cerchio è aperto');
    expect(pushesReceivedBy('phone-of-waiting-user')).not.toContain('Il cerchio è aperto');
  });

  it('con l\'ora legale il cerchio si apre comunque alle 9:00 italiane', async () => {
    const app = await createTestApp();
    await saveSchedule(app, await loginAs(app, await givenAdmin()), saturdayAtNine);
    const member = await loginAs(app, await givenMember(await givenGroup()));

    // Saturday 6 July 2030: 09:00 in Italy is 07:00 UTC
    await runSharingChannelTick(new Date('2030-07-06T07:00:00.000Z'));

    expect((await readStatus(app, member)).json()).toMatchObject({
      status: 'open',
      scheduledClosedAt: '2030-07-06T08:00:00.000Z',
    });
  });
});

describe('Avviso di chiusura imminente', () => {
  it('15 minuti prima della chiusura arriva solo a chi è nel cerchio, una volta sola', async () => {
    const app = await createTestApp();
    await saveSchedule(app, await loginAs(app, await givenAdmin()), saturdayAtNine);
    const group = await givenGroup();
    const inside = await loginAs(app, await givenMember(group));
    const outside = await loginAs(app, await givenMember(group));
    await registerDevice(app, inside, 'phone-inside');
    await registerDevice(app, outside, 'phone-outside');
    await runSharingChannelTick(new Date('2030-01-05T08:00:00.000Z'));
    await join(app, inside);

    await runSharingChannelTick(new Date('2030-01-05T08:45:00.000Z'));
    await runSharingChannelTick(new Date('2030-01-05T08:45:30.000Z'));

    const warning = 'Il cerchio si chiude tra 15 minuti';
    expect(pushesReceivedBy('phone-inside').filter((body) => body === warning)).toHaveLength(1);
    expect(pushesReceivedBy('phone-outside')).not.toContain(warning);
  });
});

describe('Niente cerchi fuori programma', () => {
  it('un admin non può aprire un cerchio a mano né chiuderlo in anticipo', async () => {
    const app = await createTestApp();
    const admin = await loginAs(app, await givenAdmin());
    const group = await givenGroup();
    const closesAt = new Date('2030-01-05T09:00:00.000Z').toISOString();

    const open = await app.inject({
      method: 'POST',
      url: `/api/sharing-channel/open?groupId=${group.id}`,
      headers: admin,
      payload: { scheduledClosedAt: closesAt },
    });
    const close = await app.inject({ method: 'POST', url: `/api/sharing-channel/close?groupId=${group.id}`, headers: admin });

    expect(open.statusCode).toBe(404);
    expect(close.statusCode).toBe(404);
  });
});

describe('Moderazione dei cerchi aperti', () => {
  it('gli admin vedono i cerchi aperti di tutti i gruppi, gli utenti no', async () => {
    const app = await createTestApp();
    const admin = await loginAs(app, await givenAdmin());
    await saveSchedule(app, admin, saturdayAtNine);
    const first = await givenGroup();
    const second = await givenGroup();
    const member = await loginAs(app, await givenMember(first));
    await runSharingChannelTick(new Date('2030-01-05T08:00:00.000Z'));

    const denied = await app.inject({ method: 'GET', url: '/api/sharing-channel/channels', headers: member });
    expect(denied.statusCode).toBe(403);

    const channels = await app.inject({ method: 'GET', url: '/api/sharing-channel/channels', headers: admin });
    expect(channels.json().map((channel: { group: { id: string } }) => channel.group.id).sort()).toEqual(
      [first.id, second.id].sort(),
    );
  });

  it('un admin legge membri e messaggi di un cerchio senza entrarci', async () => {
    const app = await createTestApp();
    const admin = await loginAs(app, await givenAdmin());
    await saveSchedule(app, admin, saturdayAtNine);
    const group = await givenGroup();
    const anna = await loginAs(app, await givenMember(group, { name: 'Anna', surname: 'Rossi' }));
    await runSharingChannelTick(new Date('2030-01-05T08:00:00.000Z'));
    await join(app, anna);
    await app.inject({ method: 'POST', url: '/api/sharing-channel/posts', headers: anna, payload: { content: 'Buongiorno' } });
    const [channel] = (await app.inject({ method: 'GET', url: '/api/sharing-channel/channels', headers: admin })).json();

    const res = await app.inject({ method: 'GET', url: `/api/sharing-channel/channels/${channel.id}`, headers: admin });

    expect(res.json()).toMatchObject({
      members: [{ user: { name: 'Anna', surname: 'Rossi' } }],
      posts: [{ content: 'Buongiorno', author: { name: 'Anna', surname: 'Rossi' } }],
    });
  });
});

describe('Cambio di programmazione', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  // Saves the schedule as if the admin pressed the button at this instant.
  async function saveScheduleAt(app: App, instant: string, schedule: object) {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(instant));
    await saveSchedule(app, await loginAs(app, await givenAdmin()), schedule);
    vi.useRealTimers();
  }

  it('un orario che comprende già il momento della modifica vale dalla settimana dopo', async () => {
    const app = await createTestApp();
    const member = await loginAs(app, await givenMember(await givenGroup()));
    // Saturday 5 January 2030, 09:10 in Italy
    await saveScheduleAt(app, '2030-01-05T08:10:00.000Z', saturdayAtNine);

    await runSharingChannelTick(new Date('2030-01-05T08:11:00.000Z'));
    expect((await readStatus(app, member)).json()).toMatchObject({ status: 'closed' });

    await runSharingChannelTick(new Date('2030-01-12T08:00:00.000Z'));
    expect((await readStatus(app, member)).json()).toMatchObject({ status: 'open' });
  });

  it('se la programmazione cambia a cerchio aperto, il cerchio finisce all\'orario previsto', async () => {
    const app = await createTestApp();
    const member = await loginAs(app, await givenMember(await givenGroup()));
    await saveScheduleAt(app, '2030-01-01T08:00:00.000Z', saturdayAtNine);
    await runSharingChannelTick(new Date('2030-01-05T08:00:00.000Z'));

    // At 09:15 the appointment becomes half an hour long
    await saveScheduleAt(app, '2030-01-05T08:15:00.000Z', { ...saturdayAtNine, durationMinutes: 30 });

    await runSharingChannelTick(new Date('2030-01-05T08:45:00.000Z'));
    expect((await readStatus(app, member)).json()).toMatchObject({
      status: 'open',
      scheduledClosedAt: '2030-01-05T09:00:00.000Z',
    });
  });
});
