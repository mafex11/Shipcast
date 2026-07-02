import { NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { generateAppcastXML } from '@/lib/appcast'

// Edge cache for 5 minutes
export const revalidate = 300
// Dynamic route - don't attempt static generation at build time
export const dynamic = 'force-dynamic'

type RouteContext = {
  params: Promise<{
    user: string
    app: string
  }>
}

/**
 * Parses Sparkle User-Agent to extract version and macOS info.
 * Example UA: "MyApp/1.0.0 Sparkle/2.0.0 (Mac OS X 14.1)"
 */
function parseSparkleUA(userAgent: string): { version?: string; uaCoarse?: string } {
  const result: { version?: string; uaCoarse?: string } = {}

  // Extract app version (first part before space)
  const versionMatch = userAgent.match(/^[^\/]+\/([^\s]+)/)
  if (versionMatch) {
    result.version = versionMatch[1]
  }

  // Extract macOS version
  const macOSMatch = userAgent.match(/Mac OS X ([\d.]+)/)
  if (macOSMatch) {
    result.uaCoarse = `macOS ${macOSMatch[1]}`
  }

  return result
}

export async function GET(req: Request, context: RouteContext) {
  const { user: userSlug, app: appSlug } = await context.params

  // 1. Lookup User by githubLogin
  const user = await prisma.user.findFirst({
    where: { githubLogin: userSlug },
  })

  if (!user) {
    return new NextResponse('User not found', { status: 404 })
  }

  // 2. Lookup App by userId + slug
  const app = await prisma.app.findUnique({
    where: {
      userId_slug: {
        userId: user.id,
        slug: appSlug,
      },
    },
  })

  if (!app) {
    return new NextResponse('App not found', { status: 404 })
  }

  // 3. Query Releases for this app, ordered by publishedAt DESC
  const releases = await prisma.release.findMany({
    where: { appId: app.id },
    orderBy: { publishedAt: 'desc' },
  })

  // 4. Generate XML
  const xml = generateAppcastXML(app.name, releases)

  // 5. Fire-and-forget FetchEvent logging
  try {
    const userAgent = req.headers.get('user-agent') || ''
    const parsed = parseSparkleUA(userAgent)

    await prisma.fetchEvent.create({
      data: {
        appId: app.id,
        version: parsed.version,
        uaCoarse: parsed.uaCoarse,
        timestamp: new Date(),
      },
    })
  } catch (error) {
    // Log error but don't block response
    console.error('Failed to log fetch event:', error)
  }

  // 6. Return RSS XML response
  return new NextResponse(xml, {
    headers: {
      'Content-Type': 'application/rss+xml; charset=utf-8',
    },
  })
}
