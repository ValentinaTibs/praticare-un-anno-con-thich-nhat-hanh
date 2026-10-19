import { PrismaClient, Role, UserStatus } from '@prisma/client';

const prisma = new PrismaClient();

// Placeholder: a verified Firebase account with this email is needed to log in.
const SUPER_ADMIN_EMAIL = 'superadmin@example.com';

async function main() {
  // There is only one Super Admin. A database migrated from phone login already has
  // one, with the placeholder email 'user-<id>@invalid.local': give it the seed email
  // instead of creating a second Super Admin.
  const existing = await prisma.user.findFirst({ where: { role: Role.super_admin } });
  if (existing) {
    if (existing.email.endsWith('@invalid.local')) {
      await prisma.user.update({ where: { id: existing.id }, data: { email: SUPER_ADMIN_EMAIL } });
    }
    console.log('Super admin already present:', existing.id);
    return;
  }

  const superAdmin = await prisma.user.create({
    data: {
      name: 'Super',
      surname: 'Admin',
      email: SUPER_ADMIN_EMAIL,
      motivation: 'System seed',
      role: Role.super_admin,
      status: UserStatus.active,
      reviewedByAdmin: true,
      lastConfirmedAt: new Date(),
    },
  });

  console.log('Seeded super admin:', superAdmin.id);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
