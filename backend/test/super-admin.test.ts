import { describe, it, expect } from 'vitest';
import { prisma } from '../src/config/prisma.js';
import { seedSuperAdmin, superAdminFromEnv } from '../scripts/super-admin.js';
import { givenAdmin, givenUser } from './helpers.js';

const data = { email: 'referente@example.org', name: 'Maria', surname: 'Rossi' };

const env = {
  SUPER_ADMIN_EMAIL: ' Referente@Example.org ',
  SUPER_ADMIN_NAME: ' Maria ',
  SUPER_ADMIN_SURNAME: 'Rossi',
};

describe('Super Admin dalle variabili d\'ambiente', () => {
  it('legge email, nome e cognome, con l\'email in minuscolo', () => {
    expect(superAdminFromEnv(env)).toEqual(data);
  });

  it('senza una variabile si ferma e dice quale manca', () => {
    expect(() => superAdminFromEnv({ ...env, SUPER_ADMIN_EMAIL: undefined })).toThrow(/manca SUPER_ADMIN_EMAIL/);
    expect(() => superAdminFromEnv({ ...env, SUPER_ADMIN_SURNAME: '  ' })).toThrow(/SUPER_ADMIN_SURNAME è vuota/);
  });

  it('rifiuta un\'email non valida', () => {
    expect(() => superAdminFromEnv({ ...env, SUPER_ADMIN_EMAIL: 'referente' })).toThrow(/non è un indirizzo email valido/);
  });
});

describe('Creazione del Super Admin', () => {
  it('su un database vuoto crea il Super Admin con i dati indicati', async () => {
    const result = await seedSuperAdmin(prisma, data);

    expect(result.outcome).toBe('created');
    expect(await prisma.user.findMany({ where: { role: 'super_admin' } })).toMatchObject([
      { ...data, status: 'active', reviewedByAdmin: true, groupId: null },
    ]);
  });

  it('una seconda esecuzione non cambia niente', async () => {
    const { id } = await seedSuperAdmin(prisma, data);

    expect(await seedSuperAdmin(prisma, data)).toEqual({ outcome: 'unchanged', id });
    expect(await prisma.user.count()).toBe(1);
  });

  it.each(['superadmin@example.com', 'user-123@invalid.local'])(
    'un Super Admin con l\'email segnaposto %s prende i dati nuovi',
    async (placeholder) => {
      const existing = await givenAdmin({ email: placeholder, role: 'super_admin' });

      expect(await seedSuperAdmin(prisma, data)).toEqual({ outcome: 'updated', id: existing.id });
      expect(await prisma.user.findUniqueOrThrow({ where: { id: existing.id } })).toMatchObject(data);
      expect(await prisma.user.count({ where: { role: 'super_admin' } })).toBe(1);
    },
  );

  it('non tocca un Super Admin con un\'email vera e non ne crea un secondo', async () => {
    const existing = await givenAdmin({ email: 'altro@example.org', role: 'super_admin' });

    expect(await seedSuperAdmin(prisma, data)).toEqual({
      outcome: 'other_super_admin',
      id: existing.id,
      email: 'altro@example.org',
    });
    expect(await prisma.user.findMany({ where: { role: 'super_admin' } })).toMatchObject([{ email: 'altro@example.org' }]);
  });

  it('si ferma se l\'email è già di un altro utente, senza promuoverlo', async () => {
    const user = await givenUser({ email: data.email });

    await expect(seedSuperAdmin(prisma, data)).rejects.toThrow(/appartiene già a un altro utente/);
    expect(await prisma.user.findUniqueOrThrow({ where: { id: user.id } })).toMatchObject({ role: 'user' });
    expect(await prisma.user.count({ where: { role: 'super_admin' } })).toBe(0);
  });
});
