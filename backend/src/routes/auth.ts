import { FastifyInstance, FastifyReply } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { env } from '../config/env.js';
import { verifyFirebaseToken, EmailNotVerifiedError } from '../services/firebase-auth.service.js';
import { authenticate } from '../middleware/authenticate.js';
import { randomUUID } from 'crypto';
import { addDays } from '../utils/date.js';
import { findOpenCycle } from '../services/cycle.service.js';

const firebaseBody = z.object({ idToken: z.string().min(1) });
const registerBody = z.object({
  idToken: z.string().min(1),
  name: z.string().min(1),
  surname: z.string().min(1),
  motivation: z.string().min(1),
});
const refreshBody = z.object({ refreshToken: z.string() });
const deviceBody = z.object({ fcmToken: z.string() });

export async function authRoutes(app: FastifyInstance) {
  // POST /api/auth/dev-login — development only, skips Firebase entirely
  if (env.NODE_ENV === 'development') {
    app.log.warn('NODE_ENV=development: POST /api/auth/dev-login is enabled (login without Firebase)');
    app.post('/dev-login', async (request, reply) => {
      const { email: rawEmail } = z.object({ email: z.string().email() }).parse(request.body);
      const email = rawEmail.trim().toLowerCase();

      const banned = await prisma.bannedEmail.findUnique({ where: { email } });
      if (banned?.permanent) {
        return reply.status(403).send({ message: 'Email permanently banned.', contact: env.ADMIN_CONTACT_EMAIL });
      }

      const user = await prisma.user.findUnique({ where: { email } });
      if (!user) return reply.send({ status: 'register', email });

      if (user.status === 'banned') {
        return reply.status(403).send({ message: 'Account banned.', contact: env.ADMIN_CONTACT_EMAIL });
      }
      if (user.status === 'suspended') {
        return reply.status(403).send({ message: 'Account suspended.' });
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
    if (banned?.permanent) {
      return reply.status(403).send({
        message: 'This email has been permanently banned.',
        contact: env.ADMIN_CONTACT_EMAIL,
      });
    }

    const user = await prisma.user.findUnique({ where: { email } });

    if (!user) {
      if (banned && !banned.permanent) {
        const cycle = await findOpenCycle();
        if (!cycle) {
          return reply.status(403).send({ message: 'Registrations are currently closed.', code: 'registrations_closed' });
        }
      }
      return reply.status(200).send({ status: 'register', email });
    }

    if (user.status === 'banned') {
      return reply.status(403).send({ message: 'Account banned.', contact: env.ADMIN_CONTACT_EMAIL });
    }
    if (user.status === 'suspended') {
      return reply.status(403).send({ message: 'Account suspended. Please contact an admin to restore access.' });
    }

    const { accessToken, refreshToken } = await issueTokens(app, user.id, user.role);
    return reply.send({ status: 'ok', accessToken, refreshToken, user: safeUser(user) });
  });

  // POST /api/auth/register — new users
  app.post('/register', async (request, reply) => {
    const { idToken, name, surname, motivation } = registerBody.parse(request.body);

    const email = await emailFromToken(idToken, reply);
    if (!email) return reply;

    const bannedEmail = await prisma.bannedEmail.findUnique({ where: { email } });
    if (bannedEmail?.permanent) {
      return reply.status(403).send({
        message: 'This email has been permanently banned.',
        contact: env.ADMIN_CONTACT_EMAIL,
      });
    }

    const cycle = await findOpenCycle();
    if (!cycle) {
      return reply.status(403).send({ message: 'Registrations are currently closed.', code: 'registrations_closed' });
    }

    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) return reply.status(409).send({ message: 'Email already registered' });

    if (bannedEmail) {
      await prisma.bannedEmail.delete({ where: { email } });
    }

    const user = await prisma.user.create({
      data: { email, name, surname, motivation, lastConfirmedAt: new Date(), groupId: cycle.group?.id },
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
      return reply.status(401).send({ message: 'Invalid or expired refresh token' });
    }

    await prisma.refreshToken.delete({ where: { id: stored.id } });

    const { accessToken, refreshToken: newRefresh } = await issueTokens(
      app,
      stored.user.id,
      stored.user.role,
    );

    return reply.send({ accessToken, refreshToken: newRefresh });
  });

  // POST /api/auth/logout
  app.post('/logout', { preHandler: authenticate }, async (request, reply) => {
    const { refreshToken } = refreshBody.parse(request.body);
    await prisma.refreshToken.deleteMany({
      where: { userId: request.user.id, token: refreshToken },
    });
    return reply.send({ message: 'Logged out' });
  });

  // POST /api/auth/devices — register a device FCM token
  app.post('/devices', { preHandler: authenticate }, async (request, reply) => {
    const { fcmToken } = deviceBody.parse(request.body);
    await prisma.userDevice.upsert({
      where: { fcmToken },
      update: { userId: request.user.id },
      create: { userId: request.user.id, fcmToken },
    });
    return reply.send({ message: 'Device registered' });
  });

  // DELETE /api/auth/devices — unregister a device FCM token on logout
  app.delete('/devices', { preHandler: authenticate }, async (request, reply) => {
    const { fcmToken } = deviceBody.parse(request.body);
    await prisma.userDevice.deleteMany({
      where: { userId: request.user.id, fcmToken },
    });
    return reply.send({ message: 'Device unregistered' });
  });
}

// Returns the verified email of a Firebase idToken, or sends the error reply and returns null.
async function emailFromToken(idToken: string, reply: FastifyReply): Promise<string | null> {
  try {
    return await verifyFirebaseToken(idToken);
  } catch (err) {
    if (err instanceof EmailNotVerifiedError) {
      reply.status(403).send({ message: 'Email not verified.', code: 'email_not_verified' });
    } else {
      reply.status(401).send({ message: 'Invalid Firebase token' });
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

function safeUser(user: { id: string; email: string; name: string; surname: string; role: string; status: string }) {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    surname: user.surname,
    role: user.role,
    status: user.status,
  };
}
