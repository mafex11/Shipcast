import { NextResponse, after } from 'next/server'
import { prisma } from '@/lib/prisma'
import { generateAppcastXML } from '@/lib/appcast'

// Caching contract: the route is dynamic at the origin (it reads request
// headers and query params, so Next.js will not prerender it), but the
// response carries Cache-Control so the CDN serves it for 5 minutes. CDN
// caching wins over per-fetch analytics precision: cached hits never reach
// this handler, so FetchEvent undercounts during the cache window — accepted
// trade-off. No `revalidate`/`force-dynamic` segment exports: the
// request-time reads already make it dynamic, and the extra configs would
// only add ambiguity about which caching mechanism applies.

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

  // 3. Query Releases for this app on the requested channel (default stable),
  // ordered by publishedAt DESC. `?channel=beta` serves the beta feed.
  const channel = new URL(req.url).searchParams.get('channel') || 'stable'
  const releases = await prisma.release.findMany({
    where: { appId: app.id, channel },
    orderBy: { publishedAt: 'desc' },
  })

  // 4. Generate XML
  const xml = generateAppcastXML(app.name, releases)

  // 5. Fire-and-forget FetchEvent logging — after() runs the insert once the
  // response has been sent, so analytics never delays or breaks the feed.
  const userAgent = req.headers.get('user-agent') || ''
  after(async () => {
    try {
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
      console.error('Failed to log fetch event:', error)
    }
  })

  // 6. Return RSS XML response (CDN-cacheable for 5 minutes)
  return new NextResponse(xml, {
    headers: {
      'Content-Type': 'application/rss+xml; charset=utf-8',
      'Cache-Control': 'public, s-maxage=300, stale-while-revalidate=60',
    },
  })
}
