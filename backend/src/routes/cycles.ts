import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';
import { closeExpiredCycles, findOpenCycle } from '../services/cycle.service.js';

const openBody = z.object({
  scheduledClosedAt: z.string().datetime(),
});

export async function cycleRoutes(app: FastifyInstance) {
  const preHandler = [authenticate, authorize('super_admin')];

  // GET /api/cycles/status — any authenticated user can check if registration is open
  app.get('/status', { preHandler: authenticate }, async (_request, reply) => {
    const cycle = await findOpenCycle();
    return reply.send({
      open: !!cycle,
      openedAt: cycle?.openedAt ?? null,
      scheduledClosedAt: cycle?.scheduledClosedAt ?? null,
    });
  });

  // POST /api/cycles/open — super_admin only, with the date the cycle closes by itself
  app.post('/open', { preHandler }, async (request, reply) => {
    const { scheduledClosedAt } = openBody.parse(request.body);
    const closesAt = new Date(scheduledClosedAt);
    const openedAt = new Date();
    if (closesAt <= openedAt) {
      return reply.status(400).send({ message: 'The closing date must be in the future' });
    }

    // A cycle past its date may still be marked open if the job has not run yet
    await closeExpiredCycles();
    const existing = await prisma.registrationCycle.findFirst({ where: { status: 'open' } });
    if (existing) return reply.status(409).send({ message: 'A registration cycle is already open' });

    // Unblock phones that were only temporarily banned (removed users)
    await prisma.bannedPhone.deleteMany({ where: { permanent: false } });

    // Opening a cycle starts a new group: everyone who registers in it joins that group
    const cycle = await prisma.registrationCycle.create({
      data: {
        status: 'open',
        openedBy: request.user.id,
        openedAt,
        scheduledClosedAt: closesAt,
        group: { create: { startedAt: openedAt } },
      },
      include: { group: true },
    });

    return reply.status(201).send(cycle);
  });

  // POST /api/cycles/close — super_admin only, closes the cycle before its date
  app.post('/close', { preHandler }, async (_request, reply) => {
    const cycle = await findOpenCycle();
    if (!cycle) return reply.status(404).send({ message: 'No open registration cycle' });

    const updated = await prisma.registrationCycle.update({
      where: { id: cycle.id },
      data: { status: 'closed', closedAt: new Date() },
    });

    return reply.send(updated);
  });
}
