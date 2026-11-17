import { runSharingChannelTick } from '../services/sharing-channel.service.js';
import { scheduleJob } from './schedule.js';

export function startSharingChannelJob() {
  // Every minute — open, warn and close the channels following the weekly schedule
  scheduleJob('* * * * *', 'sharing channel', () => runSharingChannelTick(new Date()));
}
