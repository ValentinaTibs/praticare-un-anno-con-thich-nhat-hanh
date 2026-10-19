import { describe, it, expect } from 'vitest';
import {
  createTestApp,
  givenAdmin,
  givenGroup,
  givenMember,
  givenOpenSharingChannel,
  firebaseTokenFor,
  loginAs,
} from './helpers.js';

type App = Awaited<ReturnType<typeof createTestApp>>;
type Headers = { authorization: string };

const nextWeek = () => new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
const openCycle = (app: App, headers: Headers) =>
  app.inject({ method: 'POST', url: '/api/cycles/open', headers, payload: { scheduledClosedAt: nextWeek() } });
const closeCycle = (app: App, headers: Headers) =>
  app.inject({ method: 'POST', url: '/api/cycles/close', headers });

async function register(app: App, email: string, name: string) {
  const res = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { idToken: firebaseTokenFor(email), name, surname: 'Rossi', motivation: 'Voglio praticare' },
  });
  if (res.statusCode !== 201) throw new Error(`register failed: ${res.statusCode} ${res.body}`);
  return { authorization: `Bearer ${res.json().accessToken}` };
}

const me = async (app: App, headers: Headers) =>
  (await app.inject({ method: 'GET', url: '/api/users/me', headers })).json();

describe('Gruppi', () => {
  it('aprire un ciclo crea un gruppo che inizia all\'apertura', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ role: 'super_admin' }));

    const res = await openCycle(app, headers);

    expect(res.statusCode).toBe(201);
    expect(res.json().group).toMatchObject({ startedAt: res.json().openedAt, endedAt: null });
  });

  it('chi si registra entra nel gruppo del ciclo aperto', async () => {
    const app = await createTestApp();
    const superAdmin = await loginAs(app, await givenAdmin({ role: 'super_admin' }));
    const cycle = (await openCycle(app, superAdmin)).json();

    const anna = await register(app, 'anna@test.local', 'Anna');

    expect((await me(app, anna)).group).toMatchObject({ id: cycle.group.id });
  });

  it('chi si registra in cicli diversi finisce in gruppi diversi', async () => {
    const app = await createTestApp();
    const superAdmin = await loginAs(app, await givenAdmin({ role: 'super_admin' }));

    await openCycle(app, superAdmin);
    const anna = await register(app, 'anna@test.local', 'Anna');
    await closeCycle(app, superAdmin);

    await openCycle(app, superAdmin);
    const marco = await register(app, 'marco@test.local', 'Marco');

    expect((await me(app, anna)).group.id).not.toBe((await me(app, marco)).group.id);
  });

  it('gli admin vedono tutti i gruppi con il numero di membri', async () => {
    const app = await createTestApp();
    const first = await givenGroup();
    const second = await givenGroup();
    await givenMember(first);
    await givenMember(first);
    await givenMember(second);
    const admin = await loginAs(app, await givenAdmin());

    const res = await app.inject({ method: 'GET', url: '/api/groups', headers: admin });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toHaveLength(2);
    expect(res.json()).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ id: first.id, memberCount: 2 }),
        expect.objectContaining({ id: second.id, memberCount: 1 }),
      ]),
    );
  });

  it('un utente non vede l\'elenco dei gruppi', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenMember(await givenGroup()));

    const res = await app.inject({ method: 'GET', url: '/api/groups', headers });

    expect(res.statusCode).toBe(403);
  });

  it('gli admin filtrano gli utenti per gruppo', async () => {
    const app = await createTestApp();
    const first = await givenGroup();
    const second = await givenGroup();
    await givenMember(first, { name: 'Anna' });
    await givenMember(second, { name: 'Marco' });
    const admin = await loginAs(app, await givenAdmin());

    const res = await app.inject({ method: 'GET', url: `/api/users?groupId=${first.id}`, headers: admin });

    expect(res.json().users).toMatchObject([{ name: 'Anna', groupId: first.id }]);
  });
});

describe('Cerchio per gruppo', () => {
  it('un utente vede solo il cerchio del suo gruppo', async () => {
    const app = await createTestApp();
    const open = await givenGroup();
    const other = await givenGroup();
    await givenOpenSharingChannel(open);
    const inside = await loginAs(app, await givenMember(open));
    const outside = await loginAs(app, await givenMember(other));

    const insideStatus = await app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers: inside });
    const outsideStatus = await app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers: outside });

    expect(insideStatus.json()).toMatchObject({ status: 'open' });
    expect(outsideStatus.json()).toMatchObject({ status: 'closed' });
    const join = await app.inject({ method: 'POST', url: '/api/sharing-channel/join', headers: outside });
    expect(join.statusCode).toBe(404);
  });

  it('un utente non può scegliere il cerchio di un altro gruppo', async () => {
    const app = await createTestApp();
    const open = await givenGroup();
    await givenOpenSharingChannel(open);
    const outside = await loginAs(app, await givenMember(await givenGroup()));

    const res = await app.inject({
      method: 'GET',
      url: `/api/sharing-channel/status?groupId=${open.id}`,
      headers: outside,
    });

    expect(res.json()).toMatchObject({ status: 'closed' });
  });

  it('i messaggi di un cerchio non arrivano al cerchio di un altro gruppo', async () => {
    const app = await createTestApp();
    const first = await givenGroup();
    const second = await givenGroup();
    await givenOpenSharingChannel(first);
    await givenOpenSharingChannel(second);
    const anna = await loginAs(app, await givenMember(first));
    const marco = await loginAs(app, await givenMember(second));
    await app.inject({ method: 'POST', url: '/api/sharing-channel/join', headers: anna });
    await app.inject({ method: 'POST', url: '/api/sharing-channel/join', headers: marco });

    await app.inject({ method: 'POST', url: '/api/sharing-channel/posts', headers: anna, payload: { content: 'Ciao gruppo uno' } });

    const posts = await app.inject({ method: 'GET', url: '/api/sharing-channel/posts', headers: marco });
    expect(posts.json()).toEqual([]);
  });

  it('un admin apre il cerchio di un gruppo scelto e può entrarci', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    const admin = await loginAs(app, await givenAdmin());
    const member = await loginAs(app, await givenMember(group));

    const opened = await app.inject({
      method: 'POST',
      url: `/api/sharing-channel/open?groupId=${group.id}`,
      headers: admin,
      payload: { scheduledClosedAt: new Date(Date.now() + 60 * 60 * 1000).toISOString() },
    });
    expect(opened.statusCode).toBe(201);
    expect(opened.json()).toMatchObject({ groupId: group.id });

    const status = await app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers: member });
    expect(status.json()).toMatchObject({ status: 'open' });

    const join = await app.inject({ method: 'POST', url: `/api/sharing-channel/join?groupId=${group.id}`, headers: admin });
    expect(join.statusCode).toBe(200);
  });

  it('un admin senza gruppo deve indicare il gruppo per aprire un cerchio', async () => {
    const app = await createTestApp();
    const admin = await loginAs(app, await givenAdmin());

    const res = await app.inject({
      method: 'POST',
      url: '/api/sharing-channel/open',
      headers: admin,
      payload: { scheduledClosedAt: new Date(Date.now() + 60 * 60 * 1000).toISOString() },
    });

    expect(res.statusCode).toBe(400);
  });

  it('gruppi diversi possono avere il cerchio aperto insieme', async () => {
    const app = await createTestApp();
    const first = await givenGroup();
    const second = await givenGroup();
    await givenOpenSharingChannel(first);
    const admin = await loginAs(app, await givenAdmin());

    const res = await app.inject({
      method: 'POST',
      url: `/api/sharing-channel/open?groupId=${second.id}`,
      headers: admin,
      payload: { scheduledClosedAt: new Date(Date.now() + 60 * 60 * 1000).toISOString() },
    });

    expect(res.statusCode).toBe(201);
  });
});
