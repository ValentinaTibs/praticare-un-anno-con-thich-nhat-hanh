import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';
import { UserStatus, Role } from '@prisma/client';

export async function adminRoutes(app: FastifyInstance) {
  const adminHandler = [authenticate, authorize('admin')];
  const superAdminHandler = [authenticate, authorize('super_admin')];

  // PATCH /api/admin/:id/suspend — only active users; a banned user must not be downgraded to suspended
  app.patch('/:id/suspend', { preHandler: adminHandler }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const user = await prisma.user.findUniqueOrThrow({ where: { id }, select: { status: true } });
    if (user.status !== UserStatus.active) {
      return reply.status(409).send({ message: 'Solo un utente attivo può essere sospeso' });
    }
    const updated = await prisma.user.update({
      where: { id },
      data: { status: UserStatus.suspended },
      select: { id: true, status: true },
    });
    return reply.send(updated);
  });

  // PATCH /api/admin/:id/reactivate — only suspended users; lifting a ban is /unban (super_admin)
  app.patch('/:id/reactivate', { preHandler: adminHandler }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const user = await prisma.user.findUniqueOrThrow({ where: { id }, select: { status: true } });
    if (user.status !== UserStatus.suspended) {
      return reply.status(409).send({ message: 'Solo un utente sospeso può essere riattivato' });
    }
    const updated = await prisma.user.update({
      where: { id },
      data: { status: UserStatus.active, lastConfirmedAt: new Date() },
      select: { id: true, status: true },
    });
    return reply.send(updated);
  });

  // PATCH /api/admin/:id/ban — permanent ban: account stays but is marked banned, email blocked forever
  app.patch('/:id/ban', { preHandler: adminHandler }, async (request, reply) => {
    const { id } = request.params as { id: string };

    const user = await prisma.user.findUniqueOrThrow({
      where: { id },
      select: { email: true },
    });

    await prisma.$transaction([
      prisma.user.update({
        where: { id },
        data: { status: UserStatus.banned },
      }),
      prisma.bannedEmail.upsert({
        where: { email: user.email },
        update: { permanent: true },
        create: { email: user.email, permanent: true },
      }),
    ]);

    return reply.send({ id, status: 'banned' });
  });

  // PATCH /api/admin/:id/unban — super_admin only: user back to active, email no longer blocked
  app.patch('/:id/unban', { preHandler: superAdminHandler }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const user = await prisma.user.findUniqueOrThrow({ where: { id }, select: { email: true, status: true } });
    if (user.status !== UserStatus.banned) {
      return reply.status(409).send({ message: 'L\'utente non è bannato' });
    }

    const [updated] = await prisma.$transaction([
      prisma.user.update({
        where: { id },
        data: { status: UserStatus.active, lastConfirmedAt: new Date() },
        select: { id: true, status: true },
      }),
      prisma.bannedEmail.deleteMany({ where: { email: user.email } }),
    ]);

    return reply.send(updated);
  });

  // DELETE /api/admin/:id — remove user: account deleted, email blocked until next cycle
  app.delete('/:id', { preHandler: adminHandler }, async (request, reply) => {
    const { id } = request.params as { id: string };

    const user = await prisma.user.findUniqueOrThrow({
      where: { id },
      select: { email: true },
    });

    // Orphan their scheduled posts — mark as draft so they won't auto-publish
    await prisma.mainChannelPost.updateMany({
      where: { authorId: id, publishedAt: null, isDraft: false },
      data: { isDraft: true },
    });

    await prisma.$transaction([
      prisma.bannedEmail.upsert({
        where: { email: user.email },
        update: { permanent: false },
        create: { email: user.email, permanent: false },
      }),
      prisma.user.delete({ where: { id } }),
    ]);

    return reply.status(204).send();
  });

  // PATCH /api/admin/:id/review — mark user as reviewed by admin
  app.patch('/:id/review', { preHandler: adminHandler }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const user = await prisma.user.update({
      where: { id },
      data: { reviewedByAdmin: true },
      select: { id: true, reviewedByAdmin: true },
    });
    return reply.send(user);
  });

  // PATCH /api/admin/:id/role — super_admin only
  app.patch(
    '/:id/role',
    { preHandler: superAdminHandler },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      const { role } = z.object({ role: z.nativeEnum(Role) }).parse(request.body);
      const user = await prisma.user.update({
        where: { id },
        data: { role },
        select: { id: true, role: true },
      });
      return reply.send(user);
    },
  );
}
