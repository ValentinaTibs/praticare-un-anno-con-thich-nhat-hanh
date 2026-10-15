import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().default(3000),
  HOST: z.string().default('0.0.0.0'),

  DATABASE_URL: z.string().url(),

  JWT_SECRET: z.string().min(32),
  JWT_ACCESS_EXPIRES_IN: z.string().default('15m'),
  JWT_REFRESH_EXPIRES_IN: z.string().default('30d'),

  FIREBASE_SERVICE_ACCOUNT_JSON: z.string(),

  CONFIRMATION_INTERVAL_DAYS: z.coerce.number().default(30),
  CONFIRMATION_GRACE_DAYS: z.coerce.number().default(3),

  CORS_ORIGIN: z.string().default('*'),

  ADMIN_CONTACT_EMAIL: z.string().email(),

  SHARING_CHANNEL_WARN_MINUTES: z.coerce.number().default(15),
});

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  console.error('Invalid environment variables:');
  console.error(parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = parsed.data;
