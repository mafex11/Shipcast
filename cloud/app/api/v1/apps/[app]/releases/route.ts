import { NextResponse } from 'next/server'
import { z } from 'zod'
import { prisma } from '@/lib/prisma'
import { Prisma } from '@prisma/client'

// Dynamic route
export const dynamic = 'force-dynamic'

type RouteContext = {
  params: Promise<{
    app: string
  }>
}

// Zod schema for release creation
const createReleaseSchema = z.object({
  version: z.string().min(1),
  artifact_url: z.string().url(),
  sha256: z.string().min(64).max(64),
  ed_signature: z.string().min(1),
  length: z.number().int().positive(),
  min_system_version: z.string().optional(),
  release_notes_html: z.string().optional(),
  channel: z.string().default('stable'),
})

export async function POST(req: Request, context: RouteContext) {
  const { app: appSlug } = await context.params

  // 1. Extract and validate Authorization header
  const authHeader = req.headers.get('Authorization')
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return NextResponse.json(
      { error: 'Missing or invalid Authorization header' },
      { status: 401 }
    )
  }

  const token = authHeader.substring(7) // Remove "Bearer " prefix

  // 2. Query User by apiToken
  const user = await prisma.user.findUnique({
    where: { apiToken: token },
  })

  if (!user) {
    return NextResponse.json(
      { error: 'Invalid API token' },
      { status: 401 }
    )
  }

  // 3. Query App by slug
  const app = await prisma.app.findFirst({
    where: { slug: appSlug },
  })

  if (!app) {
    return NextResponse.json(
      { error: 'App not found' },
      { status: 404 }
    )
  }

  // 4. Verify ownership
  if (app.userId !== user.id) {
    return NextResponse.json(
      { error: 'You do not have permission to publish releases for this app' },
      { status: 403 }
    )
  }

  // 5. Parse and validate request body
  let body: unknown
  try {
    body = await req.json()
  } catch (error) {
    return NextResponse.json(
      { error: 'Invalid JSON body' },
      { status: 422 }
    )
  }

  const parseResult = createReleaseSchema.safeParse(body)
  if (!parseResult.success) {
    return NextResponse.json(
      {
        error: 'Invalid request body',
        details: parseResult.error.issues,
      },
      { status: 422 }
    )
  }

  const data = parseResult.data

  // 6. Check unique constraint (appId, version, channel)
  const existingRelease = await prisma.release.findFirst({
    where: {
      appId: app.id,
      version: data.version,
      channel: data.channel,
    },
  })

  if (existingRelease) {
    return NextResponse.json(
      {
        error: 'A release with this version and channel already exists',
        existing: {
          id: existingRelease.id,
          version: existingRelease.version,
          channel: existingRelease.channel,
        },
      },
      { status: 409 }
    )
  }

  // 7. Create Release
  try {
    const release = await prisma.release.create({
      data: {
        appId: app.id,
        version: data.version,
        artifactUrl: data.artifact_url,
        sha256: data.sha256,
        edSignature: data.ed_signature,
        length: data.length,
        minSystemVersion: data.min_system_version,
        releaseNotesHtml: data.release_notes_html,
        channel: data.channel,
      },
    })

    // 8. Return 201 with id
    return NextResponse.json(
      { id: release.id },
      { status: 201 }
    )
  } catch (error) {
    console.error('Failed to create release:', error)
    return NextResponse.json(
      { error: 'Failed to create release' },
      { status: 500 }
    )
  }
}
