-- The Main Channel becomes a single sequence of templates, each with a journey day
-- and a time, copied into a group's Main Channel when the group reaches them.
-- The old posts belong to no group, so they can't become copies: each one becomes
-- a draft template on day 1, with its media link appended to the text. Drafts are
-- never published, and the admins decide what to keep.

-- CreateEnum
CREATE TYPE "TemplateStatus" AS ENUM ('draft', 'scheduled');

-- CreateTable
CREATE TABLE "main_channel_templates" (
    "id" TEXT NOT NULL,
    "author_id" TEXT,
    "content" TEXT NOT NULL,
    "journey_day" INTEGER NOT NULL,
    "publish_time" TEXT NOT NULL DEFAULT '08:00',
    "status" "TemplateStatus" NOT NULL DEFAULT 'draft',
    "sequenced_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "main_channel_templates_pkey" PRIMARY KEY ("id")
);

INSERT INTO "main_channel_templates" ("id", "author_id", "content", "journey_day", "created_at", "updated_at")
SELECT "id",
       "author_id",
       CASE WHEN "media_url" IS NULL THEN "content" ELSE "content" || E'\n\n' || "media_url" END,
       1,
       "created_at",
       CURRENT_TIMESTAMP
FROM "main_channel_posts";

DELETE FROM "main_channel_posts";

-- AlterTable
ALTER TABLE "main_channel_posts" DROP COLUMN "is_draft",
DROP COLUMN "media_url",
DROP COLUMN "scheduled_at",
ADD COLUMN     "group_id" TEXT NOT NULL,
ADD COLUMN     "template_id" TEXT,
ALTER COLUMN "published_at" SET NOT NULL;

-- CreateTable
CREATE TABLE "main_channel_publications" (
    "group_id" TEXT NOT NULL,
    "template_id" TEXT NOT NULL,
    "published_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "main_channel_publications_pkey" PRIMARY KEY ("group_id","template_id")
);

-- CreateIndex
CREATE INDEX "main_channel_templates_status_journey_day_idx" ON "main_channel_templates"("status", "journey_day");

-- CreateIndex
CREATE INDEX "main_channel_publications_template_id_idx" ON "main_channel_publications"("template_id");

-- CreateIndex
CREATE INDEX "main_channel_posts_group_id_published_at_idx" ON "main_channel_posts"("group_id", "published_at");

-- CreateIndex
CREATE INDEX "main_channel_posts_template_id_idx" ON "main_channel_posts"("template_id");

-- AddForeignKey
ALTER TABLE "main_channel_templates" ADD CONSTRAINT "main_channel_templates_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "main_channel_publications" ADD CONSTRAINT "main_channel_publications_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "groups"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "main_channel_publications" ADD CONSTRAINT "main_channel_publications_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "main_channel_templates"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "main_channel_posts" ADD CONSTRAINT "main_channel_posts_group_id_fkey" FOREIGN KEY ("group_id") REFERENCES "groups"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "main_channel_posts" ADD CONSTRAINT "main_channel_posts_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "main_channel_templates"("id") ON DELETE SET NULL ON UPDATE CASCADE;
