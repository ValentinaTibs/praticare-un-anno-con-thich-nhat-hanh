import { describe, it, expect, vi } from 'vitest';
import { fcm } from '../src/config/firebase.js';
import { prisma } from '../src/config/prisma.js';
import { createTestApp, givenMember, givenAdmin, givenGroup, givenOpenSharingChannel, loginAs } from './helpers.js';

type App = Awaited<ReturnType<typeof createTestApp>>;
type Headers = { authorization: string };

const join = (app: App, headers: Headers) =>
  app.inject({ method: 'POST', url: '/api/sharing-channel/join', headers });
const leave = (app: App, headers: Headers) =>
  app.inject({ method: 'DELETE', url: '/api/sharing-channel/leave', headers });
const readPosts = (app: App, headers: Headers) =>
  app.inject({ method: 'GET', url: '/api/sharing-channel/posts', headers });
const writePost = (app: App, headers: Headers, content: string) =>
  app.inject({ method: 'POST', url: '/api/sharing-channel/posts', headers, payload: { content } });
const readStatus = (app: App, headers: Headers) =>
  app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers });
const contents = (res: { json: () => { content: string }[] }) => res.json().map((post) => post.content);

describe('Cerchio di condivisione', () => {
  it('senza cerchio aperto lo stato è chiuso', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenMember(await givenGroup()));

    const res = await app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'closed' });
  });

  it('con il cerchio aperto lo stato mostra l\'orario di chiusura e se l\'utente è entrato', async () => {
    const app = await createTestApp();
    const closesAt = new Date('2030-01-05T12:00:00.000Z');
    const group = await givenGroup();
    await givenOpenSharingChannel(group, closesAt);
    const headers = await loginAs(app, await givenMember(group));

    const before = await app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers });
    expect(before.json()).toMatchObject({
      status: 'open',
      scheduledClosedAt: '2030-01-05T12:00:00.000Z',
      joined: false,
      memberCount: 0,
    });

    await join(app, headers);

    const after = await app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers });
    expect(after.json()).toMatchObject({ joined: true, memberCount: 1 });
  });

  it('chi è entrato scrive un messaggio e gli altri partecipanti lo vedono con nome e cognome', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const anna = await loginAs(app, await givenMember(group, { name: 'Anna', surname: 'Rossi' }));
    const marco = await loginAs(app, await givenMember(group, { name: 'Marco', surname: 'Bianchi' }));
    await join(app, anna);
    await join(app, marco);

    const sent = await writePost(app, anna, 'Oggi mi sento grata');
    expect(sent.statusCode).toBe(201);

    const posts = await readPosts(app, marco);
    expect(posts.statusCode).toBe(200);
    expect(posts.json()).toMatchObject([
      { content: 'Oggi mi sento grata', author: { name: 'Anna', surname: 'Rossi' } },
    ]);
  });

  it('non si può entrare due volte', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const headers = await loginAs(app, await givenMember(group));
    await join(app, headers);

    const res = await join(app, headers);

    expect(res.statusCode).toBe(409);
  });

  it('chi non è entrato non può leggere né scrivere', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const headers = await loginAs(app, await givenMember(group));

    expect((await readPosts(app, headers)).statusCode).toBe(403);
    expect((await writePost(app, headers, 'Ciao')).statusCode).toBe(403);
  });

  it('chi esce non può più leggere i messaggi', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const headers = await loginAs(app, await givenMember(group));
    await join(app, headers);

    const res = await leave(app, headers);
    expect(res.statusCode).toBe(200);

    expect((await readPosts(app, headers)).statusCode).toBe(403);
  });

  it('un admin cancella un messaggio, un utente non può farlo', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const author = await loginAs(app, await givenMember(group));
    const admin = await loginAs(app, await givenAdmin());
    await join(app, author);
    const post = (await writePost(app, author, 'Da rimuovere')).json();

    const denied = await app.inject({ method: 'DELETE', url: `/api/sharing-channel/posts/${post.id}`, headers: author });
    expect(denied.statusCode).toBe(403);

    const removed = await app.inject({ method: 'DELETE', url: `/api/sharing-channel/posts/${post.id}`, headers: admin });
    expect(removed.statusCode).toBe(204);

    expect((await readPosts(app, author)).json()).toEqual([]);
  });

  it('solo gli admin vedono l\'elenco dei membri', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const anna = await loginAs(app, await givenMember(group, { name: 'Anna' }));
    const admin = await loginAs(app, await givenAdmin());
    await join(app, anna);

    const denied = await app.inject({ method: 'GET', url: '/api/sharing-channel/members', headers: anna });
    expect(denied.statusCode).toBe(403);

    const members = await app.inject({ method: 'GET', url: `/api/sharing-channel/members?groupId=${group.id}`, headers: admin });
    expect(members.json()).toMatchObject([{ user: { name: 'Anna' } }]);
  });

  it('i messaggi sono solo testo: un link a media viene rifiutato', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const headers = await loginAs(app, await givenMember(group));
    await join(app, headers);

    const res = await app.inject({
      method: 'POST',
      url: '/api/sharing-channel/posts',
      headers,
      payload: { content: 'Ascoltate', mediaUrl: 'https://example.org/audio.mp3' },
    });

    expect(res.statusCode).toBe(400);
  });

  it('chi entra per la prima volta vede i messaggi già scritti', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const anna = await loginAs(app, await givenMember(group));
    const marco = await loginAs(app, await givenMember(group));
    await join(app, anna);
    await writePost(app, anna, 'Benvenuti');

    const joined = await join(app, marco);

    expect(joined.json().history).toMatchObject([{ content: 'Benvenuti' }]);
    expect(contents(await readPosts(app, marco))).toEqual(['Benvenuti']);
  });

  it('chi rientra vede solo i messaggi scritti dopo il rientro', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const anna = await loginAs(app, await givenMember(group));
    const marco = await loginAs(app, await givenMember(group));
    await join(app, anna);
    await join(app, marco);
    await writePost(app, anna, 'Prima');
    await leave(app, marco);
    await writePost(app, anna, 'Mentre era fuori');

    const rejoined = await join(app, marco);
    expect(rejoined.statusCode).toBe(200);
    expect(rejoined.json().history).toEqual([]);
    await writePost(app, anna, 'Dopo il rientro');

    expect(contents(await readPosts(app, marco))).toEqual(['Dopo il rientro']);
    expect(contents(await readPosts(app, anna))).toEqual(['Prima', 'Mentre era fuori', 'Dopo il rientro']);
  });

  it('chi è uscito non riceve più le notifiche del cerchio', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const anna = await loginAs(app, await givenMember(group));
    const marcoUser = await givenMember(group);
    const marco = await loginAs(app, marcoUser);
    await prisma.userDevice.create({ data: { userId: marcoUser.id, fcmToken: 'phone-of-marco' } });
    await join(app, anna);
    await join(app, marco);
    await leave(app, marco);
    vi.mocked(fcm.sendEachForMulticast).mockClear();

    await writePost(app, anna, 'Ciao a tutti');

    const reached = vi.mocked(fcm.sendEachForMulticast).mock.calls.filter(([m]) => m.tokens.includes('phone-of-marco'));
    expect(reached).toHaveLength(0);
  });

  it('gli utenti vedono quante persone sono nel cerchio e quante ci sono entrate, senza i nomi', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    await givenOpenSharingChannel(group);
    const anna = await loginAs(app, await givenMember(group, { name: 'Anna' }));
    const marco = await loginAs(app, await givenMember(group, { name: 'Marco' }));
    const lucia = await loginAs(app, await givenMember(group));
    expect((await readStatus(app, lucia)).json()).toMatchObject({ participantCount: 0 });

    await join(app, anna);
    await join(app, marco);
    await leave(app, marco);
    await join(app, marco);

    await join(app, lucia);
    await leave(app, lucia);

    const status = await readStatus(app, lucia);
    expect(status.json()).toMatchObject({ memberCount: 2, participantCount: 3 });
    expect(status.body).not.toContain('Anna');
    expect(status.body).not.toContain('Marco');
  });

  it('nel pannello i membri del cerchio sono quelli che ci sono adesso', async () => {
    const app = await createTestApp();
    const group = await givenGroup();
    const channel = await givenOpenSharingChannel(group);
    const anna = await loginAs(app, await givenMember(group, { name: 'Anna' }));
    const marco = await loginAs(app, await givenMember(group, { name: 'Marco' }));
    const admin = await loginAs(app, await givenAdmin());
    await join(app, anna);
    await join(app, marco);
    await leave(app, marco);

    const detail = await app.inject({ method: 'GET', url: `/api/sharing-channel/channels/${channel.id}`, headers: admin });
    expect(detail.json().members).toMatchObject([{ user: { name: 'Anna' } }]);
    const list = await app.inject({ method: 'GET', url: '/api/sharing-channel/channels', headers: admin });
    expect(list.json()).toMatchObject([{ memberCount: 1 }]);
  });
});
