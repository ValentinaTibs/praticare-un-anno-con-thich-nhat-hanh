import { FastifyInstance } from 'fastify';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { UserStatus } from '@prisma/client';

export async function confirmationRoutes(app: FastifyInstance) {
  // GET /api/confirmations/pending — current user's pending request (if any)
  app.get('/pending', { preHandler: authenticate }, async (request, reply) => {
    const pending = await prisma.confirmationRequest.findFirst({
      where: { userId: request.user.id, status: 'pending' },
      orderBy: { dueAt: 'asc' },
    });
    return reply.send(pending ?? null);
  });

  // POST /api/confirmations/confirm — user self-confirms
  app.post('/confirm', { preHandler: authenticate }, async (request, reply) => {
    const pending = await prisma.confirmationRequest.findFirst({
      where: { userId: request.user.id, status: 'pending' },
    });

    if (!pending) {
      return reply.status(404).send({ message: 'No pending confirmation request' });
    }

    await prisma.$transaction([
      prisma.confirmationRequest.update({
        where: { id: pending.id },
        data: { status: 'confirmed', confirmedAt: new Date() },
      }),
      prisma.user.update({
        where: { id: request.user.id },
        data: { status: UserStatus.active, lastConfirmedAt: new Date() },
      }),
    ]);

    return reply.send({ confirmed: true });
  });
}
