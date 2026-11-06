import { describe, it, expect } from 'vitest';
import { prisma } from '../src/config/prisma.js';
import {
  createTestApp,
  firebaseTokenFor,
  givenAdmin,
  givenGroup,
  givenMember,
  givenOpenCycle,
  givenUser,
  loginAs,
} from './helpers.js';

type App = Awaited<ReturnType<typeof createTestApp>>;
type Headers = { authorization: string };

const inDays = (days: number) => new Date(Date.now() + days * 24 * 60 * 60 * 1000);

const ask = (app: App, headers: Headers) => app.inject({ method: 'POST', url: '/api/cycles/requests', headers });
const cancel = (app: App, headers: Headers) =>
  app.inject({ method: 'DELETE', url: '/api/cycles/requests/mine', headers });
const next = (app: App, headers: Headers) => app.inject({ method: 'GET', url: '/api/cycles/next', headers });
const list = (app: App, headers: Headers) => app.inject({ method: 'GET', url: '/api/cycles/requests', headers });

// Requests closed, journey still to start.
const givenClosedCycle = (startsAt = inDays(14)) =>
  prisma.registrationCycle.create({
    data: { status: 'closed', openedAt: new Date(), closedAt: new Date(), scheduledClosedAt: inDays(1), startsAt },
  });

const givenRequest = (cycle: { id: string }, user: { id: string }) =>
  prisma.participationRequest.create({ data: { cycleId: cycle.id, userId: user.id } });

describe('Richiesta di partecipazione', () => {
  it('a ciclo aperto un utente in attesa chiede di partecipare', async () => {
    const app = await createTestApp();
    const cycle = await givenOpenCycle();
    const user = await givenUser();
    const headers = await loginAs(app, user);

    const res = await ask(app, headers);

    expect(res.statusCode).toBe(201);
    expect(await prisma.participationRequest.findMany()).toMatchObject([{ cycleId: cycle.id, userId: user.id }]);
    expect((await next(app, headers)).json()).toMatchObject({ requested: true, canRequest: false, requesters: 1 });
  });

  it('anche un admin in attesa può chiedere di partecipare', async () => {
    const app = await createTestApp();
    await givenOpenCycle();

    expect((await ask(app, await loginAs(app, await givenAdmin()))).statusCode).toBe(201);
  });

  it('senza un ciclo aperto la richiesta è rifiutata', async () => {
    const app = await createTestApp();
    await givenClosedCycle();

    const res = await ask(app, await loginAs(app, await givenUser()));

    expect(res.statusCode).toBe(409);
    expect(res.json().message).toBe('Le richieste di partecipazione sono chiuse');
  });

  it('un ciclo oltre la data di chiusura non accetta richieste anche se il job non è ancora passato', async () => {
    const app = await createTestApp();
    await givenOpenCycle(new Date(Date.now() - 1000));

    expect((await ask(app, await loginAs(app, await givenUser()))).statusCode).toBe(409);
  });

  it('chi è in un gruppo attivo non può chiedere di partecipare', async () => {
    const app = await createTestApp();
    await givenOpenCycle();
    const headers = await loginAs(app, await givenMember(await givenGroup()));

    const res = await ask(app, headers);

    expect(res.statusCode).toBe(409);
    expect(res.json().message).toBe('Partecipi già a un percorso');
    expect((await next(app, headers)).statusCode).toBe(403);
  });

  it('chi è in un gruppo già finito può chiedere di partecipare', async () => {
    const app = await createTestApp();
    await givenOpenCycle();
    const group = await givenGroup();
    await prisma.group.update({ where: { id: group.id }, data: { endedAt: new Date(Date.now() - 1000) } });

    expect((await ask(app, await loginAs(app, await givenMember(group)))).statusCode).toBe(201);
  });

  it('non si può chiedere due volte', async () => {
    const app = await createTestApp();
    await givenOpenCycle();
    const headers = await loginAs(app, await givenUser());
    await ask(app, headers);

    const res = await ask(app, headers);

    expect(res.statusCode).toBe(409);
    expect(res.json().message).toBe('Hai già una richiesta in corso');
    expect(await prisma.participationRequest.count()).toBe(1);
  });

  it('due richieste simultanee ne creano una sola', async () => {
    const app = await createTestApp();
    await givenOpenCycle();
    const headers = await loginAs(app, await givenUser());

    const codes = (await Promise.all([ask(app, headers), ask(app, headers)])).map((r) => r.statusCode).sort();

    expect(codes).toEqual([201, 409]);
    expect(await prisma.participationRequest.count()).toBe(1);
  });

  it('chi aspetta un percorso già chiuso non può chiederne un altro finché non annulla', async () => {
    const app = await createTestApp();
    const user = await givenUser();
    const headers = await loginAs(app, user);
    const first = await givenClosedCycle();
    await givenRequest(first, user);
    const second = await givenOpenCycle(inDays(20), inDays(30));

    expect((await ask(app, headers)).statusCode).toBe(409);
    expect((await next(app, headers)).json()).toMatchObject({ cycle: { id: first.id, open: false }, requested: true });

    expect((await cancel(app, headers)).statusCode).toBe(204);
    expect((await ask(app, headers)).statusCode).toBe(201);
    expect(await prisma.participationRequest.findMany()).toMatchObject([{ cycleId: second.id }]);
  });

  it('una richiesta di un percorso già iniziato non conta più', async () => {
    const app = await createTestApp();
    const user = await givenUser();
    const headers = await loginAs(app, user);
    await givenRequest(await givenClosedCycle(new Date(Date.now() - 1000)), user);
    await givenOpenCycle();

    expect((await ask(app, headers)).statusCode).toBe(201);
  });
});

describe('Annullamento della richiesta', () => {
  it('si annulla e si rifà finché il ciclo è aperto', async () => {
    const app = await createTestApp();
    await givenOpenCycle();
    const headers = await loginAs(app, await givenUser());
    await ask(app, headers);

    expect((await cancel(app, headers)).statusCode).toBe(204);
    expect(await prisma.participationRequest.count()).toBe(0);
    expect((await next(app, headers)).json()).toMatchObject({ requested: false, canRequest: true });
    expect((await ask(app, headers)).statusCode).toBe(201);
  });

  it('a ciclo chiuso si annulla fino all\'inizio, ma non si rifà', async () => {
    const app = await createTestApp();
    const user = await givenUser();
    const headers = await loginAs(app, user);
    await givenRequest(await givenClosedCycle(), user);

    expect((await cancel(app, headers)).statusCode).toBe(204);
    expect((await ask(app, headers)).statusCode).toBe(409);
  });

  it('dopo l\'inizio non si annulla', async () => {
    const app = await createTestApp();
    const user = await givenUser();
    await givenRequest(await givenClosedCycle(new Date(Date.now() - 1000)), user);

    const res = await cancel(app, await loginAs(app, user));

    expect(res.statusCode).toBe(404);
    expect(await prisma.participationRequest.count()).toBe(1);
  });

  it('annulla solo la propria richiesta', async () => {
    const app = await createTestApp();
    const cycle = await givenOpenCycle();
    await givenRequest(cycle, await givenUser());

    expect((await cancel(app, await loginAs(app, await givenUser()))).statusCode).toBe(404);
    expect(await prisma.participationRequest.count()).toBe(1);
  });
});

describe('Numero dei richiedenti', () => {
  it('senza percorsi in programma non c\'è niente da chiedere', async () => {
    const app = await createTestApp();

    const res = await next(app, await loginAs(app, await givenUser()));

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ cycle: null, requesters: 0, requested: false, canRequest: false });
  });

  it('conta i richiedenti del ciclo aperto, tranne i sospesi', async () => {
    const app = await createTestApp();
    const cycle = await givenOpenCycle();
    await givenRequest(cycle, await givenUser());
    await givenRequest(cycle, await givenUser());
    await givenRequest(cycle, await givenUser({ status: 'suspended' }));

    const res = await next(app, await loginAs(app, await givenUser()));

    expect(res.json()).toMatchObject({ cycle: { id: cycle.id, open: true }, requesters: 2, requested: false, canRequest: true });
  });

  it('a ciclo chiuso mostra il prossimo percorso e non permette di chiedere', async () => {
    const app = await createTestApp();
    const cycle = await givenClosedCycle();
    await givenRequest(cycle, await givenUser());

    const res = await next(app, await loginAs(app, await givenUser()));

    expect(res.json()).toMatchObject({ cycle: { id: cycle.id, open: false }, requesters: 1, canRequest: false });
  });

  it('non mostra un percorso già iniziato', async () => {
    const app = await createTestApp();
    await givenClosedCycle(new Date(Date.now() - 1000));

    expect((await next(app, await loginAs(app, await givenUser()))).json().cycle).toBeNull();
  });
});

describe('Elenco dei richiedenti', () => {
  it('gli admin vedono motivazione e prima chi è da revisionare', async () => {
    const app = await createTestApp();
    const cycle = await givenOpenCycle();
    const reviewed = await givenUser({ reviewedByAdmin: true, motivation: 'Già nota' });
    const toReview = await givenUser({ motivation: 'Voglio praticare' });
    await givenRequest(cycle, reviewed);
    await givenRequest(cycle, toReview);

    const res = await list(app, await loginAs(app, await givenAdmin()));

    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject([
      {
        id: cycle.id,
        requests: [
          { id: toReview.id, motivation: 'Voglio praticare', reviewedByAdmin: false },
          { id: reviewed.id, motivation: 'Già nota', reviewedByAdmin: true },
        ],
      },
    ]);
  });

  it('elenca i percorsi non iniziati, dal più vicino, anche a richieste chiuse', async () => {
    const app = await createTestApp();
    const later = await givenOpenCycle(inDays(20), inDays(30));
    const sooner = await givenClosedCycle(inDays(10));
    await givenClosedCycle(new Date(Date.now() - 1000));

    const res = await list(app, await loginAs(app, await givenAdmin()));

    expect(res.json().map((c: { id: string }) => c.id)).toEqual([sooner.id, later.id]);
  });

  it('un utente normale non vede l\'elenco', async () => {
    const app = await createTestApp();

    expect((await list(app, await loginAs(app, await givenUser()))).statusCode).toBe(403);
  });
});

describe('Uscita di un richiedente', () => {
  const remove = (app: App, headers: Headers, id: string) =>
    app.inject({ method: 'DELETE', url: `/api/admin/${id}`, headers });
  const registerAgain = (app: App, email: string) =>
    app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { idToken: firebaseTokenFor(email), name: 'Anna', surname: 'Bianchi', motivation: 'Ci riprovo' },
    });

  it('chi è rimosso con una richiesta si registra di nuovo, ma non può chiedere nello stesso ciclo', async () => {
    const app = await createTestApp();
    const cycle = await givenOpenCycle();
    const user = await givenUser();
    await givenRequest(cycle, user);
    const admin = await loginAs(app, await givenAdmin());

    expect((await remove(app, admin, user.id)).statusCode).toBe(204);
    expect(await prisma.participationRequest.count()).toBe(0);
    expect((await next(app, await loginAs(app, await givenUser()))).json().requesters).toBe(0);

    expect((await registerAgain(app, user.email)).statusCode).toBe(201);
    const headers = await loginAs(app, user);
    expect((await next(app, headers)).json()).toMatchObject({ requested: false, canRequest: false });
    const res = await ask(app, headers);
    expect(res.statusCode).toBe(403);
    expect(res.json().message).toBe('Non puoi chiedere di partecipare a questo percorso. Potrai farlo dal prossimo.');
  });

  it('dal ciclo successivo può chiedere di nuovo', async () => {
    const app = await createTestApp();
    const cycle = await givenClosedCycle();
    const user = await givenUser();
    await givenRequest(cycle, user);
    await remove(app, await loginAs(app, await givenAdmin()), user.id);
    await registerAgain(app, user.email);
    await givenOpenCycle(inDays(20), inDays(30));

    expect((await ask(app, await loginAs(app, user))).statusCode).toBe(201);
  });

  it('chi è rimosso senza richiesta può chiedere nello stesso ciclo', async () => {
    const app = await createTestApp();
    await givenOpenCycle();
    const user = await givenUser();
    await remove(app, await loginAs(app, await givenAdmin()), user.id);
    await registerAgain(app, user.email);

    expect((await ask(app, await loginAs(app, user))).statusCode).toBe(201);
  });

  it('chi aveva annullato prima della rimozione può chiedere di nuovo', async () => {
    const app = await createTestApp();
    await givenOpenCycle();
    const user = await givenUser();
    const headers = await loginAs(app, user);
    await ask(app, headers);
    await cancel(app, headers);
    await remove(app, await loginAs(app, await givenAdmin()), user.id);
    await registerAgain(app, user.email);

    expect((await ask(app, await loginAs(app, user))).statusCode).toBe(201);
  });

  it('il ban cancella la richiesta', async () => {
    const app = await createTestApp();
    const cycle = await givenOpenCycle();
    const user = await givenUser();
    await givenRequest(cycle, user);

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/admin/${user.id}/ban`,
      headers: await loginAs(app, await givenAdmin()),
    });

    expect(res.statusCode).toBe(200);
    expect(await prisma.participationRequest.count()).toBe(0);
  });
});
