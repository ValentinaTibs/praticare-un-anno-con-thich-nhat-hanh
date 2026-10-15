import cron from 'node-cron';
import {
  issueConfirmationRequests,
  processMissedConfirmations,
} from '../services/confirmation.service.js';

export function startConfirmationCheckJob() {
  // Every day at 08:00 — issue new confirmation requests to users who are overdue
  cron.schedule('0 8 * * *', async () => {
    await issueConfirmationRequests();
  });

  // Every hour — mark missed confirmations and suspend users
  cron.schedule('0 * * * *', async () => {
    await processMissedConfirmations();
  });
}
