import cron from 'node-cron';
import { prisma } from '../config/prisma.js';
import { env } from '../config/env.js';
import { pushToAll } from '../services/push.service.js';
import { closeChannel } from '../routes/sharing-channel.js';

export function startSharingChannelJob() {
  cron.schedule('* * * * *', async () => {
    const channel = await prisma.sharingChannel.findFirst({
      where: { status: 'open', scheduledClosedAt: { not: null } },
    });

    if (!channel || !channel.scheduledClosedAt) return;

    const now = new Date();
    const closeTime = channel.scheduledClosedAt;
    const warnTime = new Date(closeTime.getTime() - env.SHARING_CHANNEL_WARN_MINUTES * 60 * 1000);

    if (now >= closeTime) {
      await closeChannel(channel.id);
      return;
    }

    const warnWindowEnd = new Date(warnTime.getTime() + 60 * 1000);
    if (now >= warnTime && now < warnWindowEnd) {
      await pushToAll(
        'Sharing channel closing soon',
        `The sharing channel closes in ${env.SHARING_CHANNEL_WARN_MINUTES} minutes`,
        { type: 'sharing_channel:closing_soon', channelId: channel.id },
      );
    }
  });
}
