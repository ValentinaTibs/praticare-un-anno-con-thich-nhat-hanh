import { Prisma, UserStatus } from '@prisma/client';
import { FastifyInstance } from 'fastify';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';
import { findOpenCycle } from '../services/cycle.service.js';
import { adminUserSelect } from './users.js';

const IN_GROUP = 'Partecipi già a un percorso';
const ALREADY_REQUESTED = 'Hai già una richiesta in corso';

const notStarted = () => ({ startsAt: { gt: new Date() } });

async function isInActiveGroup(groupId: string | null) {
  if (!groupId) return false;
  const group = await prisma.group.findFirst({
    where: { id: groupId, OR: [{ endedAt: null }, { endedAt: { gt: new Date() } }] },
    select: { id: true },
  });
  return group !== null;
}

// The request of this user for a journey not started yet: past ones have lapsed.
function findPendingRequest(userId: string) {
  return prisma.participationRequest.findFirst({
    where: { userId, cycle: notStarted() },
    include: { cycle: true },
  });
}

export async function participationRequestRoutes(app: FastifyInstance) {
  // GET /api/cycles/next — what the waiting screen shows: the user's own journey if they
  // asked for one, else the one taking requests, else the next to start.
  app.get('/next', { preHandler: authenticate }, async (request, reply) => {
    const { id: userId, groupId } = request.user;
    if (await isInActiveGroup(groupId)) return reply.status(403).send({ message: IN_GROUP });

    const [pending, open] = await Promise.all([findPendingRequest(userId), findOpenCycle()]);
    const cycle =
      pending?.cycle ??
      open ??
      (await prisma.registrationCycle.findFirst({ where: notStarted(), orderBy: { startsAt: 'asc' } }));
    if (!cycle) return reply.send({ cycle: null, requesters: 0, requested: false, canRequest: false });

    const { email } = await prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { email: true } });
    const [requesters, removed] = await Promise.all([
      prisma.participationRequest.count({ where: { cycleId: cycle.id, user: { status: UserStatus.active } } }),
      prisma.removedRequester.findUnique({ where: { cycleId_email: { cycleId: cycle.id, email } } }),
    ]);
    const isOpen = open?.id === cycle.id;

    return reply.send({
      cycle: {
        id: cycle.id,
        open: isOpen,
        startsAt: cycle.startsAt,
        durationDays: cycle.durationDays,
        scheduledClosedAt: cycle.scheduledClosedAt,
      },
      requesters,
      requested: pending !== null,
      canRequest: isOpen && !pending && !removed,
    });
  });

  // POST /api/cycles/requests — asks to join the journey of the open cycle
  app.post('/requests', { preHandler: authenticate }, async (request, reply) => {
    const { id: userId, groupId } = request.user;
    if (await isInActiveGroup(groupId)) return reply.status(409).send({ message: IN_GROUP });

    const cycle = await findOpenCycle();
    if (!cycle) return reply.status(409).send({ message: 'Le richieste di partecipazione sono chiuse' });

    if (await findPendingRequest(userId)) return reply.status(409).send({ message: ALREADY_REQUESTED });

    const { email } = await prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { email: true } });
    const removed = await prisma.removedRequester.findUnique({ where: { cycleId_email: { cycleId: cycle.id, email } } });
    if (removed) {
      return reply.status(403).send({ message: 'Non puoi chiedere di partecipare a questo percorso. Potrai farlo dal prossimo.' });
    }

    try {
      const created = await prisma.participationRequest.create({ data: { cycleId: cycle.id, userId } });
      return reply.status(201).send(created);
    } catch (error) {
      // A double tap: the unique index lets only the first through.
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        return reply.status(409).send({ message: ALREADY_REQUESTED });
      }
      throw error;
    }
  });

  // DELETE /api/cycles/requests/mine — until the journey starts, even if the cycle has closed
  app.delete('/requests/mine', { preHandler: authenticate }, async (request, reply) => {
    const { count } = await prisma.participationRequest.deleteMany({
      where: { userId: request.user.id, cycle: notStarted() },
    });
    if (count === 0) return reply.status(404).send({ message: 'Nessuna richiesta in corso' });
    return reply.status(204).send();
  });

  // GET /api/cycles/requests — admins: requesters of every journey not started yet,
  // soonest first; within each, who still needs a review comes first.
  app.get('/requests', { preHandler: [authenticate, authorize('admin')] }, async (_request, reply) => {
    const cycles = await prisma.registrationCycle.findMany({
      where: notStarted(),
      orderBy: { startsAt: 'asc' },
      select: {
        id: true,
        status: true,
        startsAt: true,
        scheduledClosedAt: true,
        participationRequests: {
          orderBy: [{ user: { reviewedByAdmin: 'asc' } }, { createdAt: 'asc' }, { id: 'asc' }],
          select: {
            createdAt: true,
            user: { select: adminUserSelect },
          },
        },
      },
    });

    return reply.send(
      cycles.map(({ participationRequests, ...cycle }) => ({
        ...cycle,
        requests: participationRequests.map(({ createdAt, user }) => ({ ...user, requestedAt: createdAt })),
      })),
    );
  });
}
