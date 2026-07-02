import { NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'

// Dynamic route
export const dynamic = 'force-dynamic'

export async function GET(req: Request) {
  // 1. Verify CRON_SECRET header
  const cronSecret = req.headers.get('x-cron-secret')
  const expectedSecret = process.env.CRON_SECRET

  if (!expectedSecret) {
    console.error('CRON_SECRET environment variable is not set')
    return NextResponse.json(
      { error: 'Server misconfiguration' },
      { status: 500 }
    )
  }

  if (cronSecret !== expectedSecret) {
    return NextResponse.json(
      { error: 'Unauthorized' },
      { status: 401 }
    )
  }

  // 2. Aggregate yesterday's FetchEvents into FetchDaily
  // Yesterday = from 00:00:00 to 23:59:59 UTC of previous day
  const today = new Date()
  today.setUTCHours(0, 0, 0, 0)
  const yesterday = new Date(today)
  yesterday.setUTCDate(yesterday.getUTCDate() - 1)

  try {
    // Use raw SQL for aggregation with upsert
    // PostgreSQL syntax for INSERT ... ON CONFLICT DO UPDATE
    const aggregationResult = await prisma.$executeRaw`
      INSERT INTO "FetchDaily" ("id", "appId", "date", "version", "fetchCount")
      SELECT
        gen_random_uuid()::text as id,
        "appId",
        DATE("timestamp") as date,
        COALESCE("version", 'unknown') as version,
        COUNT(*)::integer as "fetchCount"
      FROM "FetchEvent"
      WHERE "timestamp" >= ${yesterday}
        AND "timestamp" < ${today}
      GROUP BY "appId", DATE("timestamp"), COALESCE("version", 'unknown')
      ON CONFLICT ("appId", "date", "version")
      DO UPDATE SET "fetchCount" = "FetchDaily"."fetchCount" + EXCLUDED."fetchCount"
    `

    // 3. Delete old FetchEvents (older than 7 days)
    const sevenDaysAgo = new Date(today)
    sevenDaysAgo.setUTCDate(sevenDaysAgo.getUTCDate() - 7)

    const deleteResult = await prisma.fetchEvent.deleteMany({
      where: {
        timestamp: {
          lt: sevenDaysAgo,
        },
      },
    })

    // 4. Return results
    return NextResponse.json({
      rolledUp: aggregationResult,
      deleted: deleteResult.count,
      period: {
        start: yesterday.toISOString(),
        end: today.toISOString(),
      },
    })
  } catch (error) {
    console.error('Rollup failed:', error)
    return NextResponse.json(
      {
        error: 'Rollup operation failed',
        details: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    )
  }
}
