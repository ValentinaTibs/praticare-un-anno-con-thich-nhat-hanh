import { buildApp } from './app.js';
import { env } from './config/env.js';
import { prisma } from './config/prisma.js';
import { startScheduledPostsJob } from './jobs/scheduled-posts.job.js';
import { startConfirmationCheckJob } from './jobs/confirmation-check.job.js';
import { startSharingChannelJob } from './jobs/sharing-channel.job.js';
import { startRegistrationCycleJob } from './jobs/registration-cycle.job.js';

async function main() {
  const app = await buildApp();

  startScheduledPostsJob();
  startConfirmationCheckJob();
  startSharingChannelJob();
  startRegistrationCycleJob();

  await app.listen({ port: env.PORT, host: env.HOST });
  app.log.info(`Server running on http://${env.HOST}:${env.PORT}`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
