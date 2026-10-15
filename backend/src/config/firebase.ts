import admin from 'firebase-admin';
import { env } from './env.js';

const serviceAccount = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

export const fcm = admin.messaging();
export const firebaseAuth = admin.auth();
