-- The sharing channel lasts whole hours: an existing duration in minutes is rounded
-- to the nearest hour, and is never shorter than one.

-- AlterTable
ALTER TABLE "sharing_channel_schedule" ADD COLUMN "duration_hours" INTEGER;
UPDATE "sharing_channel_schedule" SET "duration_hours" = GREATEST(1, ROUND("duration_minutes" / 60.0));
ALTER TABLE "sharing_channel_schedule" ALTER COLUMN "duration_hours" SET NOT NULL;
ALTER TABLE "sharing_channel_schedule" DROP COLUMN "duration_minutes";
