import { describe, it, expect } from 'vitest';
import { prisma } from '../src/config/prisma.js';
import { endDueGroups } from '../src/services/cycle.service.js';
import { runSharingChannelTick } from '../src/services/sharing-channel.service.js';
import { journeyEndsAt } from '../src/utils/date.js';
import {
  createTestApp,
  givenAdmin,
  givenMember,
  givenOpenCycle,
  givenOpenSharingChannel,
  loginAs,
} from './helpers.js';

type App = Awaited<ReturnType<typeof createTestApp>>;

const DAY = 24 * 60 * 60 * 1000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY);

// A group whose journey started some days ago and lasts the given days, job not run yet.
async function givenGroupStarted(days: number, durationDays: number) {
  const startsAt = daysAgo(days);
  const cycle = await prisma.registrationCycle.create({
    data: {
      status: 'closed',
      openedAt: daysAgo(days + 14),
      closedAt: startsAt,
      scheduledClosedAt: startsAt,
      startsAt,
      durationDays,
      group: { create: { startedAt: startsAt } },
    },
    include: { group: true },
  });
  return { ...cycle.group!, endsAt: journeyEndsAt(startsAt, durationDays) };
}

const me = async (app: App, user: { email: string }) =>
  (await app.inject({ method: 'GET', url: '/api/users/me', headers: await loginAs(app, user) })).json();

describe('Fine del gruppo', () => {
  it('trascorsa la durata il gruppo finisce alla data prevista e il membro torna in attesa', async () => {
    const app = await createTestApp();
    const group = await givenGroupStarted(31, 30);
    const member = await givenMember(group);

    await endDueGroups();

    expect((await me(app, member)).group.endedAt).toBe(group.endsAt.toISOString());
    const next = await app.inject({ method: 'GET', url: '/api/cycles/next', headers: await loginAs(app, member) });
    expect(next.statusCode).toBe(200);
  });

  it('un gruppo con la durata non ancora trascorsa resta attivo', async () => {
    const app = await createTestApp();
    const group = await givenGroupStarted(29, 30);
    const member = await givenMember(group);

    await endDueGroups();

    expect((await me(app, member)).group.endedAt).toBeNull();
  });

  it('dopo uno spegnimento del server la fine resta quella prevista, non quella della ripartenza', async () => {
    const app = await createTestApp();
    const group = await givenGroupStarted(100, 30);
    const member = await givenMember(group);

    await endDueGroups();

    expect((await me(app, member)).group.endedAt).toBe(group.endsAt.toISOString());
  });

  it('eseguire di nuovo il controllo non cambia la data di fine', async () => {
    const app = await createTestApp();
    const group = await givenGroupStarted(31, 30);
    const member = await givenMember(group);

    await endDueGroups();
    await endDueGroups();

    expect((await me(app, member)).group.endedAt).toBe(group.endsAt.toISOString());
  });

  it('l\'ex membro può chiedere di partecipare a un nuovo percorso', async () => {
    const app = await createTestApp();
    const group = await givenGroupStarted(31, 30);
    const member = await givenMember(group, { reviewedByAdmin: true });
    await givenOpenCycle();
    const headers = await loginAs(app, member);

    const before = await app.inject({ method: 'POST', url: '/api/cycles/requests', headers });
    expect(before.statusCode).toBe(409);

    await endDueGroups();

    const after = await app.inject({ method: 'POST', url: '/api/cycles/requests', headers });
    expect(after.statusCode).toBe(201);
  });

  it('gli admin vedono il gruppo archiviato con i suoi ex membri', async () => {
    const app = await createTestApp();
    const group = await givenGroupStarted(31, 30);
    const member = await givenMember(group);
    const headers = await loginAs(app, await givenAdmin());

    await endDueGroups();

    const groups = (await app.inject({ method: 'GET', url: '/api/groups', headers })).json();
    expect(groups).toMatchObject([{ id: group.id, endedAt: group.endsAt.toISOString(), memberCount: 1 }]);
    const members = await app.inject({ method: 'GET', url: `/api/users?groupId=${group.id}`, headers });
    expect(members.json().users.map((u: { id: string }) => u.id)).toEqual([member.id]);
  });
});

describe('Cerchio di un gruppo finito', () => {
  it('il cerchio aperto alla fine del percorso si chiude e i suoi messaggi vengono cancellati', async () => {
    const app = await createTestApp();
    const group = await givenGroupStarted(31, 30);
    const member = await givenMember(group);
    const headers = await loginAs(app, member);
    const channel = await givenOpenSharingChannel(group);
    await app.inject({ method: 'POST', url: '/api/sharing-channel/join', headers });
    await app.inject({ method: 'POST', url: '/api/sharing-channel/posts', headers, payload: { content: 'Ciao' } });

    await endDueGroups();
    await runSharingChannelTick(new Date());

    expect((await prisma.sharingChannel.findUniqueOrThrow({ where: { id: channel.id } })).status).toBe('closed');
    expect(await prisma.sharingChannelPost.count({ where: { sharingChannelId: channel.id } })).toBe(0);
  });

  it('prima che il cerchio si chiuda l\'ex membro non può più entrarci', async () => {
    const app = await createTestApp();
    const group = await givenGroupStarted(31, 30);
    const member = await givenMember(group);
    await givenOpenSharingChannel(group);

    await endDueGroups();

    const headers = await loginAs(app, member);
    expect((await app.inject({ method: 'GET', url: '/api/sharing-channel/status', headers })).json()).toEqual({
      status: 'closed',
    });
    const join = await app.inject({ method: 'POST', url: '/api/sharing-channel/join', headers });
    expect(join.statusCode).toBe(404);
  });
});
