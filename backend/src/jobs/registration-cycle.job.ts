import cron from 'node-cron';
import { closeExpiredCycles, startDueGroups } from '../services/cycle.service.js';

async function checkCycles() {
  await closeExpiredCycles();
  await startDueGroups();
}

export function startRegistrationCycleJob() {
  // At startup too, to catch up on a date reached while the server was off
  checkCycles().catch((error) => console.error('Controllo dei cicli non riuscito', error));

  // Every minute — close cycles at their closing date, create groups at their start date
  cron.schedule('* * * * *', async () => {
    await checkCycles();
  });
}
