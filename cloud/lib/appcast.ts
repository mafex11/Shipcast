import type { Release } from '@prisma/client'

/**
 * Escapes special XML characters in a string.
 */
function escapeXML(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
}

/**
 * Wraps HTML in a CDATA section. A literal "]]>" inside the content would
 * terminate the CDATA early, so split it across two CDATA sections.
 */
function toCDATA(html: string): string {
  return `<![CDATA[${html.replaceAll(']]>', ']]]]><![CDATA[>')}]]>`
}

/**
 * Formats a Date object to RFC 2822 format (required for RSS pubDate).
 */
function toRFC2822(date: Date): string {
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

  const dayName = days[date.getUTCDay()]
  const day = date.getUTCDate().toString().padStart(2, '0')
  const month = months[date.getUTCMonth()]
  const year = date.getUTCFullYear()
  const hours = date.getUTCHours().toString().padStart(2, '0')
  const minutes = date.getUTCMinutes().toString().padStart(2, '0')
  const seconds = date.getUTCSeconds().toString().padStart(2, '0')

  return `${dayName}, ${day} ${month} ${year} ${hours}:${minutes}:${seconds} +0000`
}

/**
 * Generates a Sparkle-compliant RSS 2.0 appcast XML string.
 *
 * @param appName The name of the application
 * @param releases Array of releases, will be sorted by publishedAt DESC
 * @returns RSS 2.0 XML string with Sparkle namespace
 */
export function generateAppcastXML(appName: string, releases: Release[]): string {
  const escapedAppName = escapeXML(appName)

  // Sort releases by publishedAt DESC (newest first)
  const sortedReleases = [...releases].sort((a, b) =>
    b.publishedAt.getTime() - a.publishedAt.getTime()
  )

  const items = sortedReleases.map(release => {
    const title = `${escapedAppName} ${escapeXML(release.version)}`
    const pubDate = toRFC2822(release.publishedAt)

    let itemContent = `    <item>
      <title>${title}</title>
      <sparkle:version>${escapeXML(release.version)}</sparkle:version>
      <pubDate>${pubDate}</pubDate>`

    if (release.releaseNotesHtml) {
      // Inline release notes as CDATA, matching the Swift AppcastGenerator.
      // (A releaseNotesLink would need a hosted notes page, which doesn't exist.)
      itemContent += `\n      <description>${toCDATA(release.releaseNotesHtml)}</description>`
    }

    itemContent += `\n      <enclosure url="${escapeXML(release.artifactUrl)}" length="${release.length}" type="application/octet-stream" sparkle:edSignature="${escapeXML(release.edSignature)}" />`

    if (release.minSystemVersion) {
      itemContent += `\n      <sparkle:minimumSystemVersion>${escapeXML(release.minSystemVersion)}</sparkle:minimumSystemVersion>`
    }

    itemContent += '\n    </item>'
    return itemContent
  }).join('\n')

  const xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>${escapedAppName}</title>
    <link>https://shipcast.dev</link>
    <description>Updates for ${escapedAppName}</description>
    <language>en</language>
${items}
  </channel>
</rss>`

  return xml
}
