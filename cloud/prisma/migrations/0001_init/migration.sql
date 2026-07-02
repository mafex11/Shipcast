-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "githubId" INTEGER NOT NULL,
    "githubLogin" TEXT NOT NULL,
    "email" TEXT,
    "apiToken" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "App" (
    "id" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "App_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Release" (
    "id" TEXT NOT NULL,
    "appId" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "artifactUrl" TEXT NOT NULL,
    "sha256" TEXT NOT NULL,
    "edSignature" TEXT NOT NULL,
    "length" INTEGER NOT NULL,
    "minSystemVersion" TEXT,
    "releaseNotesHtml" TEXT,
    "channel" TEXT NOT NULL DEFAULT 'stable',
    "publishedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Release_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FetchEvent" (
    "id" TEXT NOT NULL,
    "appId" TEXT NOT NULL,
    "version" TEXT,
    "timestamp" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "uaCoarse" TEXT,

    CONSTRAINT "FetchEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FetchDaily" (
    "id" TEXT NOT NULL,
    "appId" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "version" TEXT NOT NULL,
    "fetchCount" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "FetchDaily_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_githubId_key" ON "User"("githubId");

-- CreateIndex
CREATE UNIQUE INDEX "User_apiToken_key" ON "User"("apiToken");

-- CreateIndex
CREATE UNIQUE INDEX "App_userId_slug_key" ON "App"("userId", "slug");

-- CreateIndex
CREATE INDEX "Release_appId_publishedAt_idx" ON "Release"("appId", "publishedAt");

-- CreateIndex
CREATE UNIQUE INDEX "Release_appId_version_channel_key" ON "Release"("appId", "version", "channel");

-- CreateIndex
CREATE INDEX "FetchEvent_appId_timestamp_idx" ON "FetchEvent"("appId", "timestamp");

-- CreateIndex
CREATE INDEX "FetchDaily_appId_date_idx" ON "FetchDaily"("appId", "date");

-- CreateIndex
CREATE UNIQUE INDEX "FetchDaily_appId_date_version_key" ON "FetchDaily"("appId", "date", "version");

-- AddForeignKey
ALTER TABLE "App" ADD CONSTRAINT "App_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Release" ADD CONSTRAINT "Release_appId_fkey" FOREIGN KEY ("appId") REFERENCES "App"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FetchEvent" ADD CONSTRAINT "FetchEvent_appId_fkey" FOREIGN KEY ("appId") REFERENCES "App"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FetchDaily" ADD CONSTRAINT "FetchDaily_appId_fkey" FOREIGN KEY ("appId") REFERENCES "App"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

