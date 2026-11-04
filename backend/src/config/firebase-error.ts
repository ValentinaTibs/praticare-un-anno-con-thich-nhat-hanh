// Thrown by every Firebase call when the server started without a valid service
// account key, which is allowed outside production (see firebase.ts).
export class FirebaseNotConfiguredError extends Error {
  constructor() {
    super('Firebase non configurato: manca una chiave di servizio valida in FIREBASE_SERVICE_ACCOUNT_JSON');
  }
}
