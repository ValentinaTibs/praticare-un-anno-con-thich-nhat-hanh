-- The weekly appointment of the sharing channel: a single row, shared by every group.

-- CreateTable
CREATE TABLE "sharing_channel_schedule" (
    "id" INTEGER NOT NULL DEFAULT 1,
    "day_of_week" INTEGER NOT NULL,
    "start_time" TEXT NOT NULL,
    "duration_minutes" INTEGER NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "sharing_channel_schedule_pkey" PRIMARY KEY ("id")
);

-- When the closing-soon warning went out, so it goes out once.
-- AlterTable
ALTER TABLE "sharing_channel" ADD COLUMN "closing_warning_at" TIMESTAMP(3);

-- A group's channel opens once per appointment.
-- CreateIndex
CREATE UNIQUE INDEX "sharing_channel_group_id_opened_at_key" ON "sharing_channel"("group_id", "opened_at");
