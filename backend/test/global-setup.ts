import EmbeddedPostgres from 'embedded-postgres';
import { execSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { TEST_DB_NAME, TEST_DB_PORT, testEnv } from './test-env.js';

// Starts a real, throwaway Postgres for the whole test run and applies the
// committed migrations, so tests exercise the same schema as production.
export default async function setup() {
  const databaseDir = mkdtempSync(join(tmpdir(), 'community-app-pg-'));
  const pg = new EmbeddedPostgres({
    databaseDir,
    user: 'postgres',
    password: 'postgres',
    port: TEST_DB_PORT,
    persistent: false,
    onLog: () => {},
  });

  await pg.initialise();
  await pg.start();
  await pg.createDatabase(TEST_DB_NAME);

  execSync('npx prisma migrate deploy', {
    env: { ...process.env, DATABASE_URL: testEnv.DATABASE_URL },
    stdio: 'ignore',
  });

  return async () => {
    await pg.stop();
    rmSync(databaseDir, { recursive: true, force: true });
  };
}
