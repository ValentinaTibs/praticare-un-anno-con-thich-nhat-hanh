-- AlterTable
ALTER TABLE "registration_cycles"
ADD COLUMN "starts_at" TIMESTAMP(3),
ADD COLUMN "duration_days" INTEGER NOT NULL DEFAULT 365;

-- Existing cycles already have a group: their journey began when the group did
UPDATE "registration_cycles" c
SET "starts_at" = g."started_at"
FROM "groups" g
WHERE g."cycle_id" = c."id";

UPDATE "registration_cycles"
SET "starts_at" = COALESCE("opened_at", "closed_at", CURRENT_TIMESTAMP)
WHERE "starts_at" IS NULL;

-- Their journey has started, so they can no longer take requests. Existing
-- groups and their members stay as they are.
UPDATE "registration_cycles"
SET "status" = 'closed', "closed_at" = CURRENT_TIMESTAMP
WHERE "status" = 'open';

-- AlterTable
ALTER TABLE "registration_cycles" ALTER COLUMN "starts_at" SET NOT NULL;

-- Only one cycle can be open at a time, even under concurrent requests.
-- Partial indexes cannot be declared in schema.prisma.
CREATE UNIQUE INDEX "registration_cycles_single_open" ON "registration_cycles" ("status") WHERE "status" = 'open';
