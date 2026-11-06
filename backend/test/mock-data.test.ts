import { describe, it, expect } from 'vitest';
import { prisma } from '../src/config/prisma.js';
import { isLocalDatabase, seedMockData } from '../scripts/mock-data.js';
import { mockUsers } from '../scripts/mock-users.js';
import { givenOpenCycle, givenUser } from './helpers.js';

const email = (predicate: (u: (typeof mockUsers)[number]) => boolean) => mockUsers.find(predicate)!.email;

describe('Dati di prova', () => {
  it('su un database vuoto crea utenti, gruppi, ciclo aperto e richieste', async () => {
    const result = await seedMockData(prisma);

    expect(result.users).toBe(mockUsers.length);
    expect(result.requests).toBe(mockUsers.filter((u) => u.requested).length);
    expect(result.requests).toBeGreaterThan(0);
    expect(await prisma.user.count({ where: { role: 'super_admin' } })).toBe(1);
    expect(await prisma.group.count({ where: { endedAt: null } })).toBe(1);
    expect(await prisma.group.count({ where: { endedAt: { lt: new Date() } } })).toBe(1);
    expect(await prisma.registrationCycle.findMany({ where: { status: 'open' } })).toMatchObject([
      { scheduledClosedAt: expect.any(Date), durationDays: 365 },
    ]);
    const banned = mockUsers.filter((u) => u.status === 'banned').map((u) => u.email).sort();
    expect((await prisma.bannedEmail.findMany({ orderBy: { email: 'asc' } })).map((b) => b.email)).toEqual(banned);
  });

  it('il ciclo aperto accetta richieste: chiude prima dell\'inizio, nel futuro', async () => {
    const { cycle } = await seedMockData(prisma);

    expect(cycle.scheduledClosedAt!.getTime()).toBeGreaterThan(Date.now());
    expect(cycle.startsAt.getTime()).toBeGreaterThan(cycle.scheduledClosedAt!.getTime());
  });

  it('una seconda esecuzione non aggiunge niente', async () => {
    await seedMockData(prisma);
    const before = await Promise.all([prisma.user.count(), prisma.group.count(), prisma.registrationCycle.count()]);

    const again = await seedMockData(prisma);

    expect(again).toMatchObject({ users: 0, bannedEmails: 0, requests: 0 });
    expect(await Promise.all([prisma.user.count(), prisma.group.count(), prisma.registrationCycle.count()])).toEqual(before);
  });

  it('non sovrascrive un utente esistente', async () => {
    const target = email((u) => u.group === 'active' && !u.status);
    await givenUser({ email: target, name: 'Cambiata', status: 'suspended' });

    await seedMockData(prisma);

    expect(await prisma.user.findUniqueOrThrow({ where: { email: target } })).toMatchObject({
      name: 'Cambiata',
      status: 'suspended',
      groupId: null,
    });
  });

  it('sostituisce un ciclo aperto ormai scaduto', async () => {
    const expired = await givenOpenCycle(new Date(Date.now() - 1000));

    const { cycle } = await seedMockData(prisma);

    expect(cycle.id).not.toBe(expired.id);
    expect(await prisma.registrationCycle.findUniqueOrThrow({ where: { id: expired.id } })).toMatchObject({ status: 'closed' });
  });

  it('riusa il ciclo già aperto', async () => {
    const open = await givenOpenCycle();

    const { cycle } = await seedMockData(prisma);

    expect(cycle.id).toBe(open.id);
    expect(await prisma.participationRequest.count({ where: { cycleId: open.id } })).toBeGreaterThan(0);
  });

  it('non dà la richiesta a chi nel frattempo è sospeso', async () => {
    const target = email((u) => !!u.requested);
    await givenUser({ email: target, status: 'suspended' });

    const { requests } = await seedMockData(prisma);

    expect(requests).toBe(mockUsers.filter((u) => u.requested).length - 1);
  });

  it('non tocca il Super Admin esistente', async () => {
    const existing = await givenUser({ role: 'super_admin', email: 'capo@prova.local' });

    await seedMockData(prisma);

    expect((await prisma.user.findMany({ where: { role: 'super_admin' } })).map((u) => u.id)).toEqual([existing.id]);
  });

  it.each([
    ['postgresql://postgres:x@localhost:5432/community_app', true],
    ['postgresql://postgres:x@127.0.0.1:5432/community_app', true],
    ['postgresql://postgres:x@postgres.railway.internal:5432/railway', false],
    ['postgresql://postgres:x@roundhouse.proxy.rlwy.net:12345/railway', false],
    ['postgresql://localhost.evil.example/db', false],
    [undefined, false],
    ['non-un-url', false],
  ])('riconosce un database locale: %s → %s', (url, expected) => {
    expect(isLocalDatabase(url)).toBe(expected);
  });
});
