import EmbeddedPostgres from 'embedded-postgres';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

// Local development database, no Docker needed: a real Postgres whose data
// survives restarts in backend/.dev-db, at the DATABASE_URL of .env.example.
// Runs in the foreground until Ctrl+C.
const DB_NAME = 'community_app';
const PORT = 5432;
const databaseDir = join(__dirname, '..', '.dev-db');

async function main() {
  const pg = new EmbeddedPostgres({
    databaseDir,
    user: 'postgres',
    password: 'postgres',
    port: PORT,
    persistent: true,
    onLog: () => {},
  });

  const firstRun = !existsSync(databaseDir);
  if (firstRun) await pg.initialise();
  await pg.start();
  if (firstRun) await pg.createDatabase(DB_NAME);

  console.log(`Postgres di sviluppo attivo su postgresql://postgres:postgres@localhost:${PORT}/${DB_NAME}`);
  console.log('Premi Ctrl+C per fermarlo.');

  const stop = async () => {
    await pg.stop();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
