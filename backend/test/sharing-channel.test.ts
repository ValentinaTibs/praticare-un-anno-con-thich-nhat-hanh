import { describe, it, expect } from 'vitest';
import { createTestApp, givenUser, givenAdmin, givenOpenSharingChannel, loginAs } from './helpers.js';

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

describe('Cerchio di condivisione', () => {
  it('senza cerchio aperto lo stato è chiuso', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenUser());

    const res = await app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'closed' });
  });

  it('con il cerchio aperto lo stato mostra l\'orario di chiusura e se l\'utente è entrato', async () => {
    const app = await createTestApp();
    const closesAt = new Date('2030-01-05T12:00:00.000Z');
    await givenOpenSharingChannel(closesAt);
    const headers = await loginAs(app, await givenUser());

    const before = await app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers });
    expect(before.json()).toMatchObject({
      status: 'open',
      scheduledClosedAt: '2030-01-05T12:00:00.000Z',
      joined: false,
    });

    await join(app, headers);

    const after = await app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers });
    expect(after.json()).toMatchObject({ joined: true });
  });

  it('chi è entrato scrive un messaggio e gli altri partecipanti lo vedono con nome e cognome', async () => {
    const app = await createTestApp();
    await givenOpenSharingChannel();
    const anna = await loginAs(app, await givenUser({ name: 'Anna', surname: 'Rossi' }));
    const marco = await loginAs(app, await givenUser({ name: 'Marco', surname: 'Bianchi' }));
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
    await givenOpenSharingChannel();
    const headers = await loginAs(app, await givenUser());
    await join(app, headers);

    const res = await join(app, headers);

    expect(res.statusCode).toBe(409);
  });

  it('chi non è entrato non può leggere né scrivere', async () => {
    const app = await createTestApp();
    await givenOpenSharingChannel();
    const headers = await loginAs(app, await givenUser());

    expect((await readPosts(app, headers)).statusCode).toBe(403);
    expect((await writePost(app, headers, 'Ciao')).statusCode).toBe(403);
  });

  it('chi esce non può più leggere i messaggi', async () => {
    const app = await createTestApp();
    await givenOpenSharingChannel();
    const headers = await loginAs(app, await givenUser());
    await join(app, headers);

    const res = await leave(app, headers);
    expect(res.statusCode).toBe(200);

    expect((await readPosts(app, headers)).statusCode).toBe(403);
  });

  it('un admin cancella un messaggio, un utente non può farlo', async () => {
    const app = await createTestApp();
    await givenOpenSharingChannel();
    const author = await loginAs(app, await givenUser());
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
    await givenOpenSharingChannel();
    const anna = await loginAs(app, await givenUser({ name: 'Anna' }));
    const admin = await loginAs(app, await givenAdmin());
    await join(app, anna);

    const denied = await app.inject({ method: 'GET', url: '/api/sharing-channel/members', headers: anna });
    expect(denied.statusCode).toBe(403);

    const members = await app.inject({ method: 'GET', url: '/api/sharing-channel/members', headers: admin });
    expect(members.json()).toMatchObject([{ user: { name: 'Anna' } }]);
  });
});
