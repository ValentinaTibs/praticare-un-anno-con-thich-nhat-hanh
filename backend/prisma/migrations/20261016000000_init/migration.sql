-- CreateEnum
CREATE TYPE "Role" AS ENUM ('super_admin', 'admin', 'user');

-- CreateEnum
CREATE TYPE "UserStatus" AS ENUM ('active', 'suspended', 'banned');

-- CreateEnum
CREATE TYPE "SharingChannelStatus" AS ENUM ('open', 'closed');

-- CreateEnum
CREATE TYPE "ConfirmationStatus" AS ENUM ('pending', 'confirmed', 'missed');

-- CreateEnum
CREATE TYPE "CycleStatus" AS ENUM ('open', 'closed');

-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "surname" TEXT NOT NULL,
    "phone_number" TEXT NOT NULL,
    "motivation" TEXT NOT NULL,
    "role" "Role" NOT NULL DEFAULT 'user',
    "status" "UserStatus" NOT NULL DEFAULT 'active',
    "reviewed_by_admin" BOOLEAN NOT NULL DEFAULT false,
    "last_confirmed_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_devices" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "fcm_token" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "user_devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "otp_codes" (
    "id" TEXT NOT NULL,
    "user_id" TEXT,
    "phone" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "used" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "otp_codes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "main_channel_posts" (
    "id" TEXT NOT NULL,
    "author_id" TEXT,
    "content" TEXT NOT NULL,
    "media_url" TEXT,
    "scheduled_at" TIMESTAMP(3),
    "published_at" TIMESTAMP(3),
    "is_draft" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "main_channel_posts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sharing_channel" (
    "id" TEXT NOT NULL,
    "status" "SharingChannelStatus" NOT NULL DEFAULT 'closed',
    "opened_by" TEXT,
    "opened_at" TIMESTAMP(3),
    "scheduled_closed_at" TIMESTAMP(3),
    "closed_at" TIMESTAMP(3),

    CONSTRAINT "sharing_channel_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sharing_channel_members" (
    "id" TEXT NOT NULL,
    "sharing_channel_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "joined_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sharing_channel_members_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sharing_channel_posts" (
    "id" TEXT NOT NULL,
    "sharing_channel_id" TEXT NOT NULL,
    "author_id" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "media_url" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sharing_channel_posts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "confirmation_requests" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "due_at" TIMESTAMP(3) NOT NULL,
    "confirmed_at" TIMESTAMP(3),
    "status" "ConfirmationStatus" NOT NULL DEFAULT 'pending',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "confirmation_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "registration_cycles" (
    "id" TEXT NOT NULL,
    "status" "CycleStatus" NOT NULL DEFAULT 'closed',
    "opened_by" TEXT,
    "opened_at" TIMESTAMP(3),
    "closed_at" TIMESTAMP(3),

    CONSTRAINT "registration_cycles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "banned_phones" (
    "id" TEXT NOT NULL,
    "phone_number" TEXT NOT NULL,
    "permanent" BOOLEAN NOT NULL DEFAULT false,
    "banned_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "banned_phones_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_phone_number_key" ON "users"("phone_number");

-- CreateIndex
CREATE UNIQUE INDEX "user_devices_fcm_token_key" ON "user_devices"("fcm_token");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_token_key" ON "refresh_tokens"("token");

-- CreateIndex
CREATE UNIQUE INDEX "sharing_channel_members_sharing_channel_id_user_id_key" ON "sharing_channel_members"("sharing_channel_id", "user_id");

-- CreateIndex
CREATE UNIQUE INDEX "banned_phones_phone_number_key" ON "banned_phones"("phone_number");

-- AddForeignKey
ALTER TABLE "user_devices" ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "otp_codes" ADD CONSTRAINT "otp_codes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "main_channel_posts" ADD CONSTRAINT "main_channel_posts_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sharing_channel" ADD CONSTRAINT "sharing_channel_opened_by_fkey" FOREIGN KEY ("opened_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sharing_channel_members" ADD CONSTRAINT "sharing_channel_members_sharing_channel_id_fkey" FOREIGN KEY ("sharing_channel_id") REFERENCES "sharing_channel"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sharing_channel_members" ADD CONSTRAINT "sharing_channel_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sharing_channel_posts" ADD CONSTRAINT "sharing_channel_posts_sharing_channel_id_fkey" FOREIGN KEY ("sharing_channel_id") REFERENCES "sharing_channel"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sharing_channel_posts" ADD CONSTRAINT "sharing_channel_posts_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "confirmation_requests" ADD CONSTRAINT "confirmation_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "registration_cycles" ADD CONSTRAINT "registration_cycles_opened_by_fkey" FOREIGN KEY ("opened_by") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

