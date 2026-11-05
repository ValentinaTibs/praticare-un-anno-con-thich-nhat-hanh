import { describe, it, expect } from 'vitest';
import { createTestApp, givenAdmin, givenGroup, givenMember, givenUser, loginAs } from './helpers.js';

type App = Awaited<ReturnType<typeof createTestApp>>;
type Headers = { authorization: string };

const listUsers = (app: App, headers: Headers, query: string) =>
  app.inject({ method: 'GET', url: `/api/users?${query}`, headers });
const ids = (res: { json: () => { users: { id: string }[] } }) => res.json().users.map((u) => u.id);

describe('Elenco utenti per gli admin', () => {
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
