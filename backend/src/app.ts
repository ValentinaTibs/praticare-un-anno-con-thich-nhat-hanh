import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import fjwt from '@fastify/jwt';
import { Prisma } from '@prisma/client';
import { ZodError } from 'zod';
import { env } from './config/env.js';
import { authRoutes } from './routes/auth.js';
import { userRoutes } from './routes/users.js';
import { mainChannelRoutes } from './routes/main-channel.js';
import { sharingChannelRoutes } from './routes/sharing-channel.js';
import { confirmationRoutes } from './routes/confirmations.js';
import { adminRoutes } from './routes/admin.js';
import { cycleRoutes } from './routes/cycles.js';
import { groupRoutes } from './routes/groups.js';

export async function buildApp() {
  const app = Fastify({
    logger: {
      level: env.NODE_ENV === 'test' ? 'silent' : env.NODE_ENV === 'production' ? 'info' : 'debug',
      transport:
        env.NODE_ENV !== 'production'
          ? { target: 'pino-pretty', options: { colorize: true } }
          : undefined,
    },
  });

  await app.register(helmet, { global: true });
  await app.register(cors, { origin: env.CORS_ORIGIN });
  await app.register(rateLimit, { max: 100, timeWindow: '1 minute' });
  await app.register(fjwt, { secret: env.JWT_SECRET });

  app.addHook('onRequest', async (request) => {
    // make verify available on request
    (request as any).jwtVerify = request.jwtVerify.bind(request);
  });

  // Registered before the routes: Fastify plugins capture the error handler at registration time.
  app.setErrorHandler((error, _request, reply) => {
    // P2025: the record targeted by findUniqueOrThrow/update/delete does not exist
    const notFound = error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025';
    const invalidInput = error instanceof ZodError;
    const statusCode = notFound ? 404 : invalidInput ? 400 : error.statusCode ?? 500;
    app.log.error(error);
    reply.status(statusCode).send({
      error: error.name,
      message: error.message,
      statusCode,
    });
  });

  app.get('/health', async () => ({ status: 'ok' }));

  await app.register(authRoutes, { prefix: '/api/auth' });
  await app.register(userRoutes, { prefix: '/api/users' });
  await app.register(mainChannelRoutes, { prefix: '/api/main-channel' });
  await app.register(sharingChannelRoutes, { prefix: '/api/sharing-channel' });
  await app.register(confirmationRoutes, { prefix: '/api/confirmations' });
  await app.register(adminRoutes, { prefix: '/api/admin' });
  await app.register(cycleRoutes, { prefix: '/api/cycles' });
  await app.register(groupRoutes, { prefix: '/api/groups' });

  return app;
}
