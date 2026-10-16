import { FastifyInstance } from 'fastify';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';

export async function groupRoutes(app: FastifyInstance) {
  // GET /api/groups — admin only, every group with its cycle and member count
  app.get('/', { preHandler: [authenticate, authorize('admin')] }, async (_request, reply) => {
    const groups = await prisma.group.findMany({
      orderBy: { startedAt: 'desc' },
      include: {
        cycle: { select: { id: true, status: true, openedAt: true, closedAt: true } },
        _count: { select: { members: true } },
      },
    });

    return reply.send(
      groups.map(({ _count, ...group }) => ({ ...group, memberCount: _count.members })),
    );
  });
}
