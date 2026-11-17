import {
  issueConfirmationRequests,
  processMissedConfirmations,
} from '../services/confirmation.service.js';
import { scheduleJob } from './schedule.js';

export function startConfirmationCheckJob() {
  // Every day at 08:00 — issue new confirmation requests to users who are overdue
  scheduleJob('0 8 * * *', 'confirmation requests', issueConfirmationRequests);

  // Every hour — mark missed confirmations and suspend users
  scheduleJob('0 * * * *', 'missed confirmations', processMissedConfirmations);
}
