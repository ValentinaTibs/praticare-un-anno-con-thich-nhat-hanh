import cron from 'node-cron';
import { runSharingChannelTick } from '../services/sharing-channel.service.js';

export function startSharingChannelJob() {
  // Every minute — open, warn and close the channels following the weekly schedule
  cron.schedule('* * * * *', async () => {
    await runSharingChannelTick(new Date());
  });
}
