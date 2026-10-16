import { FastifyInstance } from 'fastify';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';

export async function cycleRoutes(app: FastifyInstance) {
  const preHandler = [authenticate, authorize('super_admin')];

  // GET /api/cycles/status — any authenticated user can check if registration is open
  app.get('/status', { preHandler: authenticate }, async (_request, reply) => {
    const cycle = await prisma.registrationCycle.findFirst({ where: { status: 'open' } });
    return reply.send({ open: !!cycle, openedAt: cycle?.openedAt ?? null });
  });

  // POST /api/cycles/open — super_admin only
  app.post('/open', { preHandler }, async (request, reply) => {
    const existing = await prisma.registrationCycle.findFirst({ where: { status: 'open' } });
    if (existing) return reply.status(409).send({ message: 'A registration cycle is already open' });

    // Unblock phones that were only temporarily banned (removed users)
    await prisma.bannedPhone.deleteMany({ where: { permanent: false } });

    // Opening a cycle starts a new group: everyone who registers in it joins that group
    const openedAt = new Date();
    const cycle = await prisma.registrationCycle.create({
      data: {
        status: 'open',
        openedBy: request.user.id,
        openedAt,
        group: { create: { startedAt: openedAt } },
      },
      include: { group: true },
    });

    return reply.status(201).send(cycle);
  });

  // POST /api/cycles/close — super_admin only
  app.post('/close', { preHandler }, async (_request, reply) => {
    const cycle = await prisma.registrationCycle.findFirst({ where: { status: 'open' } });
    if (!cycle) return reply.status(404).send({ message: 'No open registration cycle' });

    const updated = await prisma.registrationCycle.update({
      where: { id: cycle.id },
      data: { status: 'closed', closedAt: new Date() },
    });

    return reply.send(updated);
  });
}
