-- CreateTable
CREATE TABLE "groups" (
    "id" TEXT NOT NULL,
    "cycle_id" TEXT NOT NULL,
    "started_at" TIMESTAMP(3) NOT NULL,
    "ended_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "groups_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "groups_cycle_id_key" ON "groups"("cycle_id");

-- AddForeignKey
ALTER TABLE "groups" ADD CONSTRAINT "groups_cycle_id_fkey" FOREIGN KEY ("cycle_id") REFERENCES "registration_cycles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- One group for every cycle opened so far
INSERT INTO "groups" ("id", "cycle_id", "started_at")
SELECT gen_random_uuid()::text, "id", COALESCE("opened_at", CURRENT_TIMESTAMP)
FROM "registration_cycles";

-- AlterTable
ALTER TABLE "users" ADD COLUMN     "group_id" TEXT;

-- AddForeignKey
ALTER TABLE "users" ADD CONSTRAINT "users_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "groups"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Existing users join the group of the cycle they registered in
UPDATE "users" u
SET "group_id" = g."id"
FROM "registration_cycles" c
JOIN "groups" g ON g."cycle_id" = c."id"
WHERE c."opened_at" IS NOT NULL
  AND u."created_at" >= c."opened_at"
  AND u."created_at" <= COALESCE(c."closed_at", CURRENT_TIMESTAMP);

-- A sharing channel now belongs to a group. Existing sessions have none and
-- their posts are temporary anyway, so they are dropped.
DELETE FROM "sharing_channel";

-- AlterTable
ALTER TABLE "sharing_channel" ADD COLUMN     "group_id" TEXT NOT NULL;

-- AddForeignKey
ALTER TABLE "sharing_channel" ADD CONSTRAINT "sharing_channel_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "groups"("id") ON DELETE CASCADE ON UPDATE CASCADE;
