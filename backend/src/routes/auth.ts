import { FastifyInstance, FastifyReply } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { env } from '../config/env.js';
import { FirebaseNotConfiguredError } from '../config/firebase-error.js';
import { verifyFirebaseToken, EmailNotVerifiedError } from '../services/firebase-auth.service.js';
import { authenticate } from '../middleware/authenticate.js';
import { randomUUID } from 'crypto';
import { addDays } from '../utils/date.js';

const firebaseBody = z.object({ idToken: z.string().min(1) });
const registerBody = z.object({
  idToken: z.string().min(1),
  name: z.string().min(1),
  surname: z.string().min(1),
  motivation: z.string().min(1),
});
const refreshBody = z.object({ refreshToken: z.string() });
const deviceBody = z.object({ fcmToken: z.string() });
const withGroup = { group: { select: { id: true, startedAt: true, endedAt: true } } } as const;

export async function authRoutes(app: FastifyInstance) {
  // POST /api/auth/dev-login — development only, skips Firebase entirely
  if (env.NODE_ENV === 'development') {
    app.log.warn('NODE_ENV=development: POST /api/auth/dev-login is enabled (login without Firebase)');
    app.post('/dev-login', async (request, reply) => {
      const { email: rawEmail } = z.object({ email: z.string().email() }).parse(request.body);
      const email = rawEmail.trim().toLowerCase();

      const banned = await prisma.bannedEmail.findUnique({ where: { email } });
      if (banned) {
        return reply.status(403).send({ message: 'Email bannata in modo permanente.', contact: env.ADMIN_CONTACT_EMAIL });
      }

      const user = await prisma.user.findUnique({ where: { email }, include: withGroup });
      if (!user) return reply.send({ status: 'register', email });

      if (user.status === 'banned') {
        return reply.status(403).send({ message: 'Account bannato.', contact: env.ADMIN_CONTACT_EMAIL });
      }
      if (user.status === 'suspended') {
        return reply.status(403).send({ message: 'Account sospeso.' });
      }

      const { accessToken, refreshToken } = await issueTokens(app, user.id, user.role);
      return reply.send({ status: 'ok', accessToken, refreshToken, user: safeUser(user) });
    });
  }

  // POST /api/auth/verify-firebase — login for existing users
  app.post('/verify-firebase', async (request, reply) => {
    const { idToken } = firebaseBody.parse(request.body);

    const email = await emailFromToken(idToken, reply);
    if (!email) return reply;

    const banned = await prisma.bannedEmail.findUnique({ where: { email } });
    if (banned) {
      return reply.status(403).send({
        message: 'Questa email è stata bannata in modo permanente.',
        contact: env.ADMIN_CONTACT_EMAIL,
      });
    }

    const user = await prisma.user.findUnique({ where: { email }, include: withGroup });

    if (!user) return reply.status(200).send({ status: 'register', email });

    if (user.status === 'banned') {
      return reply.status(403).send({ message: 'Account bannato.', contact: env.ADMIN_CONTACT_EMAIL });
    }
    if (user.status === 'suspended') {
      return reply.status(403).send({ message: 'Account sospeso. Contatta un amministratore per riattivarlo.' });
    }

    const { accessToken, refreshToken } = await issueTokens(app, user.id, user.role);
    return reply.send({ status: 'ok', accessToken, refreshToken, user: safeUser(user) });
  });

  // POST /api/auth/register — new users, always open: they start as waiting users
  app.post('/register', async (request, reply) => {
    const { idToken, name, surname, motivation } = registerBody.parse(request.body);

    const email = await emailFromToken(idToken, reply);
    if (!email) return reply;

    const bannedEmail = await prisma.bannedEmail.findUnique({ where: { email } });
    if (bannedEmail) {
      return reply.status(403).send({
        message: 'Questa email è stata bannata in modo permanente.',
        contact: env.ADMIN_CONTACT_EMAIL,
      });
    }

    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) return reply.status(409).send({ message: 'Email già registrata' });

    const user = await prisma.user.create({
      data: { email, name, surname, motivation, lastConfirmedAt: new Date() },
    });

    const { accessToken, refreshToken } = await issueTokens(app, user.id, user.role);
    return reply.status(201).send({ accessToken, refreshToken, user: safeUser(user) });
  });

  // POST /api/auth/refresh
  app.post('/refresh', async (request, reply) => {
    const { refreshToken } = refreshBody.parse(request.body);

    const stored = await prisma.refreshToken.findUnique({
      where: { token: refreshToken },
      include: { user: true },
    });

    if (!stored || stored.expiresAt < new Date()) {
      return reply.status(401).send({ message: 'Sessione non valida o scaduta' });
    }

    await prisma.refreshToken.delete({ where: { id: stored.id } });

    const { accessToken, refreshToken: newRefresh } = await issueTokens(
      app,
      stored.user.id,
      stored.user.role,
    );

    return reply.send({ accessToken, refreshToken: newRefresh });
  });

  // POST /api/auth/logout — the refresh token is its own credential: asking for
  // a valid access token too would make the client rotate it first, leaving the
  // new one alive, and would stop a suspended user from revoking it.
  app.post('/logout', async (request, reply) => {
    const { refreshToken } = refreshBody.parse(request.body);
    await prisma.refreshToken.deleteMany({ where: { token: refreshToken } });
    return reply.send({ message: 'Disconnesso' });
  });

  // POST /api/auth/devices — register a device FCM token
  app.post('/devices', { preHandler: authenticate }, async (request, reply) => {
    const { fcmToken } = deviceBody.parse(request.body);
    await prisma.userDevice.upsert({
      where: { fcmToken },
      update: { userId: request.user.id },
      create: { userId: request.user.id, fcmToken },
    });
    return reply.send({ message: 'Dispositivo registrato' });
  });

  // DELETE /api/auth/devices — unregister a device FCM token on logout
  app.delete('/devices', { preHandler: authenticate }, async (request, reply) => {
    const { fcmToken } = deviceBody.parse(request.body);
    await prisma.userDevice.deleteMany({
      where: { userId: request.user.id, fcmToken },
    });
    return reply.send({ message: 'Dispositivo rimosso' });
  });
}

// Returns the verified email of a Firebase idToken, or sends the error reply and returns null.
async function emailFromToken(idToken: string, reply: FastifyReply): Promise<string | null> {
  try {
    return await verifyFirebaseToken(idToken);
  } catch (err) {
    if (err instanceof EmailNotVerifiedError) {
      reply.status(403).send({ message: 'Email non verificata.', code: 'email_not_verified' });
    } else if (err instanceof FirebaseNotConfiguredError) {
      reply.status(503).send({
        message: 'Accesso non disponibile: il server non ha la chiave Firebase.',
        code: 'firebase_not_configured',
      });
    } else {
      reply.status(401).send({ message: 'Token di accesso non valido' });
    }
    return null;
  }
}

async function issueTokens(app: FastifyInstance, userId: string, role: string) {
  const accessToken = app.jwt.sign(
    { sub: userId, role },
    { expiresIn: env.JWT_ACCESS_EXPIRES_IN },
  );

  const refreshToken = randomUUID();
  await prisma.refreshToken.create({
    data: {
      userId,
      token: refreshToken,
      expiresAt: addDays(new Date(), 30),
    },
  });

  return { accessToken, refreshToken };
}

function safeUser(user: {
  id: string;
  email: string;
  name: string;
  surname: string;
  role: string;
  status: string;
  group?: { id: string; startedAt: Date; endedAt: Date | null } | null;
}) {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    surname: user.surname,
    role: user.role,
    status: user.status,
    // The app tells waiting users from group members with it, as with /api/users/me.
    group: user.group ?? null,
  };
}
