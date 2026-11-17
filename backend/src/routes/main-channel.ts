import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';

const content = z.string().trim().min(1);
const journeyDay = z.number().int().min(1);
const publishTime = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
const templateStatus = z.enum(['draft', 'scheduled']);

const createTemplateBody = z.object({
  content,
  journeyDay,
  publishTime: publishTime.default('08:00'),
  status: templateStatus.default('draft'),
});

const updateTemplateBody = z.object({
  content: content.optional(),
  journeyDay: journeyDay.optional(),
  publishTime: publishTime.optional(),
  status: templateStatus.optional(),
});

const updatePostBody = z.object({ content });

const pageQuery = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

const author = { select: { id: true, name: true, surname: true } } as const;

const templateFields = {
  id: true,
  content: true,
  journeyDay: true,
  publishTime: true,
  status: true,
  createdAt: true,
  updatedAt: true,
  author,
} as const;

// Participants never see who wrote a post: the author is only for the panel.
const appPostFields = { id: true, content: true, publishedAt: true, createdAt: true } as const;

const panelPostFields = {
  id: true,
  groupId: true,
  templateId: true,
  content: true,
  publishedAt: true,
  createdAt: true,
  updatedAt: true,
  author,
} as const;

const newestFirst = [{ publishedAt: 'desc' }, { createdAt: 'desc' }] as const;

export async function mainChannelRoutes(app: FastifyInstance) {
  const adminHandler = [authenticate, authorize('admin')];

  // GET /api/main-channel/posts — the published posts of the user's active group
  app.get('/posts', { preHandler: authenticate }, async (request, reply) => {
    const { page, limit } = pageQuery.parse(request.query);
    const now = new Date();

    // Waiting users have no Main Channel.
    const group = request.user.groupId
      ? await prisma.group.findFirst({
          where: {
            id: request.user.groupId,
            startedAt: { lte: now },
            OR: [{ endedAt: null }, { endedAt: { gt: now } }],
          },
          select: { id: true },
        })
      : null;
    if (!group) return reply.send({ posts: [], total: 0, page, limit });

    const where = { groupId: group.id };
    const [posts, total] = await Promise.all([
      prisma.mainChannelPost.findMany({
        where,
        orderBy: [...newestFirst],
        skip: (page - 1) * limit,
        take: limit,
        select: appPostFields,
      }),
      prisma.mainChannelPost.count({ where }),
    ]);

    return reply.send({ posts, total, page, limit });
  });

  // GET /api/main-channel/groups/:groupId/posts — admin only, any group, also archived
  app.get('/groups/:groupId/posts', { preHandler: adminHandler }, async (request, reply) => {
    const { groupId } = request.params as { groupId: string };
    const { page, limit } = pageQuery.parse(request.query);
    await prisma.group.findUniqueOrThrow({ where: { id: groupId }, select: { id: true } });

    const where = { groupId };
    const [posts, total] = await Promise.all([
      prisma.mainChannelPost.findMany({
        where,
        orderBy: [...newestFirst],
        skip: (page - 1) * limit,
        take: limit,
        select: panelPostFields,
      }),
      prisma.mainChannelPost.count({ where }),
    ]);

    return reply.send({ posts, total, page, limit });
  });

  // PATCH /api/main-channel/posts/:id — admin only, the post in its own group, no push
  app.patch('/posts/:id', { preHandler: adminHandler }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const data = updatePostBody.parse(request.body);
    const post = await prisma.mainChannelPost.update({ where: { id }, data, select: panelPostFields });
    return reply.send(post);
  });

  // DELETE /api/main-channel/posts/:id — admin only, the post in its own group
  app.delete('/posts/:id', { preHandler: adminHandler }, async (request, reply) => {
    const { id } = request.params as { id: string };
    await prisma.mainChannelPost.delete({ where: { id } });
    return reply.status(204).send();
  });

  // GET /api/main-channel/templates — admin only, the sequence with its drafts
  app.get('/templates', { preHandler: adminHandler }, async (_request, reply) => {
    const templates = await prisma.mainChannelTemplate.findMany({
      orderBy: [{ journeyDay: 'asc' }, { publishTime: 'asc' }, { createdAt: 'asc' }],
      select: templateFields,
    });
    return reply.send(templates);
  });

  // POST /api/main-channel/templates — admin only
  app.post('/templates', { preHandler: adminHandler }, async (request, reply) => {
    const body = createTemplateBody.parse(request.body);
    const template = await prisma.mainChannelTemplate.create({
      data: {
        ...body,
        authorId: request.user.id,
        sequencedAt: body.status === 'scheduled' ? new Date() : null,
      },
      select: templateFields,
    });
    return reply.status(201).send(template);
  });

  // PATCH /api/main-channel/templates/:id — admin only. Posts already published stay as they are.
  app.patch('/templates/:id', { preHandler: adminHandler }, async (request, reply) => {
    const { id } = request.params as { id: string };
    const changes = updateTemplateBody.parse(request.body);
    const current = await prisma.mainChannelTemplate.findUniqueOrThrow({ where: { id } });

    const status = changes.status ?? current.status;
    const moved =
      current.status !== 'scheduled' ||
      (changes.journeyDay !== undefined && changes.journeyDay !== current.journeyDay) ||
      (changes.publishTime !== undefined && changes.publishTime !== current.publishTime);
    // Entering the sequence, or moving within it, counts only for groups that haven't
    // reached the new moment yet. A change of text alone keeps the template's place.
    const sequencedAt = status === 'draft' ? null : moved ? new Date() : current.sequencedAt;

    const template = await prisma.mainChannelTemplate.update({
      where: { id },
      data: { ...changes, sequencedAt },
      select: templateFields,
    });
    return reply.send(template);
  });

  // DELETE /api/main-channel/templates/:id — admin only. Posts already published stay.
  app.delete('/templates/:id', { preHandler: adminHandler }, async (request, reply) => {
    const { id } = request.params as { id: string };
    await prisma.mainChannelTemplate.delete({ where: { id } });
    return reply.status(204).send();
  });
}
