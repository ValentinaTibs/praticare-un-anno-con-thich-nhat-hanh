import { runMainChannelTick } from '../services/main-channel.service.js';
import { scheduleJob } from './schedule.js';

export function startMainChannelJob() {
  // At startup, for the posts missed while the server was off
  runMainChannelTick(new Date()).catch((error) => console.error('Job failed (main channel):', error));
  // Every minute — publish the templates each group has reached
  scheduleJob('* * * * *', 'main channel', () => runMainChannelTick(new Date()));
}
