import { FastifyRequest, FastifyReply } from 'fastify';
import { prisma } from '../config/prisma.js';
import { env } from '../config/env.js';
import { UserStatus } from '@prisma/client';

export interface JwtPayload {
  sub: string;
  role: string;
}

export interface AuthUser {
  id: string;
  role: string;
  status: UserStatus;
  groupId: string | null;
}

// @fastify/jwt owns the type of request.user: declare it here instead of on FastifyRequest.
declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: JwtPayload;
    user: AuthUser;
  }
}

export async function authenticate(request: FastifyRequest, reply: FastifyReply) {
  try {
    const payload = await request.jwtVerify<JwtPayload>();

    const dbUser = await prisma.user.findUnique({
      where: { id: payload.sub },
      select: { id: true, role: true, status: true, groupId: true },
    });

    if (!dbUser) {
      return reply.status(401).send({ message: 'Utente non trovato' });
    }

    if (dbUser.status === UserStatus.suspended) {
      return reply.status(403).send({ message: 'Account sospeso. Contatta un amministratore per riattivarlo.' });
    }

    if (dbUser.status === UserStatus.banned) {
      return reply.status(403).send({
        message: 'Account bannato.',
        contact: env.ADMIN_CONTACT_EMAIL,
      });
    }

    request.user = dbUser;
  } catch {
    return reply.status(401).send({ message: 'Non autorizzato' });
  }
}
