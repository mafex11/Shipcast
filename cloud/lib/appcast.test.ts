import { describe, it, expect } from 'vitest'
import { generateAppcastXML } from './appcast'
import type { Release } from '@prisma/client'

describe('generateAppcastXML', () => {
  it('generates valid RSS with empty channel when no releases', () => {
    const xml = generateAppcastXML('TestApp', [])

    expect(xml).toContain('<?xml version="1.0" encoding="utf-8"?>')
    expect(xml).toContain('<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">')
    expect(xml).toContain('<channel>')
    expect(xml).toContain('<title>TestApp</title>')
    expect(xml).toContain('</channel>')
    expect(xml).toContain('</rss>')
    expect(xml).not.toContain('<item>')
  })

  it('generates item with all required fields for single release', () => {
    const release: Release = {
      id: 'rel_123',
      appId: 'app_123',
      version: '1.0.0',
      artifactUrl: 'https://example.com/app-1.0.0.zip',
      sha256: 'abc123',
      edSignature: 'sig123',
      length: 1024000,
      minSystemVersion: '10.15',
      releaseNotesHtml: '<p>Initial release</p>',
      channel: 'stable',
      publishedAt: new Date('2024-01-15T10:30:00Z'),
    }

    const xml = generateAppcastXML('TestApp', [release])

    expect(xml).toContain('<item>')
    expect(xml).toContain('<title>TestApp 1.0.0</title>')
    expect(xml).toContain('<sparkle:version>1.0.0</sparkle:version>')
    expect(xml).toContain('<pubDate>Mon, 15 Jan 2024 10:30:00 +0000</pubDate>')
    expect(xml).toContain('<enclosure url="https://example.com/app-1.0.0.zip" length="1024000" type="application/octet-stream" sparkle:edSignature="sig123" />')
    expect(xml).toContain('<sparkle:minimumSystemVersion>10.15</sparkle:minimumSystemVersion>')
    expect(xml).toContain('<description><![CDATA[<p>Initial release</p>]]></description>')
    expect(xml).not.toContain('sparkle:releaseNotesLink')
    expect(xml).toContain('</item>')
  })

  it('sorts multiple releases by publishedAt DESC (newest first)', () => {
    const releases: Release[] = [
      {
        id: 'rel_1',
        appId: 'app_123',
        version: '1.0.0',
        artifactUrl: 'https://example.com/app-1.0.0.zip',
        sha256: 'abc1',
        edSignature: 'sig1',
        length: 1000,
        minSystemVersion: null,
        releaseNotesHtml: null,
        channel: 'stable',
        publishedAt: new Date('2024-01-10T10:00:00Z'),
      },
      {
        id: 'rel_2',
        appId: 'app_123',
        version: '2.0.0',
        artifactUrl: 'https://example.com/app-2.0.0.zip',
        sha256: 'abc2',
        edSignature: 'sig2',
        length: 2000,
        minSystemVersion: null,
        releaseNotesHtml: null,
        channel: 'stable',
        publishedAt: new Date('2024-01-20T10:00:00Z'),
      },
      {
        id: 'rel_3',
        appId: 'app_123',
        version: '1.5.0',
        artifactUrl: 'https://example.com/app-1.5.0.zip',
        sha256: 'abc3',
        edSignature: 'sig3',
        length: 1500,
        minSystemVersion: null,
        releaseNotesHtml: null,
        channel: 'stable',
        publishedAt: new Date('2024-01-15T10:00:00Z'),
      },
    ]

    const xml = generateAppcastXML('TestApp', releases)

    // Find positions of version strings in the XML
    const version2Pos = xml.indexOf('<sparkle:version>2.0.0</sparkle:version>')
    const version15Pos = xml.indexOf('<sparkle:version>1.5.0</sparkle:version>')
    const version1Pos = xml.indexOf('<sparkle:version>1.0.0</sparkle:version>')

    // Verify they appear in descending date order
    expect(version2Pos).toBeLessThan(version15Pos)
    expect(version15Pos).toBeLessThan(version1Pos)
  })

  it('omits sparkle:minimumSystemVersion when not set', () => {
    const release: Release = {
      id: 'rel_123',
      appId: 'app_123',
      version: '1.0.0',
      artifactUrl: 'https://example.com/app-1.0.0.zip',
      sha256: 'abc123',
      edSignature: 'sig123',
      length: 1024000,
      minSystemVersion: null,
      releaseNotesHtml: '<p>Notes</p>',
      channel: 'stable',
      publishedAt: new Date('2024-01-15T10:30:00Z'),
    }

    const xml = generateAppcastXML('TestApp', [release])

    expect(xml).not.toContain('sparkle:minimumSystemVersion')
  })

  it('omits description when releaseNotesHtml is not set', () => {
    const release: Release = {
      id: 'rel_123',
      appId: 'app_123',
      version: '1.0.0',
      artifactUrl: 'https://example.com/app-1.0.0.zip',
      sha256: 'abc123',
      edSignature: 'sig123',
      length: 1024000,
      minSystemVersion: '10.15',
      releaseNotesHtml: null,
      channel: 'stable',
      publishedAt: new Date('2024-01-15T10:30:00Z'),
    }

    const xml = generateAppcastXML('TestApp', [release])

    expect(xml).not.toContain('<description><![CDATA[')
    expect(xml).not.toContain('sparkle:releaseNotesLink')
  })

  it('guards a literal ]]> inside release notes by splitting the CDATA', () => {
    const release: Release = {
      id: 'rel_123',
      appId: 'app_123',
      version: '1.0.0',
      artifactUrl: 'https://example.com/app-1.0.0.zip',
      sha256: 'abc123',
      edSignature: 'sig123',
      length: 1024000,
      minSystemVersion: null,
      releaseNotesHtml: '<p>tricky ]]> content</p>',
      channel: 'stable',
      publishedAt: new Date('2024-01-15T10:30:00Z'),
    }

    const xml = generateAppcastXML('TestApp', [release])

    expect(xml).toContain(
      '<description><![CDATA[<p>tricky ]]]]><![CDATA[> content</p>]]></description>'
    )
  })

  it('escapes XML special characters in app name and version', () => {
    const release: Release = {
      id: 'rel_123',
      appId: 'app_123',
      version: '1.0.0-beta&test',
      artifactUrl: 'https://example.com/app.zip?ver=1&test=true',
      sha256: 'abc123',
      edSignature: 'sig"123',
      length: 1024000,
      minSystemVersion: null,
      releaseNotesHtml: null,
      channel: 'stable',
      publishedAt: new Date('2024-01-15T10:30:00Z'),
    }

    const xml = generateAppcastXML('Test&App<>', [release])

    expect(xml).toContain('<title>Test&amp;App&lt;&gt; 1.0.0-beta&amp;test</title>')
    expect(xml).toContain('<sparkle:version>1.0.0-beta&amp;test</sparkle:version>')
    expect(xml).toContain('url="https://example.com/app.zip?ver=1&amp;test=true"')
    expect(xml).toContain('sparkle:edSignature="sig&quot;123"')
  })

  it('matches golden file output', () => {
    const releases: Release[] = [
      {
        id: 'rel_new',
        appId: 'app_test',
        version: '2.0.0',
        artifactUrl: 'https://cdn.shipcast.dev/myapp/2.0.0.zip',
        sha256: 'def456',
        edSignature: 'newsig456',
        length: 2048000,
        minSystemVersion: '11.0',
        releaseNotesHtml: '<p>Major update</p>',
        channel: 'stable',
        publishedAt: new Date('2024-02-01T12:00:00Z'),
      },
      {
        id: 'rel_old',
        appId: 'app_test',
        version: '1.0.0',
        artifactUrl: 'https://cdn.shipcast.dev/myapp/1.0.0.zip',
        sha256: 'abc123',
        edSignature: 'oldsig123',
        length: 1024000,
        minSystemVersion: null,
        releaseNotesHtml: null,
        channel: 'stable',
        publishedAt: new Date('2024-01-01T10:00:00Z'),
      },
    ]

    const xml = generateAppcastXML('MyApp', releases)

    const expectedXML = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MyApp</title>
    <link>https://shipcast.dev</link>
    <description>Updates for MyApp</description>
    <language>en</language>
    <item>
      <title>MyApp 2.0.0</title>
      <sparkle:version>2.0.0</sparkle:version>
      <pubDate>Thu, 01 Feb 2024 12:00:00 +0000</pubDate>
      <description><![CDATA[<p>Major update</p>]]></description>
      <enclosure url="https://cdn.shipcast.dev/myapp/2.0.0.zip" length="2048000" type="application/octet-stream" sparkle:edSignature="newsig456" />
      <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
    </item>
    <item>
      <title>MyApp 1.0.0</title>
      <sparkle:version>1.0.0</sparkle:version>
      <pubDate>Mon, 01 Jan 2024 10:00:00 +0000</pubDate>
      <enclosure url="https://cdn.shipcast.dev/myapp/1.0.0.zip" length="1024000" type="application/octet-stream" sparkle:edSignature="oldsig123" />
    </item>
  </channel>
</rss>`

    expect(xml).toBe(expectedXML)
  })
})
