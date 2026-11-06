import cron from 'node-cron';
import { closeExpiredCycles, startDueGroups } from '../services/cycle.service.js';

async function checkCycles() {
  await closeExpiredCycles();
  await startDueGroups();
}

export function startRegistrationCycleJob() {
  // Every minute — close cycles at their closing date, create groups at their start date
  cron.schedule('* * * * *', async () => {
    await checkCycles();
  });
}
