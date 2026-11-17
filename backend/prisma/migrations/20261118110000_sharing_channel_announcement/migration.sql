-- The opening of a sharing channel is announced by a post in the group's Main Channel,
-- linked to the channel. Leaving a channel keeps the member, with the time they left
-- and, if they come back, the time they rejoined. Sharing channel messages are text
-- only: a media link still in an open channel moves into the text.

-- AlterTable
ALTER TABLE "main_channel_posts" ADD COLUMN     "sharing_channel_id" TEXT;

-- AlterTable
ALTER TABLE "sharing_channel_members" ADD COLUMN     "left_at" TIMESTAMP(3),
ADD COLUMN     "rejoined_at" TIMESTAMP(3);

-- AlterTable
UPDATE "sharing_channel_posts" SET "content" = "content" || E'\n\n' || "media_url" WHERE "media_url" IS NOT NULL;
ALTER TABLE "sharing_channel_posts" DROP COLUMN "media_url";

-- CreateIndex
CREATE UNIQUE INDEX "main_channel_posts_sharing_channel_id_key" ON "main_channel_posts"("sharing_channel_id");

-- AddForeignKey
ALTER TABLE "main_channel_posts" ADD CONSTRAINT "main_channel_posts_sharing_channel_id_fkey" FOREIGN KEY ("sharing_channel_id") REFERENCES "sharing_channel"("id") ON DELETE SET NULL ON UPDATE CASCADE;
