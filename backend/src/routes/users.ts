import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';

const adminUserSelect = {
  id: true,
  name: true,
  surname: true,
  email: true,
  motivation: true,
  role: true,
  status: true,
  reviewedByAdmin: true,
  lastConfirmedAt: true,
  groupId: true,
  createdAt: true,
} as const;

export async function userRoutes(app: FastifyInstance) {
  // GET /api/users/me
  app.get('/me', { preHandler: authenticate }, async (request, reply) => {
    const user = await prisma.user.findUniqueOrThrow({
      where: { id: request.user.id },
      select: {
        id: true,
        name: true,
        surname: true,
        email: true,
        role: true,
        status: true,
        lastConfirmedAt: true,
        createdAt: true,
        group: { select: { id: true, startedAt: true, endedAt: true } },
      },
    });
    return reply.send(user);
  });

  // PATCH /api/users/me
  app.patch('/me', { preHandler: authenticate }, async (request, reply) => {
    const body = z
      .object({ name: z.string().optional(), surname: z.string().optional() })
      .parse(request.body);

    const user = await prisma.user.update({
      where: { id: request.user.id },
      data: body,
      select: { id: true, name: true, surname: true, role: true, status: true },
    });
    return reply.send(user);
  });

  // Admin: GET /api/users — supports ?status=&reviewed=false&groupId=
  app.get(
    '/',
    { preHandler: [authenticate, authorize('admin')] },
    async (request, reply) => {
      const { page = '1', limit = '20', status, reviewed, groupId } = request.query as Record<string, string>;
      const skip = (Number(page) - 1) * Number(limit);

      const where: Record<string, unknown> = {};
      if (status) where.status = status;
      if (reviewed === 'false') where.reviewedByAdmin = false;
      if (groupId) where.groupId = groupId;

      const [users, total] = await Promise.all([
        prisma.user.findMany({
          where,
          skip,
          take: Number(limit),
          orderBy: { createdAt: 'desc' },
          select: adminUserSelect,
        }),
        prisma.user.count({ where }),
      ]);

      return reply.send({ users, total, page: Number(page), limit: Number(limit) });
    },
  );

  // Admin: GET /api/users/:id
  app.get(
    '/:id',
    { preHandler: [authenticate, authorize('admin')] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      const user = await prisma.user.findUniqueOrThrow({
        where: { id },
        select: adminUserSelect,
      });
      return reply.send(user);
    },
  );
}
