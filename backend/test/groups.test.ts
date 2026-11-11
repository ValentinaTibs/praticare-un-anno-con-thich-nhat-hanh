import { describe, it, expect } from 'vitest';
import {
  createTestApp,
  givenAdmin,
  givenGroup,
  givenMember,
  givenOpenSharingChannel,
  loginAs,
} from './helpers.js';

describe('Gruppi', () => {
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

  it('un admin entra nel cerchio di un gruppo scelto', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const admin = await loginAs(app, await givenAdmin());

    const join = await app.inject({ method: 'POST', url: `/api/sharing-channel/join?groupId=${group.id}`, headers: admin });

    expect(join.statusCode).toBe(200);
  });
});
