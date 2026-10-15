import { firebaseAuth } from '../config/firebase.js';

export async function verifyFirebaseToken(idToken: string): Promise<string> {
  const decoded = await firebaseAuth.verifyIdToken(idToken);
  if (!decoded.phone_number) throw new Error('Firebase token has no phone number');
  return decoded.phone_number;
}
