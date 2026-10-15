import { PrismaClient, Role, UserStatus } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  const superAdmin = await prisma.user.upsert({
    where: { phoneNumber: '+10000000000' },
    update: {},
    create: {
      name: 'Super',
      surname: 'Admin',
      phoneNumber: '+10000000000',
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
