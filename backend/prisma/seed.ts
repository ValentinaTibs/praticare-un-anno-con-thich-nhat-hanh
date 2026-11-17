import { PrismaClient } from '@prisma/client';
import { seedSuperAdmin, superAdminFromEnv } from '../scripts/super-admin.js';

const prisma = new PrismaClient();

const messages = {
  created: 'Super Admin creato',
  updated: 'Super Admin aggiornato: l\'email segnaposto è stata sostituita',
  unchanged: 'Super Admin già presente',
} as const;

async function main() {
  const data = superAdminFromEnv(process.env);
  const result = await seedSuperAdmin(prisma, data);

  if (result.outcome === 'other_super_admin') {
    console.log(`C'è già un Super Admin con l'email ${result.email}: lo script non lo modifica.`);
    return;
  }
  console.log(`${messages[result.outcome]}: ${data.email} (${result.id})`);
}

main()
  .catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
