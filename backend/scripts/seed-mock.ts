import { PrismaClient } from '@prisma/client';
import { isLocalDatabase, seedMockData } from './mock-data.js';

const prisma = new PrismaClient();

// Fills the local database with fictional users, groups and requests. Never for prova or production.
async function main() {
  if (process.env.NODE_ENV === 'production' || !isLocalDatabase(process.env.DATABASE_URL)) {
    throw new Error('I dati di prova si creano solo su un database locale: controlla DATABASE_URL e NODE_ENV.');
  }
  const { users, bannedEmails, requests, cycle } = await seedMockData(prisma);
  console.log(`Aggiunti: ${users} utenti, ${bannedEmails} email bannate, ${requests} richieste di partecipazione.`);
  console.log(`Ciclo aperto: richieste fino al ${cycle.scheduledClosedAt?.toISOString()}, inizio ${cycle.startsAt.toISOString()}.`);
}

main()
  .catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
