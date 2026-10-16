import { FastifyRequest, FastifyReply } from 'fastify';
import { prisma } from '../config/prisma.js';
import { env } from '../config/env.js';
import { UserStatus } from '@prisma/client';

export interface JwtPayload {
  sub: string;
  role: string;
  iat: number;
  exp: number;
}

declare module 'fastify' {
  interface FastifyRequest {
    user: {
      id: string;
      role: string;
      status: UserStatus;
      groupId: string | null;
    };
  }
}

export async function authenticate(request: FastifyRequest, reply: FastifyReply) {
  try {
    await request.jwtVerify();
    const payload = request.user as unknown as JwtPayload;

    const dbUser = await prisma.user.findUnique({
      where: { id: payload.sub },
      select: { id: true, role: true, status: true, groupId: true },
    });

    if (!dbUser) {
      return reply.status(401).send({ message: 'User not found' });
    }

    if (dbUser.status === UserStatus.suspended) {
      return reply.status(403).send({ message: 'Account suspended. Please contact an admin to restore access.' });
    }

    if (dbUser.status === UserStatus.banned) {
      return reply.status(403).send({
        message: 'Account banned.',
        contact: env.ADMIN_CONTACT_EMAIL,
      });
    }

    request.user = dbUser;
  } catch {
    return reply.status(401).send({ message: 'Unauthorized' });
  }
}
