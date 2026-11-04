import admin from 'firebase-admin';
import { env } from './env.js';
import { FirebaseNotConfiguredError } from './firebase-error.js';

// In production a missing or invalid service account key stops the server.
// Elsewhere the server starts anyway, so that it can be developed with
// /api/auth/dev-login: each Firebase call then throws FirebaseNotConfiguredError.
function initFirebase(): admin.app.App | null {
  if (admin.apps.length) return admin.app();
  try {
    const serviceAccount = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON ?? '');
    return admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  } catch (err) {
    if (env.NODE_ENV === 'production') throw err;
    console.warn(`Firebase not configured, Firebase login and push notifications disabled: ${(err as Error).message}`);
    return null;
  }
}

const app = initFirebase();

function requireApp(): admin.app.App {
  if (!app) throw new FirebaseNotConfiguredError();
  return app;
}

export const firebaseAuth = {
  verifyIdToken: async (idToken: string, checkRevoked?: boolean) =>
    requireApp().auth().verifyIdToken(idToken, checkRevoked),
};

export const fcm = {
  sendEachForMulticast: async (message: admin.messaging.MulticastMessage) =>
    requireApp().messaging().sendEachForMulticast(message),
};
