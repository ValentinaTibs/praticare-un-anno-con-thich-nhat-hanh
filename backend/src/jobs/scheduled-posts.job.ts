import cron from 'node-cron';
import { prisma } from '../config/prisma.js';
import { pushToAll } from '../services/push.service.js';

export function startScheduledPostsJob() {
  cron.schedule('* * * * *', async () => {
    const due = await prisma.mainChannelPost.findMany({
      where: {
        scheduledAt: { lte: new Date() },
        publishedAt: null,
        isDraft: false,
      },
    });

    for (const post of due) {
      await prisma.mainChannelPost.update({
        where: { id: post.id },
        data: { publishedAt: new Date() },
      });

      await pushToAll('New post', post.content.slice(0, 100), { type: 'main_channel:new_post' });
    }
  });
}
