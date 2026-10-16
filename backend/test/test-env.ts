// Environment shared by the vitest config (applied to test workers) and the
// global setup (which starts Postgres on this port and migrates the database).
export const TEST_DB_PORT = 54329;
export const TEST_DB_NAME = 'community_app_test';

export const testEnv = {
  NODE_ENV: 'test',
  DATABASE_URL: `postgresql://postgres:postgres@localhost:${TEST_DB_PORT}/${TEST_DB_NAME}`,
  JWT_SECRET: 'test_secret_that_is_at_least_32_characters_long',
  FIREBASE_SERVICE_ACCOUNT_JSON: '{}',
  ADMIN_CONTACT_EMAIL: 'admin@example.com',
};
