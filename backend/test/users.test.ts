import { describe, it, expect } from 'vitest';
import { prisma } from '../src/config/prisma.js';
import { createTestApp, givenAdmin, givenGroup, givenMember, givenUser, loginAs } from './helpers.js';

type App = Awaited<ReturnType<typeof createTestApp>>;
type Headers = { authorization: string };

const listUsers = (app: App, headers: Headers, query: string) =>
  app.inject({ method: 'GET', url: `/api/users?${query}`, headers });
const ids = (res: { json: () => { users: { id: string }[] } }) => res.json().users.map((u) => u.id);

describe('Elenco utenti per gli admin', () => {
  it('il filtro «in attesa» comprende solo gli utenti attivi fuori da un gruppo attivo', async () => {
    const app = await createTestApp();
    const admin = await givenAdmin();
    const headers = await loginAs(app, admin);
    const waiting = await givenUser();
    await givenUser({ status: 'suspended' });
    await givenMember(await givenGroup());
    const ended = await givenGroup();
    await prisma.group.update({ where: { id: ended.id }, data: { endedAt: new Date(Date.now() - 1000) } });
    const backToWaiting = await givenMember(ended);

    const res = await listUsers(app, headers, 'waiting=true');

    expect(ids(res).sort()).toEqual([admin.id, waiting.id, backToWaiting.id].sort());
  });

  it('il filtro «da revisionare» comprende anche gli utenti senza gruppo', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const waiting = await givenUser({ reviewedByAdmin: false });
    const member = await givenMember(await givenGroup(), { reviewedByAdmin: false });
    const reviewed = await givenUser({ reviewedByAdmin: true });

    const res = await listUsers(app, headers, 'reviewed=false');

    expect(res.statusCode).toBe(200);
    expect(ids(res)).toEqual(expect.arrayContaining([waiting.id, member.id]));
    expect(ids(res)).not.toContain(reviewed.id);
  });

  it('il filtro «da revisionare» esclude i bannati, a meno di chiederli', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const active = await givenUser({ reviewedByAdmin: false });
    const suspended = await givenUser({ reviewedByAdmin: false, status: 'suspended' });
    const banned = await givenUser({ reviewedByAdmin: false, status: 'banned' });

    const queue = await listUsers(app, headers, 'reviewed=false');
    expect(ids(queue)).toEqual(expect.arrayContaining([active.id, suspended.id]));
    expect(ids(queue)).not.toContain(banned.id);

    const bannedOnly = await listUsers(app, headers, 'reviewed=false&status=banned');
    expect(ids(bannedOnly)).toEqual([banned.id]);
  });

  it('la ricerca trova per nome e cognome insieme, in qualsiasi ordine', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ name: 'Admin', surname: 'Prova' }));
    const chiara = await givenUser({ name: 'Chiara', surname: "D'Amico" });
    await givenUser({ name: 'Chiara', surname: 'Neri' });
    await givenUser({ name: 'Luca', surname: "D'Amico" });

    for (const q of ["Chiara D'Amico", "d'amico  chiara"]) {
      const res = await listUsers(app, headers, `q=${encodeURIComponent(q)}`);
      expect(ids(res)).toEqual([chiara.id]);
    }
  });

  it('le pagine non ripetono né saltano utenti con la stessa data di registrazione', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ createdAt: new Date('2020-01-01') }));
    const sameDate = new Date('2027-01-10T10:00:00.000Z');
    const users = [];
    for (let i = 0; i < 6; i++) users.push(await givenUser({ createdAt: sameDate }));
    const newest = await givenUser({ createdAt: new Date('2027-02-01') });

    const pages = [];
    for (const page of [1, 2, 3, 4]) pages.push(...ids(await listUsers(app, headers, `limit=2&page=${page}`)));

    expect(pages[0]).toBe(newest.id);
    const tied = pages.slice(1, 7);
    expect(tied).toEqual(users.map((u) => u.id).sort().reverse());
    expect(new Set(pages).size).toBe(pages.length);
  });

  it('la ricerca trova per nome, cognome o email senza distinguere le maiuscole', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin({ name: 'Admin', surname: 'Prova' }));
    const byName = await givenUser({ name: 'Anna', surname: 'Rossi' });
    const bySurname = await givenUser({ name: 'Luca', surname: 'Giovannini' });
    const byEmail = await givenUser({ name: 'Marco', surname: 'Verdi', email: 'ANNAmaria@test.local' });
    const other = await givenUser({ name: 'Paolo', surname: 'Neri' });

    const res = await listUsers(app, headers, 'q=ann');

    expect(res.json().total).toBe(3);
    expect(ids(res)).toEqual(expect.arrayContaining([byName.id, bySurname.id, byEmail.id]));
    expect(ids(res)).not.toContain(other.id);
  });

  it('filtra per stato e pagina i risultati', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());
    const banned = await givenUser({ status: 'banned' });
    await givenUser();
    await givenUser();

    const byStatus = await listUsers(app, headers, 'status=banned');
    expect(ids(byStatus)).toEqual([banned.id]);

    const page = await listUsers(app, headers, 'limit=2&page=2');
    expect(page.json()).toMatchObject({ total: 4, page: 2, limit: 2 });
    expect(page.json().users).toHaveLength(2);
  });

  it('parametri non validi rispondono 400', async () => {
    const app = await createTestApp();
    const headers = await loginAs(app, await givenAdmin());

    for (const query of ['limit=abc', 'limit=1000', 'page=0', 'status=xyz', 'reviewed=forse']) {
      const res = await listUsers(app, headers, query);
      expect(res.statusCode, query).toBe(400);
      expect(res.json().message).toBe('Dati non validi');
    }
  });
});
