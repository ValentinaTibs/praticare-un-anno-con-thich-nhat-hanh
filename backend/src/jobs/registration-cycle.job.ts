import cron from 'node-cron';
import { closeExpiredCycles } from '../services/cycle.service.js';

export function startRegistrationCycleJob() {
  // Every minute — close cycles that reached their closing date
  cron.schedule('* * * * *', async () => {
    await closeExpiredCycles();
  });
}
