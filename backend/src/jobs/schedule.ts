import cron from 'node-cron';

// node-cron swallows the errors of async tasks without logging them: log them here,
// and the next run tries again.
export function scheduleJob(expression: string, name: string, task: () => Promise<void>) {
  cron.schedule(expression, () => {
    task().catch((error) => console.error(`Job failed (${name}):`, error));
  });
}
