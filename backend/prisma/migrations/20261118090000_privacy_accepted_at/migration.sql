-- When the user accepted the privacy policy at registration.

-- AlterTable
ALTER TABLE "users" ADD COLUMN "privacy_accepted_at" TIMESTAMP(3);
