import { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize, outranks } from '../middleware/authorize.js';
import { Prisma, UserStatus, Role } from '@prisma/client';

function httpError(statusCode: number, message: string) {
  return Object.assign(new Error(message), { statusCode });
}

// The user an action is aimed at: 404 if missing, 403 if the caller does not outrank them
// (or, with anyRank, if they are the caller). The error handler turns the thrown
// statusCode and message into the response.
async function findTarget(request: FastifyRequest, { anyRank = false } = {}) {
  const { id } = request.params as { id: string };
  const target = await prisma.user.findUniqueOrThrow({
    where: { id },
    select: { id: true, role: true, status: true, email: true },
  });
  const allowed = anyRank ? target.id !== request.user.id : outranks(request.user.role, target.role);
  if (!allowed) throw httpError(403, 'Non puoi eseguire questa azione su questo utente');
  return target;
}

// The writes below repeat the status check in their where clause, so a change made by
// another admin after findTarget (e.g. a ban) can't be overwritten. When the row no longer
// matches, Prisma throws P2025 and the transaction rolls back: that becomes a 409.
async function unlessChanged<T>(write: Promise<T>, message: string): Promise<T> {
  try {
    return await write;
  } catch (error) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025') {
      throw httpError(409, message);
    }
    throw error;
  }
}

export async function adminRoutes(app: FastifyInstance) {
  const adminHandler = [authenticate, authorize('admin')];
  const superAdminHandler = [authenticate, authorize('super_admin')];

  // PATCH /api/admin/:id/suspend — only active users; a banned user must not be downgraded to suspended
  app.patch('/:id/suspend', { preHandler: adminHandler }, async (request, reply) => {
    const target = await findTarget(request);
    const conflict = 'Solo un utente attivo può essere sospeso';
    if (target.status !== UserStatus.active) return reply.status(409).send({ message: conflict });
    const updated = await unlessChanged(
      prisma.user.update({
        where: { id: target.id, status: UserStatus.active },
        data: { status: UserStatus.suspended },
        select: { id: true, status: true },
      }),
      conflict,
    );
    return reply.send(updated);
  });

  // PATCH /api/admin/:id/reactivate — only suspended users; lifting a ban is /unban (super_admin).
  // Any admin reactivates anyone, whatever the role: the spec leaves it to "an admin", and an
  // admin or the Super Admin suspended for a missed confirmation can't reactivate themselves.
  app.patch('/:id/reactivate', { preHandler: adminHandler }, async (request, reply) => {
    const target = await findTarget(request, { anyRank: true });
    const conflict = 'Solo un utente sospeso può essere riattivato';
    if (target.status !== UserStatus.suspended) return reply.status(409).send({ message: conflict });
    const updated = await unlessChanged(
      prisma.user.update({
        where: { id: target.id, status: UserStatus.suspended },
        data: { status: UserStatus.active, lastConfirmedAt: new Date() },
        select: { id: true, status: true },
      }),
      conflict,
    );
    return reply.send(updated);
  });

  // PATCH /api/admin/:id/ban — permanent ban: account stays but is marked banned, email blocked forever
  app.patch('/:id/ban', { preHandler: adminHandler }, async (request, reply) => {
    const target = await findTarget(request);

    await prisma.$transaction([
      prisma.user.update({
        where: { id: target.id },
        data: { status: UserStatus.banned },
      }),
      prisma.bannedEmail.upsert({
        where: { email: target.email },
        update: {},
        create: { email: target.email },
      }),
    ]);

    return reply.send({ id: target.id, status: 'banned' });
  });

  // PATCH /api/admin/:id/unban — super_admin only: user back to active, email no longer blocked
  app.patch('/:id/unban', { preHandler: superAdminHandler }, async (request, reply) => {
    const target = await findTarget(request);
    const conflict = 'L\'utente non è bannato';
    if (target.status !== UserStatus.banned) return reply.status(409).send({ message: conflict });

    const [updated] = await unlessChanged(
      prisma.$transaction([
        prisma.user.update({
          where: { id: target.id, status: UserStatus.banned },
          data: { status: UserStatus.active, lastConfirmedAt: new Date() },
          select: { id: true, status: true },
        }),
        prisma.bannedEmail.deleteMany({ where: { email: target.email } }),
      ]),
      conflict,
    );

    return reply.send(updated);
  });

  // DELETE /api/admin/:id — remove user: account deleted, email free to register again.
  // Only from active or suspended: a ban keeps the account and blocks the email for good.
  app.delete('/:id', { preHandler: adminHandler }, async (request, reply) => {
    const target = await findTarget(request);
    const conflict = 'Un utente bannato non può essere rimosso';
    if (target.status === UserStatus.banned) return reply.status(409).send({ message: conflict });

    // All or nothing: their scheduled posts become drafts so they won't auto-publish,
    // and their sharing channel messages go with the account (cascade). If a ban arrived
    // meanwhile, the delete matches nothing and the ban stays.
    await unlessChanged(
      prisma.$transaction([
        prisma.mainChannelPost.updateMany({
          where: { authorId: target.id, publishedAt: null, isDraft: false },
          data: { isDraft: true },
        }),
        prisma.user.delete({ where: { id: target.id, status: { not: UserStatus.banned } } }),
      ]),
      conflict,
    );

    return reply.status(204).send();
  });

  // PATCH /api/admin/:id/review — mark user as reviewed by admin. Harmless and final,
  // so any admin may review anyone but themselves: the review is what lets a waiting
  // user into a path, and an admin can be waiting too.
  app.patch('/:id/review', { preHandler: adminHandler }, async (request, reply) => {
    const { id } = request.params as { id: string };
    if (id === request.user.id) throw httpError(403, 'Non puoi revisionare il tuo account');
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
