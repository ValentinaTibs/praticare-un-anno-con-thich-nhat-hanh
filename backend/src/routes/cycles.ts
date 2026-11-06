import { Prisma } from '@prisma/client';
import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';
import { closeExpiredCycles, findOpenCycle } from '../services/cycle.service.js';
import { startOfDayInRome } from '../utils/date.js';

const DEFAULT_DURATION_DAYS = 365;

const scheduledClosedAt = z.string().datetime();
const startDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const durationDays = z.number().int().positive().max(3650);

const openBody = z.object({
  scheduledClosedAt,
  startDate,
  durationDays: durationDays.default(DEFAULT_DURATION_DAYS),
});

const updateBody = z
  .object({
    scheduledClosedAt: scheduledClosedAt.optional(),
    startDate: startDate.optional(),
    durationDays: durationDays.optional(),
  })
  .refine((body) => Object.keys(body).length > 0);

const CLOSES_IN_PAST = 'La data di chiusura deve essere nel futuro';
const STARTS_IN_PAST = 'La data di inizio deve essere nel futuro';
const CLOSES_AFTER_START = 'La data di chiusura non può superare l\'inizio del percorso';
const ALREADY_OPEN = 'C\'è già un ciclo aperto';

// Concurrent requests can pass the check above: the partial unique index on open cycles stops them.
const isOpenCycleConflict = (error: unknown) =>
  error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002';

export async function cycleRoutes(app: FastifyInstance) {
  const preHandler = [authenticate, authorize('super_admin')];

  // GET /api/cycles/status — any authenticated user can check if requests are open
  app.get('/status', { preHandler: authenticate }, async (_request, reply) => {
    const cycle = await findOpenCycle();
    return reply.send({
      open: !!cycle,
      id: cycle?.id ?? null,
      openedAt: cycle?.openedAt ?? null,
      scheduledClosedAt: cycle?.scheduledClosedAt ?? null,
      startsAt: cycle?.startsAt ?? null,
      durationDays: cycle?.durationDays ?? null,
    });
  });

  // GET /api/cycles — super_admin only, every cycle, including closed ones still editable, with
  // its requesters (counted as on the waiting screen: suspended users don't count) and group members
  app.get('/', { preHandler }, async (_request, reply) => {
    await closeExpiredCycles();
    const cycles = await prisma.registrationCycle.findMany({
      orderBy: { startsAt: 'desc' },
      include: {
        group: { select: { _count: { select: { members: true } } } },
        _count: { select: { participationRequests: { where: { user: { status: 'active' } } } } },
      },
    });
    return reply.send(
      cycles.map(({ group, _count, ...cycle }) => ({
        ...cycle,
        requesters: _count.participationRequests,
        participants: group?._count.members ?? 0,
      })),
    );
  });

  // POST /api/cycles/open — super_admin only. The group is not created here.
  app.post('/open', { preHandler }, async (request, reply) => {
    const body = openBody.parse(request.body);
    const closesAt = new Date(body.scheduledClosedAt);
    const startsAt = startOfDayInRome(body.startDate);
    if (!startsAt) return reply.status(400).send({ message: 'Dati non validi' });

    const openedAt = new Date();
    if (closesAt <= openedAt) return reply.status(400).send({ message: CLOSES_IN_PAST });
    if (closesAt > startsAt) return reply.status(400).send({ message: CLOSES_AFTER_START });

    // A cycle past its date may still be marked open if the job has not run yet
    await closeExpiredCycles();
    const existing = await prisma.registrationCycle.findFirst({ where: { status: 'open' } });
    if (existing) return reply.status(409).send({ message: ALREADY_OPEN });

    try {
      const cycle = await prisma.registrationCycle.create({
        data: {
          status: 'open',
          openedBy: request.user.id,
          openedAt,
          scheduledClosedAt: closesAt,
          startsAt,
          durationDays: body.durationDays,
        },
      });

      return reply.status(201).send(cycle);
    } catch (error) {
      if (isOpenCycleConflict(error)) return reply.status(409).send({ message: ALREADY_OPEN });
      throw error;
    }
  });

  // PATCH /api/cycles/:id — super_admin only, until the journey starts.
  // A new closing date reopens a cycle that had already closed.
  app.patch<{ Params: { id: string } }>('/:id', { preHandler }, async (request, reply) => {
    const body = updateBody.parse(request.body);
    await closeExpiredCycles();
    const cycle = await prisma.registrationCycle.findUniqueOrThrow({ where: { id: request.params.id } });

    const now = new Date();
    if (cycle.startsAt <= now) {
      return reply.status(409).send({ message: 'Il percorso è già iniziato: il ciclo non si può più modificare' });
    }

    const startsAt = body.startDate ? startOfDayInRome(body.startDate) : cycle.startsAt;
    if (!startsAt) return reply.status(400).send({ message: 'Dati non validi' });
    if (startsAt <= now) return reply.status(400).send({ message: STARTS_IN_PAST });

    const closesAt = body.scheduledClosedAt ? new Date(body.scheduledClosedAt) : null;
    if (closesAt && closesAt <= now) return reply.status(400).send({ message: CLOSES_IN_PAST });

    // A cycle staying closed has already stopped taking requests, whatever its scheduled date says
    const effectiveClose = closesAt ?? (cycle.status === 'open' ? cycle.scheduledClosedAt : null);
    if (effectiveClose && effectiveClose > startsAt) {
      return reply.status(400).send({ message: CLOSES_AFTER_START });
    }

    // Resending the same date, as a form would, must not undo an early close
    const reopening =
      closesAt !== null && cycle.status === 'closed' && closesAt.getTime() !== cycle.scheduledClosedAt?.getTime();
    if (reopening) {
      const existing = await prisma.registrationCycle.findFirst({ where: { status: 'open' } });
      if (existing) return reply.status(409).send({ message: ALREADY_OPEN });
    }

    try {
      const updated = await prisma.registrationCycle.update({
        where: { id: cycle.id },
        data: {
          startsAt,
          durationDays: body.durationDays,
          ...(closesAt && { scheduledClosedAt: closesAt }),
          ...(reopening && { status: 'open' as const, closedAt: null }),
        },
      });

      return reply.send(updated);
    } catch (error) {
      if (isOpenCycleConflict(error)) return reply.status(409).send({ message: ALREADY_OPEN });
      throw error;
    }
  });

  // POST /api/cycles/close — super_admin only, closes the cycle before its date
  app.post('/close', { preHandler }, async (_request, reply) => {
    const cycle = await findOpenCycle();
    if (!cycle) return reply.status(404).send({ message: 'Nessun ciclo aperto' });

    const updated = await prisma.registrationCycle.update({
      where: { id: cycle.id },
      data: { status: 'closed', closedAt: new Date() },
    });

    return reply.send(updated);
  });
}
