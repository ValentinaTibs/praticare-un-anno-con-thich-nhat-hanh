import cron from 'node-cron';
import { closeExpiredCycles, startDueGroups } from '../services/cycle.service.js';

// Each step runs even if the other failed; failures are logged, and the next run tries again.
async function checkCycles() {
  const steps = [
    { name: 'close expired cycles', run: closeExpiredCycles },
    { name: 'start due groups', run: startDueGroups },
  ];
  for (const step of steps) {
    try {
      await step.run();
    } catch (error) {
      console.error(`Cycle check failed (${step.name}):`, error);
    }
  }
}

export function startRegistrationCycleJob() {
  // At startup too, to catch up on a date reached while the server was off
  void checkCycles();

  // Every minute — close cycles at their closing date, create groups at their start date
  cron.schedule('* * * * *', checkCycles);
}
