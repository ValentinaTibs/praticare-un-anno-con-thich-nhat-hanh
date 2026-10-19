import { firebaseAuth } from '../config/firebase.js';

export class EmailNotVerifiedError extends Error {
  constructor() {
    super('Email not verified');
  }
}

// Returns the email of a valid Firebase idToken, normalized so that the same
// address always maps to the same user regardless of case.
// checkRevoked: also rejects tokens of disabled Firebase users and tokens issued
// before a revocation (e.g. after a password reset).
export async function verifyFirebaseToken(idToken: string): Promise<string> {
  const decoded = await firebaseAuth.verifyIdToken(idToken, true);
  if (!decoded.email) throw new Error('Firebase token has no email');
  if (decoded.email_verified !== true) throw new EmailNotVerifiedError();
  return decoded.email.trim().toLowerCase();
}
