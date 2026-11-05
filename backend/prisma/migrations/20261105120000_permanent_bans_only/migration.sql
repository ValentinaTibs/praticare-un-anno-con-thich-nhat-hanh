-- Registration is always open: removed users are no longer blocked until the
-- next cycle, so the only blocked emails left are permanent bans.
DELETE FROM "banned_emails" WHERE "permanent" = false;

-- AlterTable
ALTER TABLE "banned_emails" DROP COLUMN "permanent";
