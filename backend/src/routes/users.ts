import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { Prisma, UserStatus } from '@prisma/client';
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

const usersQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  status: z.nativeEnum(UserStatus).optional(),
  reviewed: z.enum(['true', 'false']).optional(),
  groupId: z.string().min(1).optional(),
  // Matches name, surname or email, ignoring case
  q: z.string().trim().max(100).optional(),
});

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

  // Admin: GET /api/users — supports ?page=&limit=&status=&reviewed=&groupId=&q=
  app.get(
    '/',
    { preHandler: [authenticate, authorize('admin')] },
    async (request, reply) => {
      const { page, limit, status, reviewed, groupId, q } = usersQuerySchema.parse(request.query);

      const where: Prisma.UserWhereInput = {};
      if (status) where.status = status;
      if (reviewed) where.reviewedByAdmin = reviewed === 'true';
      if (groupId) where.groupId = groupId;
      if (q) {
        const match = { contains: q, mode: 'insensitive' } as const;
        where.OR = [{ name: match }, { surname: match }, { email: match }];
      }

      const [users, total] = await Promise.all([
        prisma.user.findMany({
          where,
          skip: (page - 1) * limit,
          take: limit,
          orderBy: { createdAt: 'desc' },
          select: adminUserSelect,
        }),
        prisma.user.count({ where }),
      ]);

      return reply.send({ users, total, page, limit });
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
