-- Removing a user deletes their sharing channel messages too, instead of
-- failing while any of them exists.

-- DropForeignKey
ALTER TABLE "sharing_channel_posts" DROP CONSTRAINT "sharing_channel_posts_author_id_fkey";

-- AddForeignKey
ALTER TABLE "sharing_channel_posts" ADD CONSTRAINT "sharing_channel_posts_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
