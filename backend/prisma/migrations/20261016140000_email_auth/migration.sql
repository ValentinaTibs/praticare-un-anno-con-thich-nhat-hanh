-- Login moves from phone (SMS) to email + password, both through Firebase.
-- The phone number is dropped entirely and the email becomes the identity.

-- DropForeignKey
ALTER TABLE "otp_codes" DROP CONSTRAINT "otp_codes_user_id_fkey";

-- DropTable
DROP TABLE "otp_codes";

-- DropIndex
DROP INDEX "users_phone_number_key";

-- AlterTable
ALTER TABLE "users" DROP COLUMN "phone_number",
ADD COLUMN     "email" TEXT;

-- Existing users (e.g. the seeded super admin) get a unique placeholder email
UPDATE "users" SET "email" = 'user-' || "id" || '@invalid.local' WHERE "email" IS NULL;

ALTER TABLE "users" ALTER COLUMN "email" SET NOT NULL;

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- Phone bans cannot carry over to emails
-- DropTable
DROP TABLE "banned_phones";

-- CreateTable
CREATE TABLE "banned_emails" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "permanent" BOOLEAN NOT NULL DEFAULT false,
    "banned_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "banned_emails_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "banned_emails_email_key" ON "banned_emails"("email");
