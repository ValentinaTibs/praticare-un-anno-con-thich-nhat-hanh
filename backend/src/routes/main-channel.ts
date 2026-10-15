import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';
import { pushToAll } from '../services/push.service.js';

const createPostBody = z.object({
  content: z.string().min(1),
  mediaUrl: z.string().url().optional(),
  scheduledAt: z.string().datetime().optional(),
});

const updatePostBody = z.object({
  content: z.string().min(1).optional(),
  mediaUrl: z.string().url().optional(),
  scheduledAt: z.string().datetime().optional(),
  publishNow: z.boolean().optional(),
  isDraft: z.boolean().optional(),
});

export async function mainChannelRoutes(app: FastifyInstance) {
  // GET /api/main-channel/posts — all authenticated users, published only
  app.get('/posts', { preHandler: authenticate }, async (request, reply) => {
    const { page = '1', limit = '20' } = request.query as Record<string, string>;
    const skip = (Number(page) - 1) * Number(limit);

    const [posts, total] = await Promise.all([
      prisma.mainChannelPost.findMany({
        where: { publishedAt: { not: null, lte: new Date() } },
        orderBy: { publishedAt: 'desc' },
        skip,
        take: Number(limit),
        include: {
          author: { select: { id: true, name: true, surname: true } },
        },
      }),
      prisma.mainChannelPost.count({
        where: { publishedAt: { not: null, lte: new Date() } },
      }),
    ]);

    return reply.send({ posts, total, page: Number(page), limit: Number(limit) });
  });

  // GET /api/main-channel/drafts — admin only, unpublished posts (scheduled + orphaned drafts)
  app.get(
    '/drafts',
    { preHandler: [authenticate, authorize('admin')] },
    async (_request, reply) => {
      const posts = await prisma.mainChannelPost.findMany({
        where: { publishedAt: null },
        orderBy: { createdAt: 'desc' },
        include: {
          author: { select: { id: true, name: true, surname: true } },
        },
      });
      return reply.send(posts);
    },
  );

  // POST /api/main-channel/posts — admin only
  app.post(
    '/posts',
    { preHandler: [authenticate, authorize('admin')] },
    async (request, reply) => {
      const { content, mediaUrl, scheduledAt } = createPostBody.parse(request.body);

      const isScheduled = !!scheduledAt;
      const post = await prisma.mainChannelPost.create({
        data: {
          authorId: request.user.id,
          content,
          mediaUrl,
          scheduledAt: isScheduled ? new Date(scheduledAt!) : null,
          publishedAt: isScheduled ? null : new Date(),
        },
        include: { author: { select: { id: true, name: true, surname: true } } },
      });

      if (!isScheduled) {
        await pushToAll('New post', content.slice(0, 100), { type: 'main_channel:new_post' });
      }

      return reply.status(201).send(post);
    },
  );

  // PATCH /api/main-channel/posts/:id — admin only
  app.patch(
    '/posts/:id',
    { preHandler: [authenticate, authorize('admin')] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      const { content, mediaUrl, scheduledAt, publishNow, isDraft } = updatePostBody.parse(request.body);

      const data: Record<string, unknown> = {};
      if (content !== undefined) data.content = content;
      if (mediaUrl !== undefined) data.mediaUrl = mediaUrl;
      if (scheduledAt !== undefined) data.scheduledAt = new Date(scheduledAt);
      if (isDraft !== undefined) data.isDraft = isDraft;

      if (publishNow) {
        data.publishedAt = new Date();
        data.scheduledAt = null;
        data.isDraft = false;
      }

      const post = await prisma.mainChannelPost.update({
        where: { id },
        data,
        include: { author: { select: { id: true, name: true, surname: true } } },
      });

      if (publishNow) {
        await pushToAll('New post', post.content.slice(0, 100), { type: 'main_channel:new_post' });
      }

      return reply.send(post);
    },
  );

  // DELETE /api/main-channel/posts/:id — admin only
  app.delete(
    '/posts/:id',
    { preHandler: [authenticate, authorize('admin')] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      await prisma.mainChannelPost.delete({ where: { id } });
      return reply.status(204).send();
    },
  );
}
