import { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { prisma } from '../config/prisma.js';
import { authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';
import { pushToChannelMembers } from '../services/push.service.js';

// Text only: a message with anything else is refused.
const postBody = z.object({ content: z.string().trim().min(1) }).strict();

const author = { select: { id: true, name: true, surname: true } } as const;

const scheduleBody = z.object({
  dayOfWeek: z.number().int().min(1).max(7),
  startTime: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
  durationHours: z.number().int().positive(),
});

const scheduleFields = { dayOfWeek: true, startTime: true, durationHours: true } as const;

const ROLES_ACROSS_GROUPS = ['admin', 'super_admin'];

// Each group has its own sharing channel. Users act on their group's channel;
// admins manage every group and can pick one with ?groupId=.
function groupIdFor(request: FastifyRequest) {
  const { groupId } = request.query as { groupId?: string };
  if (groupId && ROLES_ACROSS_GROUPS.includes(request.user.role)) return groupId;
  return request.user.groupId;
}

// The user's entry in the channel, also if they left it.
function findMembership(channelId: string, userId: string) {
  return prisma.sharingChannelMember.findUnique({
    where: { sharingChannelId_userId: { sharingChannelId: channelId, userId } },
  });
}

// Who is in the channel now sees the messages from their first entry, or from their
// return if they left and came back.
async function findMemberIn(channelId: string, userId: string) {
  const member = await findMembership(channelId, userId);
  return member && !member.leftAt ? member : null;
}

function postsSeenBy(channelId: string, member: { rejoinedAt: Date | null }) {
  return prisma.sharingChannelPost.findMany({
    where: { sharingChannelId: channelId, ...(member.rejoinedAt && { createdAt: { gte: member.rejoinedAt } }) },
    orderBy: { createdAt: 'asc' },
    include: { author },
  });
}

// A channel left open when its group ended counts as closed until the job closes it.
function findOpenChannel(request: FastifyRequest) {
  const groupId = groupIdFor(request);
  if (!groupId) return null;
  return prisma.sharingChannel.findFirst({
    where: { status: 'open', groupId, group: { OR: [{ endedAt: null }, { endedAt: { gt: new Date() } }] } },
  });
}

export async function sharingChannelRoutes(app: FastifyInstance) {
  // GET /api/sharing-channel/schedule — admin only
  app.get('/schedule', { preHandler: [authenticate, authorize('admin')] }, async (_request, reply) => {
    const schedule = await prisma.sharingChannelSchedule.findUnique({ where: { id: 1 }, select: scheduleFields });
    if (!schedule) return reply.status(404).send({ message: 'Il cerchio non ha ancora una programmazione' });
    return reply.send(schedule);
  });

  // PUT /api/sharing-channel/schedule — admin only
  app.put('/schedule', { preHandler: [authenticate, authorize('admin')] }, async (request, reply) => {
    // Set here rather than by Prisma: the change counts from the next appointment after it.
    const data = { ...scheduleBody.parse(request.body), updatedAt: new Date() };
    const schedule = await prisma.sharingChannelSchedule.upsert({
      where: { id: 1 },
      create: data,
      update: data,
      select: scheduleFields,
    });
    return reply.send(schedule);
  });

  // GET /api/sharing-channel/status
  app.get('/status', { preHandler: authenticate }, async (request, reply) => {
    const channel = await findOpenChannel(request);

    if (!channel) return reply.send({ status: 'closed' });

    // Numbers only, never who (spec, section 9).
    const [member, memberCount, participantCount] = await Promise.all([
      findMemberIn(channel.id, request.user.id),
      // How many people are in the circle now.
      prisma.sharingChannelMember.count({ where: { sharingChannelId: channel.id, leftAt: null } }),
      // Everyone who entered, also if they left.
      prisma.sharingChannelMember.count({ where: { sharingChannelId: channel.id } }),
    ]);

    return reply.send({
      status: 'open',
      channelId: channel.id,
      openedAt: channel.openedAt,
      scheduledClosedAt: channel.scheduledClosedAt,
      joined: !!member,
      memberCount,
      participantCount,
    });
  });

  // POST /api/sharing-channel/join
  app.post('/join', { preHandler: authenticate }, async (request, reply) => {
    const channel = await findOpenChannel(request);
    if (!channel) return reply.status(404).send({ message: 'Il canale di condivisione non è aperto' });

    const existing = await findMembership(channel.id, request.user.id);
    if (existing && !existing.leftAt) return reply.status(409).send({ message: 'Partecipi già alla sessione' });

    // The first entry shows the messages so far; a return only those from then on.
    const member = existing
      ? await prisma.sharingChannelMember.update({
          where: { id: existing.id },
          data: { leftAt: null, rejoinedAt: new Date() },
        })
      : await prisma.sharingChannelMember.create({
          data: { sharingChannelId: channel.id, userId: request.user.id },
        });

    const history = await postsSeenBy(channel.id, member);

    await pushToChannelMembers(
      channel.id,
      'Nuovo partecipante',
      'Qualcuno è entrato nella sessione di condivisione',
      { type: 'sharing_channel:member_joined', channelId: channel.id },
    );

    return reply.send({ joined: true, history });
  });

  // DELETE /api/sharing-channel/leave
  app.delete('/leave', { preHandler: authenticate }, async (request, reply) => {
    const channel = await findOpenChannel(request);
    if (!channel) return reply.status(404).send({ message: 'Il canale di condivisione non è aperto' });

    const member = await findMemberIn(channel.id, request.user.id);
    if (!member) return reply.status(404).send({ message: 'Non partecipi al canale di condivisione' });

    // Kept as having taken part, and recognised if they come back.
    await prisma.sharingChannelMember.update({ where: { id: member.id }, data: { leftAt: new Date() } });

    await pushToChannelMembers(
      channel.id,
      'Un partecipante è uscito',
      'Qualcuno è uscito dalla sessione di condivisione',
      { type: 'sharing_channel:member_left', channelId: channel.id },
    );

    return reply.send({ left: true });
  });

  // GET /api/sharing-channel/posts — joined members only
  app.get('/posts', { preHandler: authenticate }, async (request, reply) => {
    const channel = await findOpenChannel(request);
    if (!channel) return reply.status(404).send({ message: 'Il canale di condivisione non è aperto' });

    const member = await findMemberIn(channel.id, request.user.id);
    if (!member) return reply.status(403).send({ message: 'Prima entra nel canale' });

    return reply.send(await postsSeenBy(channel.id, member));
  });

  // POST /api/sharing-channel/posts — joined members only
  app.post('/posts', { preHandler: authenticate }, async (request, reply) => {
    const { content } = postBody.parse(request.body);

    const channel = await findOpenChannel(request);
    if (!channel) return reply.status(404).send({ message: 'Il canale di condivisione non è aperto' });

    const member = await findMemberIn(channel.id, request.user.id);
    if (!member) return reply.status(403).send({ message: 'Prima entra nel canale' });

    const post = await prisma.sharingChannelPost.create({
      data: { sharingChannelId: channel.id, authorId: request.user.id, content },
      include: { author },
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
        'Post rimosso',
        'Un amministratore ha rimosso un post',
        { type: 'sharing_channel:post_deleted', channelId: post.sharingChannelId },
      );

      return reply.status(204).send();
    },
  );

  // GET /api/sharing-channel/channels — admin only, the open channels of every group
  app.get('/channels', { preHandler: [authenticate, authorize('admin')] }, async (_request, reply) => {
    const channels = await prisma.sharingChannel.findMany({
      where: { status: 'open' },
      orderBy: { openedAt: 'asc' },
      select: {
        id: true,
        openedAt: true,
        scheduledClosedAt: true,
        group: { select: { id: true, startedAt: true } },
        _count: { select: { members: { where: { leftAt: null } }, posts: true } },
      },
    });

    return reply.send(
      channels.map(({ _count, ...channel }) => ({ ...channel, memberCount: _count.members, postCount: _count.posts })),
    );
  });

  // GET /api/sharing-channel/channels/:id — admin only, members and messages without joining
  app.get('/channels/:id', { preHandler: [authenticate, authorize('admin')] }, async (request, reply) => {
    const { id } = request.params as { id: string };

    const channel = await prisma.sharingChannel.findFirst({
      where: { id, status: 'open' },
      select: {
        id: true,
        openedAt: true,
        scheduledClosedAt: true,
        group: { select: { id: true, startedAt: true } },
        members: { where: { leftAt: null }, orderBy: { joinedAt: 'asc' }, select: { joinedAt: true, user: author } },
        posts: { orderBy: { createdAt: 'asc' }, select: { id: true, content: true, createdAt: true, author } },
      },
    });
    if (!channel) return reply.status(404).send({ message: 'Il cerchio non è aperto' });

    return reply.send(channel);
  });

  // GET /api/sharing-channel/members — admin only
  app.get(
    '/members',
    { preHandler: [authenticate, authorize('admin')] },
    async (request, reply) => {
      const channel = await findOpenChannel(request);
      if (!channel) return reply.send([]);

      const members = await prisma.sharingChannelMember.findMany({
        where: { sharingChannelId: channel.id, leftAt: null },
        include: { user: { select: { id: true, name: true, surname: true, email: true } } },
      });

      return reply.send(members);
    },
  );
}
