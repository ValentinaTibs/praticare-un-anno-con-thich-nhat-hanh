import { PrismaClient, Role, UserStatus } from '@prisma/client';
import { z } from 'zod';

const required = (name: string) => z.string({ required_error: `manca ${name}` }).trim().min(1, `${name} è vuota`);

const superAdminEnv = z.object({
  SUPER_ADMIN_EMAIL: required('SUPER_ADMIN_EMAIL')
    .email('SUPER_ADMIN_EMAIL non è un indirizzo email valido')
    .transform((email) => email.toLowerCase()),
  SUPER_ADMIN_NAME: required('SUPER_ADMIN_NAME'),
  SUPER_ADMIN_SURNAME: required('SUPER_ADMIN_SURNAME'),
});

export type SuperAdminData = { email: string; name: string; surname: string };

// Reads the Super Admin from the environment. Nobody can verify a placeholder email,
// so there is no default: a missing variable stops the script.
export function superAdminFromEnv(env: Record<string, string | undefined>): SuperAdminData {
  const parsed = superAdminEnv.safeParse(env);
  if (!parsed.success) {
    const problems = parsed.error.issues.map((issue) => issue.message).join(', ');
    throw new Error(`Dati del Super Admin non validi: ${problems}. Impostali nel file .env.`);
  }
  const { SUPER_ADMIN_EMAIL: email, SUPER_ADMIN_NAME: name, SUPER_ADMIN_SURNAME: surname } = parsed.data;
  return { email, name, surname };
}

// Emails nobody can log in with: the old seed's and the one given by the move from phone login.
const isPlaceholderEmail = (email: string) =>
  email === 'superadmin@example.com' || email.endsWith('@invalid.local');

export type SeedResult =
  | { outcome: 'created' | 'updated' | 'unchanged'; id: string }
  | { outcome: 'other_super_admin'; id: string; email: string };

// There is only one Super Admin: an existing one with a placeholder email takes the new
// data, one with a real email is left as it is.
export async function seedSuperAdmin(prisma: PrismaClient, data: SuperAdminData): Promise<SeedResult> {
  const existing = await prisma.user.findFirst({ where: { role: Role.super_admin } });

  if (existing?.email === data.email) return { outcome: 'unchanged', id: existing.id };
  if (existing && !isPlaceholderEmail(existing.email)) {
    return { outcome: 'other_super_admin', id: existing.id, email: existing.email };
  }

  const owner = await prisma.user.findUnique({ where: { email: data.email }, select: { id: true } });
  if (owner) {
    throw new Error(`L'email ${data.email} appartiene già a un altro utente: scegline un'altra per il Super Admin.`);
  }

  if (existing) {
    await prisma.user.update({ where: { id: existing.id }, data });
    return { outcome: 'updated', id: existing.id };
  }

  const created = await prisma.user.create({
    data: {
      ...data,
      motivation: 'System seed',
      role: Role.super_admin,
      status: UserStatus.active,
      reviewedByAdmin: true,
      lastConfirmedAt: new Date(),
    },
  });
  return { outcome: 'created', id: created.id };
}
