import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { fcm } from '../src/config/firebase.js';
import { prisma } from '../src/config/prisma.js';
import { runMainChannelTick } from '../src/services/main-channel.service.js';
import { startOfDayInRome } from '../src/utils/date.js';
import { createTestApp, givenAdmin, givenMember, givenUser, loginAs } from './helpers.js';

type App = Awaited<ReturnType<typeof createTestApp>>;
type Headers = { authorization: string };

// Tokens last 15 minutes and journeys last days: every request logs in again at the current time.
const as = (app: App, user: { email: string }) => loginAs(app, user);

const createTemplate = async (app: App, admin: { email: string }, payload: object) =>
  app.inject({ method: 'POST', url: '/api/main-channel/templates', headers: await as(app, admin), payload });
const updateTemplate = async (app: App, admin: { email: string }, id: string, payload: object) =>
  app.inject({ method: 'PATCH', url: `/api/main-channel/templates/${id}`, headers: await as(app, admin), payload });
const deleteTemplate = async (app: App, admin: { email: string }, id: string) =>
  app.inject({ method: 'DELETE', url: `/api/main-channel/templates/${id}`, headers: await as(app, admin) });
const readTemplates = async (app: App, admin: { email: string }) =>
  app.inject({ method: 'GET', url: '/api/main-channel/templates', headers: await as(app, admin) });
const readGroupPosts = async (app: App, admin: { email: string }, groupId: string) =>
  app.inject({ method: 'GET', url: `/api/main-channel/groups/${groupId}/posts`, headers: await as(app, admin) });
const updatePost = async (app: App, admin: { email: string }, id: string, payload: object) =>
  app.inject({ method: 'PATCH', url: `/api/main-channel/posts/${id}`, headers: await as(app, admin), payload });
const deletePost = async (app: App, admin: { email: string }, id: string) =>
  app.inject({ method: 'DELETE', url: `/api/main-channel/posts/${id}`, headers: await as(app, admin) });
const readPosts = (app: App, headers: Headers) =>
  app.inject({ method: 'GET', url: '/api/main-channel/posts', headers });

// Moves the clock, as seen by the server, to this instant.
function at(instant: string) {
  vi.setSystemTime(new Date(instant));
}

// The job's run at the current time.
const tick = () => runMainChannelTick(new Date());

// A group whose journey starts at 00:00 in Italy on this date.
async function givenGroupStartingOn(date: string, durationDays = 365) {
  const startedAt = startOfDayInRome(date)!;
  const cycle = await prisma.registrationCycle.create({
    data: {
      status: 'closed',
      openedAt: startedAt,
      closedAt: startedAt,
      startsAt: startedAt,
      durationDays,
      group: { create: { startedAt } },
    },
    include: { group: true },
  });
  return cycle.group!;
}

async function givenDevice(user: { id: string }) {
  const { fcmToken } = await prisma.userDevice.create({ data: { userId: user.id, fcmToken: `token-${user.id}` } });
  return fcmToken;
}

// The push notifications Firebase was asked to deliver to this device.
function pushesReceivedBy(fcmToken: string) {
  return vi
    .mocked(fcm.sendEachForMulticast)
    .mock.calls.filter(([message]) => message.tokens.includes(fcmToken))
    .map(([message]) => message.notification);
}

const postsOf = async (groupId: string) =>
  prisma.mainChannelPost.findMany({ where: { groupId }, orderBy: { publishedAt: 'asc' } });

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.mocked(fcm.sendEachForMulticast).mockClear();
});

afterEach(() => {
  vi.useRealTimers();
});

describe('Sequenza dei modelli', () => {
  it('un modello nuovo è una bozza alle 08:00 se non si indica altro', async () => {
    at('2030-01-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();

    const created = await createTemplate(app, admin, { content: 'Benvenuti', journeyDay: 1 });

    expect(created.statusCode).toBe(201);
    expect(created.json()).toMatchObject({ journeyDay: 1, publishTime: '08:00', status: 'draft' });
  });

  it('la sequenza è ordinata per giorno e ora e mostra l\'autore agli admin', async () => {
    at('2030-01-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin({ name: 'Anna', surname: 'Rossi' });
    await createTemplate(app, admin, { content: 'Terzo', journeyDay: 2, publishTime: '09:00' });
    await createTemplate(app, admin, { content: 'Primo', journeyDay: 1, publishTime: '20:00' });
    await createTemplate(app, admin, { content: 'Secondo', journeyDay: 2, publishTime: '07:30', status: 'scheduled' });

    const templates = (await readTemplates(app, admin)).json();

    expect(templates.map((t: { content: string }) => t.content)).toEqual(['Primo', 'Secondo', 'Terzo']);
    expect(templates[0].author).toMatchObject({ name: 'Anna', surname: 'Rossi' });
  });

  it('giorno del percorso e ora devono essere validi', async () => {
    at('2030-01-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();

    expect((await createTemplate(app, admin, { content: 'x', journeyDay: 0 })).statusCode).toBe(400);
    expect((await createTemplate(app, admin, { content: 'x', journeyDay: 1, publishTime: '24:00' })).statusCode).toBe(400);
    expect((await createTemplate(app, admin, { content: '  ', journeyDay: 1 })).statusCode).toBe(400);
  });

  it('un utente che non è admin non vede né scrive la sequenza', async () => {
    at('2030-01-01T10:00:00.000Z');
    const app = await createTestApp();
    const user = await givenUser();

    expect((await readTemplates(app, user)).statusCode).toBe(403);
    expect((await createTemplate(app, user, { content: 'x', journeyDay: 1 })).statusCode).toBe(403);
  });
});

describe('Pubblicazione nei gruppi', () => {
  it('due gruppi con date di inizio diverse ricevono lo stesso modello nel rispettivo giorno', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    const early = await givenGroupStartingOn('2030-01-01');
    const late = await givenGroupStartingOn('2030-01-10');
    await createTemplate(app, admin, { content: 'Giorno 3', journeyDay: 3, status: 'scheduled' });

    // Day 3 of the first group, 07:59 and then 08:00 in Italy (UTC+1 in winter)
    at('2030-01-03T06:59:00.000Z');
    await tick();
    expect(await postsOf(early.id)).toHaveLength(0);

    at('2030-01-03T07:00:00.000Z');
    await tick();
    expect(await postsOf(early.id)).toMatchObject([{ content: 'Giorno 3', publishedAt: new Date('2030-01-03T07:00:00.000Z') }]);
    expect(await postsOf(late.id)).toHaveLength(0);

    // Day 3 of the second group
    at('2030-01-12T07:00:00.000Z');
    await tick();
    expect(await postsOf(late.id)).toMatchObject([{ content: 'Giorno 3', publishedAt: new Date('2030-01-12T07:00:00.000Z') }]);
    expect(await postsOf(early.id)).toHaveLength(1);
  });

  it('un modello aggiunto dopo il giorno N non arriva ai gruppi che l\'hanno già superato', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    const ahead = await givenGroupStartingOn('2030-01-01');
    const behind = await givenGroupStartingOn('2030-01-04');

    // Day 5 of the first group, day 2 of the second
    at('2030-01-05T10:00:00.000Z');
    await createTemplate(app, admin, { content: 'Giorno 3', journeyDay: 3, status: 'scheduled' });
    await tick();

    at('2030-01-06T07:00:00.000Z');
    await tick();

    expect(await postsOf(ahead.id)).toHaveLength(0);
    expect(await postsOf(behind.id)).toMatchObject([{ content: 'Giorno 3' }]);
  });

  it('un modello spostato più avanti arriva a chi non ha ancora raggiunto il nuovo giorno', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    const group = await givenGroupStartingOn('2030-01-01');
    const template = (await createTemplate(app, admin, { content: 'Spostato', journeyDay: 2, status: 'scheduled' })).json();

    // Day 3: moved from day 2 to day 4 before the group received it
    at('2030-01-03T05:00:00.000Z');
    await updateTemplate(app, admin, template.id, { journeyDay: 4 });

    at('2030-01-04T07:00:00.000Z');
    await tick();

    expect(await postsOf(group.id)).toMatchObject([{ content: 'Spostato' }]);
  });

  it('le bozze non vengono pubblicate', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    const group = await givenGroupStartingOn('2030-01-01');
    await createTemplate(app, admin, { content: 'Bozza', journeyDay: 1 });

    at('2030-01-01T07:00:00.000Z');
    await tick();

    expect(await postsOf(group.id)).toHaveLength(0);
  });

  it('un modello si pubblica una sola volta per gruppo', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    const group = await givenGroupStartingOn('2030-01-01');
    await createTemplate(app, admin, { content: 'Una volta', journeyDay: 1, status: 'scheduled' });

    at('2030-01-01T07:00:00.000Z');
    await Promise.all([tick(), tick()]);
    at('2030-01-01T07:01:00.000Z');
    await tick();

    expect(await postsOf(group.id)).toHaveLength(1);
  });

  it('i gruppi archiviati e quelli non ancora iniziati non ricevono nulla', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    const ended = await givenGroupStartingOn('2029-12-25', 5);
    const notStarted = await givenGroupStartingOn('2030-02-01');
    await createTemplate(app, admin, { content: 'Giorno 10', journeyDay: 10, status: 'scheduled' });

    // Day 10 of the archived group, which ended on 30 December
    at('2030-01-03T07:00:00.000Z');
    await prisma.group.update({ where: { id: ended.id }, data: { endedAt: startOfDayInRome('2029-12-30') } });
    await tick();

    expect(await postsOf(ended.id)).toHaveLength(0);
    expect(await postsOf(notStarted.id)).toHaveLength(0);
  });
});

describe('Notifica della pubblicazione', () => {
  it('i membri attivi del gruppo ricevono la push «Canale Principale» con l\'inizio del post', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    const group = await givenGroupStartingOn('2030-01-01');
    const other = await givenGroupStartingOn('2030-01-01');
    const member = await givenDevice(await givenMember(group));
    const suspended = await givenDevice(await givenMember(group, { status: 'suspended' }));
    const outsider = await givenDevice(await givenMember(other));
    const longText = `${'a'.repeat(150)} fine`;
    await createTemplate(app, admin, { content: longText, journeyDay: 1, status: 'scheduled' });

    at('2030-01-01T07:00:00.000Z');
    await tick();

    const [notification] = pushesReceivedBy(member);
    expect(notification?.title).toBe('Canale Principale');
    expect(notification?.body).toHaveLength(100);
    expect(notification?.body).toBe(`${'a'.repeat(99)}…`);
    expect(pushesReceivedBy(suspended)).toHaveLength(0);
    // The other group gets its own copy, with its own push
    expect(pushesReceivedBy(member)).toHaveLength(1);
    expect(pushesReceivedBy(outsider)).toHaveLength(1);
  });

  it('dopo una ripartenza nello stesso giorno il post arretrato si pubblica con la push', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    const group = await givenGroupStartingOn('2030-01-01');
    const member = await givenDevice(await givenMember(group));
    await createTemplate(app, admin, { content: 'Arretrato', journeyDay: 1, status: 'scheduled' });

    // Server back at 18:00 in Italy, the same day
    at('2030-01-01T17:00:00.000Z');
    await tick();

    expect(await postsOf(group.id)).toMatchObject([{ publishedAt: new Date('2030-01-01T07:00:00.000Z') }]);
    expect(pushesReceivedBy(member)).toHaveLength(1);
  });

  it('dopo una ripartenza in un altro giorno il post arretrato si pubblica senza push', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    const group = await givenGroupStartingOn('2030-01-01');
    const member = await givenDevice(await givenMember(group));
    await createTemplate(app, admin, { content: 'Giorno 1', journeyDay: 1, status: 'scheduled' });
    await createTemplate(app, admin, { content: 'Giorno 2', journeyDay: 2, status: 'scheduled' });

    // Server back on day 2 at 09:00 in Italy
    at('2030-01-02T08:00:00.000Z');
    await tick();

    expect((await postsOf(group.id)).map((p) => p.content)).toEqual(['Giorno 1', 'Giorno 2']);
    expect(pushesReceivedBy(member).map((n) => n?.body)).toEqual(['Giorno 2']);
  });
});

describe('Post del gruppo nell\'app', () => {
  it('il membro vede i post del proprio gruppo, dal più recente, senza autore', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    const group = await givenGroupStartingOn('2030-01-01');
    const other = await givenGroupStartingOn('2030-01-05');
    const member = await givenMember(group);
    await createTemplate(app, admin, { content: 'Primo', journeyDay: 1, status: 'scheduled' });
    await createTemplate(app, admin, { content: 'Secondo', journeyDay: 2, status: 'scheduled' });

    at('2030-01-05T07:00:00.000Z');
    await tick();

    const res = await readPosts(app, await as(app, member));
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ total: 2, page: 1, limit: 20 });
    expect(res.json().posts.map((p: { content: string }) => p.content)).toEqual(['Secondo', 'Primo']);
    expect(res.json().posts[0]).not.toHaveProperty('author');
    expect(res.json().posts[0]).not.toHaveProperty('authorId');
    expect(await postsOf(other.id)).toHaveLength(1);
  });

  it('un utente in attesa non vede alcun post', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    await givenGroupStartingOn('2030-01-01');
    const waiting = await givenUser();
    await createTemplate(app, admin, { content: 'Primo', journeyDay: 1, status: 'scheduled' });

    at('2030-01-01T07:00:00.000Z');
    await tick();

    expect((await readPosts(app, await as(app, waiting))).json()).toMatchObject({ posts: [], total: 0 });
  });

  it('a fine percorso l\'ex membro non vede più i post del gruppo', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin();
    const group = await givenGroupStartingOn('2030-01-01', 3);
    const member = await givenMember(group);
    await createTemplate(app, admin, { content: 'Primo', journeyDay: 1, status: 'scheduled' });
    at('2030-01-01T07:00:00.000Z');
    await tick();

    at('2030-01-05T07:00:00.000Z');
    await prisma.group.update({ where: { id: group.id }, data: { endedAt: startOfDayInRome('2030-01-04') } });

    expect((await readPosts(app, await as(app, member))).json()).toMatchObject({ posts: [], total: 0 });
  });
});

describe('Post pubblicati nel pannello', () => {
  async function givenPublishedPost() {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const admin = await givenAdmin({ name: 'Anna', surname: 'Rossi' });
    const group = await givenGroupStartingOn('2030-01-01');
    const other = await givenGroupStartingOn('2030-01-01');
    const template = (await createTemplate(app, admin, { content: 'Originale', journeyDay: 1, status: 'scheduled' })).json();
    at('2030-01-01T07:00:00.000Z');
    await tick();
    const [post] = await postsOf(group.id);
    return { app, admin, group, other, template, post: post! };
  }

  it('l\'admin vede i post di un gruppo con l\'autore', async () => {
    const { app, admin, group } = await givenPublishedPost();

    const res = await readGroupPosts(app, admin, group.id);

    expect(res.json()).toMatchObject({ total: 1, posts: [{ content: 'Originale', author: { name: 'Anna', surname: 'Rossi' } }] });
  });

  it('modificare un post lo cambia solo nel suo gruppo, senza notifiche', async () => {
    const { app, admin, group, other, post } = await givenPublishedPost();
    const member = await givenDevice(await givenMember(group));
    vi.mocked(fcm.sendEachForMulticast).mockClear();

    const res = await updatePost(app, admin, post.id, { content: 'Corretto' });

    expect(res.statusCode).toBe(200);
    expect(await postsOf(group.id)).toMatchObject([{ content: 'Corretto' }]);
    expect(await postsOf(other.id)).toMatchObject([{ content: 'Originale' }]);
    expect(pushesReceivedBy(member)).toHaveLength(0);
  });

  it('cancellare un post lo toglie solo dal suo gruppo e non lo ripubblica', async () => {
    const { app, admin, group, other, post } = await givenPublishedPost();

    expect((await deletePost(app, admin, post.id)).statusCode).toBe(204);
    at('2030-01-01T08:00:00.000Z');
    await tick();

    expect(await postsOf(group.id)).toHaveLength(0);
    expect(await postsOf(other.id)).toHaveLength(1);
  });

  it('anche i post di un gruppo archiviato si modificano e si cancellano', async () => {
    const { app, admin, group, post } = await givenPublishedPost();
    await prisma.group.update({ where: { id: group.id }, data: { endedAt: new Date('2030-01-01T07:30:00.000Z') } });

    expect((await readGroupPosts(app, admin, group.id)).json().total).toBe(1);
    expect((await updatePost(app, admin, post.id, { content: 'Archivio' })).statusCode).toBe(200);
    expect((await deletePost(app, admin, post.id)).statusCode).toBe(204);
  });

  it('modificare o cancellare il modello non tocca le copie già pubblicate', async () => {
    const { app, admin, group, template } = await givenPublishedPost();

    await updateTemplate(app, admin, template.id, { content: 'Nuovo testo' });
    expect(await postsOf(group.id)).toMatchObject([{ content: 'Originale' }]);

    expect((await deleteTemplate(app, admin, template.id)).statusCode).toBe(204);
    expect(await postsOf(group.id)).toMatchObject([{ content: 'Originale', templateId: null }]);
  });

  it('un utente che non è admin non modifica né cancella i post', async () => {
    const { app, group, post } = await givenPublishedPost();
    const member = await givenMember(group);

    expect((await updatePost(app, member, post.id, { content: 'x' })).statusCode).toBe(403);
    expect((await deletePost(app, member, post.id)).statusCode).toBe(403);
  });
});

describe('Rimozione di un admin', () => {
  it('modelli e copie restano senza autore, le bozze restano bozze e la sequenza continua', async () => {
    at('2029-12-01T10:00:00.000Z');
    const app = await createTestApp();
    const superAdmin = await givenUser({ role: 'super_admin', reviewedByAdmin: true });
    const admin = await givenAdmin();
    const group = await givenGroupStartingOn('2030-01-01');
    await createTemplate(app, admin, { content: 'Giorno 1', journeyDay: 1, status: 'scheduled' });
    await createTemplate(app, admin, { content: 'Giorno 2', journeyDay: 2, status: 'scheduled' });
    await createTemplate(app, admin, { content: 'Bozza', journeyDay: 3 });
    at('2030-01-01T07:00:00.000Z');
    await tick();

    const removed = await app.inject({ method: 'DELETE', url: `/api/admin/${admin.id}`, headers: await as(app, superAdmin) });
    expect(removed.statusCode).toBe(204);

    const templates = (await readTemplates(app, superAdmin)).json();
    expect(templates).toMatchObject([
      { content: 'Giorno 1', status: 'scheduled', author: null },
      { content: 'Giorno 2', status: 'scheduled', author: null },
      { content: 'Bozza', status: 'draft', author: null },
    ]);

    at('2030-01-02T07:00:00.000Z');
    await tick();
    expect(await postsOf(group.id)).toMatchObject([
      { content: 'Giorno 1', authorId: null },
      { content: 'Giorno 2', authorId: null },
    ]);
  });
});
