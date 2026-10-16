import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { env } from '../config/env.js';
import { verifyFirebaseToken } from '../services/otp.service.js';
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
    app.post('/dev-login', async (request, reply) => {
      const { phoneNumber } = z.object({ phoneNumber: z.string() }).parse(request.body);

      const banned = await prisma.bannedPhone.findUnique({ where: { phoneNumber } });
      if (banned?.permanent) {
        return reply.status(403).send({ message: 'Phone permanently banned.', contact: env.ADMIN_CONTACT_EMAIL });
      }

      const user = await prisma.user.findUnique({ where: { phoneNumber } });
      if (!user) return reply.send({ status: 'register', phoneNumber });

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

    let phoneNumber: string;
    try {
      phoneNumber = await verifyFirebaseToken(idToken);
    } catch {
      return reply.status(401).send({ message: 'Invalid Firebase token' });
    }

    const banned = await prisma.bannedPhone.findUnique({ where: { phoneNumber } });
    if (banned?.permanent) {
      return reply.status(403).send({
        message: 'This phone number has been permanently banned.',
        contact: env.ADMIN_CONTACT_EMAIL,
      });
    }

    const user = await prisma.user.findUnique({ where: { phoneNumber } });

    if (!user) {
      if (banned && !banned.permanent) {
        const cycle = await findOpenCycle();
        if (!cycle) {
          return reply.status(403).send({ message: 'Registrations are currently closed.' });
        }
      }
      return reply.status(200).send({ status: 'register', phoneNumber });
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

    let phoneNumber: string;
    try {
      phoneNumber = await verifyFirebaseToken(idToken);
    } catch {
      return reply.status(401).send({ message: 'Invalid Firebase token' });
    }

    const bannedPhone = await prisma.bannedPhone.findUnique({ where: { phoneNumber } });
    if (bannedPhone?.permanent) {
      return reply.status(403).send({
        message: 'This phone number has been permanently banned.',
        contact: env.ADMIN_CONTACT_EMAIL,
      });
    }

    const cycle = await findOpenCycle();
    if (!cycle) {
      return reply.status(403).send({ message: 'Registrations are currently closed.' });
    }

    const existing = await prisma.user.findUnique({ where: { phoneNumber } });
    if (existing) return reply.status(409).send({ message: 'Phone already registered' });

    if (bannedPhone) {
      await prisma.bannedPhone.delete({ where: { phoneNumber } });
    }

    const user = await prisma.user.create({
      data: { phoneNumber, name, surname, motivation, lastConfirmedAt: new Date(), groupId: cycle.group?.id },
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

function safeUser(user: { id: string; name: string; surname: string; role: string; status: string }) {
  return { id: user.id, name: user.name, surname: user.surname, role: user.role, status: user.status };
}
