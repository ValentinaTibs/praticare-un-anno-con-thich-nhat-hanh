import { describe, it, expect, vi } from 'vitest';
import { FirebaseNotConfiguredError } from '../src/config/firebase-error.js';
import { fcm } from '../src/config/firebase.js';
import { prisma } from '../src/config/prisma.js';
import { pushToUser } from '../src/services/push.service.js';
import { createTestApp, givenUser } from './helpers.js';

describe('server senza chiave Firebase', () => {
  // The test environment has no real service account key (FIREBASE_SERVICE_ACCOUNT_JSON={}).
  it('il modulo Firebase si carica lo stesso e le sue funzioni segnalano che manca la chiave', async () => {
    const real = await vi.importActual<typeof import('../src/config/firebase.js')>('../src/config/firebase.js');

    await expect(real.firebaseAuth.verifyIdToken('qualsiasi-token')).rejects.toBeInstanceOf(FirebaseNotConfiguredError);
    await expect(real.fcm.sendEachForMulticast({ tokens: ['t'] })).rejects.toBeInstanceOf(FirebaseNotConfiguredError);
  });

  it('l\'accesso con Firebase risponde 503 con un messaggio chiaro', async () => {
    const app = await createTestApp();

    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/verify-firebase',
      payload: { idToken: 'firebase-not-configured' },
    });

    expect(res.statusCode).toBe(503);
    expect(res.json()).toMatchObject({ code: 'firebase_not_configured' });
  });

  it('le notifiche push vengono saltate invece di far fallire l\'operazione', async () => {
    const user = await givenUser();
    await prisma.userDevice.create({ data: { userId: user.id, fcmToken: 'device-token' } });
    vi.mocked(fcm.sendEachForMulticast).mockRejectedValueOnce(new FirebaseNotConfiguredError());

    await expect(pushToUser(user.id, 'Titolo', 'Testo')).resolves.toBeUndefined();
  });
});
