-- CreateTable
CREATE TABLE "participation_requests" (
    "id" TEXT NOT NULL,
    "cycle_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "participation_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "removed_requesters" (
    "cycle_id" TEXT NOT NULL,
    "email" TEXT NOT NULL,

    CONSTRAINT "removed_requesters_pkey" PRIMARY KEY ("cycle_id","email")
);

-- CreateIndex
CREATE INDEX "participation_requests_user_id_idx" ON "participation_requests"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "participation_requests_cycle_id_user_id_key" ON "participation_requests"("cycle_id", "user_id");

-- AddForeignKey
ALTER TABLE "participation_requests" ADD CONSTRAINT "participation_requests_cycle_id_fkey" FOREIGN KEY ("cycle_id") REFERENCES "registration_cycles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "participation_requests" ADD CONSTRAINT "participation_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "removed_requesters" ADD CONSTRAINT "removed_requesters_cycle_id_fkey" FOREIGN KEY ("cycle_id") REFERENCES "registration_cycles"("id") ON DELETE CASCADE ON UPDATE CASCADE;
