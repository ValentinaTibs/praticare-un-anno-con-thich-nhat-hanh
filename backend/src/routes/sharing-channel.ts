import { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';
import { pushToGroup, pushToChannelMembers } from '../services/push.service.js';

const postBody = z.object({
  content: z.string().min(1),
  mediaUrl: z.string().url().optional(),
});

const openBody = z.object({
  scheduledClosedAt: z.string().datetime(),
});

const ROLES_ACROSS_GROUPS = ['admin', 'super_admin'];

// Each group has its own sharing channel. Users act on their group's channel;
// admins manage every group and can pick one with ?groupId=.
function groupIdFor(request: FastifyRequest) {
  const { groupId } = request.query as { groupId?: string };
  if (groupId && ROLES_ACROSS_GROUPS.includes(request.user.role)) return groupId;
  return request.user.groupId;
}

function findOpenChannel(request: FastifyRequest) {
  const groupId = groupIdFor(request);
  if (!groupId) return null;
  return prisma.sharingChannel.findFirst({ where: { status: 'open', groupId } });
}

export async function sharingChannelRoutes(app: FastifyInstance) {
  // GET /api/sharing-channel/status
  app.get('/status', { preHandler: authenticate }, async (request, reply) => {
    const channel = await findOpenChannel(request);

    if (!channel) return reply.send({ status: 'closed' });

    const membership = await prisma.sharingChannelMember.findFirst({
      where: { sharingChannelId: channel.id, userId: request.user.id },
    });

    return reply.send({
      status: 'open',
      channelId: channel.id,
      openedAt: channel.openedAt,
      scheduledClosedAt: channel.scheduledClosedAt,
      joined: !!membership,
    });
  });

  // POST /api/sharing-channel/join
  app.post('/join', { preHandler: authenticate }, async (request, reply) => {
    const channel = await findOpenChannel(request);
    if (!channel) return reply.status(404).send({ message: 'Sharing channel is not open' });

    const existing = await prisma.sharingChannelMember.findFirst({
      where: { sharingChannelId: channel.id, userId: request.user.id },
    });
    if (existing) return reply.status(409).send({ message: 'Already joined' });

    await prisma.sharingChannelMember.create({
      data: { sharingChannelId: channel.id, userId: request.user.id },
    });

    const history = await prisma.sharingChannelPost.findMany({
      where: { sharingChannelId: channel.id },
      orderBy: { createdAt: 'asc' },
      include: { author: { select: { id: true, name: true, surname: true } } },
    });

    await pushToChannelMembers(
      channel.id,
      'New participant',
      'Someone joined the sharing session',
      { type: 'sharing_channel:member_joined', channelId: channel.id },
    );

    return reply.send({ joined: true, history });
  });

  // DELETE /api/sharing-channel/leave
  app.delete('/leave', { preHandler: authenticate }, async (request, reply) => {
    const channel = await findOpenChannel(request);
    if (!channel) return reply.status(404).send({ message: 'Sharing channel is not open' });

    const member = await prisma.sharingChannelMember.findFirst({
      where: { sharingChannelId: channel.id, userId: request.user.id },
    });
    if (!member) return reply.status(404).send({ message: 'Not a member of the sharing channel' });

    await prisma.sharingChannelMember.delete({ where: { id: member.id } });

    await pushToChannelMembers(
      channel.id,
      'Participant left',
      'Someone left the sharing session',
      { type: 'sharing_channel:member_left', channelId: channel.id },
    );

    return reply.send({ left: true });
  });

  // GET /api/sharing-channel/posts — joined members only
  app.get('/posts', { preHandler: authenticate }, async (request, reply) => {
    const channel = await findOpenChannel(request);
    if (!channel) return reply.status(404).send({ message: 'Sharing channel is not open' });

    const member = await prisma.sharingChannelMember.findFirst({
      where: { sharingChannelId: channel.id, userId: request.user.id },
    });
    if (!member) return reply.status(403).send({ message: 'Join the channel first' });

    const posts = await prisma.sharingChannelPost.findMany({
      where: { sharingChannelId: channel.id },
      orderBy: { createdAt: 'asc' },
      include: { author: { select: { id: true, name: true, surname: true } } },
    });

    return reply.send(posts);
  });

  // POST /api/sharing-channel/posts — joined members only
  app.post('/posts', { preHandler: authenticate }, async (request, reply) => {
    const { content, mediaUrl } = postBody.parse(request.body);

    const channel = await findOpenChannel(request);
    if (!channel) return reply.status(404).send({ message: 'Sharing channel is not open' });

    const member = await prisma.sharingChannelMember.findFirst({
      where: { sharingChannelId: channel.id, userId: request.user.id },
    });
    if (!member) return reply.status(403).send({ message: 'Join the channel first' });

    const post = await prisma.sharingChannelPost.create({
      data: { sharingChannelId: channel.id, authorId: request.user.id, content, mediaUrl },
      include: { author: { select: { id: true, name: true, surname: true } } },
    });

    await pushToChannelMembers(
      channel.id,
      post.author.name,
      content.slice(0, 100),
      { type: 'sharing_channel:new_post', channelId: channel.id },
    );

    return reply.status(201).send(post);
  });

  // DELETE /api/sharing-channel/posts/:id — admin only
  app.delete(
    '/posts/:id',
    { preHandler: [authenticate, authorize('admin')] },
    async (request, reply) => {
      const { id } = request.params as { id: string };
      const post = await prisma.sharingChannelPost.findUniqueOrThrow({ where: { id } });

      await prisma.sharingChannelPost.delete({ where: { id } });

      await pushToChannelMembers(
        post.sharingChannelId,
        'Post removed',
        'A post was removed by an admin',
        { type: 'sharing_channel:post_deleted', channelId: post.sharingChannelId },
      );

      return reply.status(204).send();
    },
  );

  // POST /api/sharing-channel/open — admin only
  app.post(
    '/open',
    { preHandler: [authenticate, authorize('admin')] },
    async (request, reply) => {
      const { scheduledClosedAt } = openBody.parse(request.body);

      const groupId = groupIdFor(request);
      if (!groupId) return reply.status(400).send({ message: 'Choose a group with ?groupId=' });

      const existing = await findOpenChannel(request);
      if (existing) return reply.status(409).send({ message: 'Sharing channel is already open' });

      const channel = await prisma.sharingChannel.create({
        data: {
          groupId,
          status: 'open',
          openedBy: request.user.id,
          openedAt: new Date(),
          scheduledClosedAt: new Date(scheduledClosedAt),
        },
      });

      await pushToGroup(groupId, 'Sharing channel opened', 'Tap to join the sharing session', {
        type: 'sharing_channel:opened',
        channelId: channel.id,
      });

      return reply.status(201).send(channel);
    },
  );

  // POST /api/sharing-channel/close — admin only (manual early close)
  app.post(
    '/close',
    { preHandler: [authenticate, authorize('admin')] },
    async (request, reply) => {
      const channel = await findOpenChannel(request);
      if (!channel) return reply.status(404).send({ message: 'No open sharing channel' });

      await closeChannel(channel.id);

      return reply.send({ message: 'Sharing channel closed' });
    },
  );

  // GET /api/sharing-channel/members — admin only
  app.get(
    '/members',
    { preHandler: [authenticate, authorize('admin')] },
    async (request, reply) => {
      const channel = await findOpenChannel(request);
      if (!channel) return reply.send([]);

      const members = await prisma.sharingChannelMember.findMany({
        where: { sharingChannelId: channel.id },
        include: { user: { select: { id: true, name: true, surname: true, email: true } } },
      });

      return reply.send(members);
    },
  );
}

export async function closeChannel(channelId: string) {
  await pushToChannelMembers(channelId, 'Sharing channel closed', 'The session has ended', {
    type: 'sharing_channel:closed',
    channelId,
  });

  await prisma.sharingChannel.update({
    where: { id: channelId },
    data: { status: 'closed', closedAt: new Date() },
  });

  await prisma.sharingChannelPost.deleteMany({ where: { sharingChannelId: channelId } });
  await prisma.sharingChannelMember.deleteMany({ where: { sharingChannelId: channelId } });
}
