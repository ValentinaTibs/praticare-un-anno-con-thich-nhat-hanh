import { describe, it, expect } from 'vitest';
import { prisma } from '../src/config/prisma.js';
import { issueConfirmationRequests, processMissedConfirmations } from '../src/services/confirmation.service.js';
import { endDueGroups } from '../src/services/cycle.service.js';
import { createTestApp, givenGroup, givenMember, givenUser, loginAs } from './helpers.js';

type App = Awaited<ReturnType<typeof createTestApp>>;

const DAY = 24 * 60 * 60 * 1000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY);
// Last confirmed long enough ago to be due for a new round.
const overdue = { lastConfirmedAt: daysAgo(40) };

async function givenEndedGroup() {
  const group = await givenGroup();
  return prisma.group.update({ where: { id: group.id }, data: { endedAt: daysAgo(1) } });
}

const pending = async (app: App, user: { email: string }) =>
  (await app.inject({ method: 'GET', url: '/api/confirmations/pending', headers: await loginAs(app, user) })).json();

const status = async (user: { id: string }) =>
  (await prisma.user.findUniqueOrThrow({ where: { id: user.id } })).status;

describe('Utenti in attesa e round di conferma', () => {
  it('il membro di un gruppo attivo riceve la richiesta di conferma', async () => {
    const app = await createTestApp();
    const member = await givenMember(await givenGroup(), overdue);

    await issueConfirmationRequests();

    expect(await pending(app, member)).not.toBeNull();
  });

  it('l\'utente in attesa senza gruppo non riceve la richiesta di conferma', async () => {
    const app = await createTestApp();
    const waiting = await givenUser(overdue);

    await issueConfirmationRequests();

    expect(await pending(app, waiting)).toBeNull();
  });

  it('l\'ex membro di un gruppo finito non riceve la richiesta di conferma', async () => {
    const app = await createTestApp();
    const exMember = await givenMember(await givenEndedGroup(), overdue);

    await issueConfirmationRequests();

    expect(await pending(app, exMember)).toBeNull();
  });

  it('a fine percorso la conferma rimasta in sospeso decade', async () => {
    const app = await createTestApp();
    const startsAt = daysAgo(31);
    const cycle = await prisma.registrationCycle.create({
      data: { status: 'closed', openedAt: daysAgo(40), closedAt: startsAt, startsAt, durationDays: 30, group: { create: { startedAt: startsAt } } },
      include: { group: true },
    });
    const member = await givenMember(cycle.group!);
    await prisma.confirmationRequest.create({ data: { userId: member.id, dueAt: new Date(Date.now() + DAY) } });

    await endDueGroups();

    expect(await pending(app, member)).toBeNull();
  });

  it('l\'utente in attesa con una conferma scaduta non viene sospeso', async () => {
    const exMember = await givenMember(await givenEndedGroup());
    await prisma.confirmationRequest.create({ data: { userId: exMember.id, dueAt: daysAgo(1) } });

    await processMissedConfirmations();

    expect(await status(exMember)).toBe('active');
    expect(await prisma.confirmationRequest.count({ where: { userId: exMember.id } })).toBe(0);
  });

  it('il membro di un gruppo attivo con una conferma scaduta viene sospeso', async () => {
    const member = await givenMember(await givenGroup());
    await prisma.confirmationRequest.create({ data: { userId: member.id, dueAt: daysAgo(1) } });

    await processMissedConfirmations();

    expect(await status(member)).toBe('suspended');
  });
});
