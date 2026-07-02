// REQUIRES: seeded DB with User(apiToken="test-token-12345") + App(slug="test-app") + npm run dev
import { test, expect } from '@playwright/test';

test.describe('Shipcast API smoke tests', () => {
  test('POST /api/v1/apps/:app/releases creates release', async ({ request }) => {
    const response = await request.post('/api/v1/apps/test-app/releases', {
      headers: {
        'Authorization': 'Bearer test-token-12345',
        'Content-Type': 'application/json',
      },
      data: {
        version: '1.0.0-test',
        artifactUrl: 'https://github.com/test/test-app/releases/download/v1.0.0/TestApp.zip',
        sha256: 'abc123def456',
        edSignature: 'test-ed-signature-base64',
        length: 12345678,
        minSystemVersion: '14.0',
        releaseNotesHtml: '<p>Test release</p>',
        channel: 'stable',
      },
    });

    expect(response.status()).toBe(201);
    const body = await response.json();
    expect(body).toHaveProperty('id');
  });

  test('GET /u/testuser/test-app/appcast.xml returns valid Sparkle XML', async ({ request }) => {
    const response = await request.get('/u/testuser/test-app/appcast.xml');

    expect(response.status()).toBe(200);
    expect(response.headers()['content-type']).toContain('xml');

    const xmlText = await response.text();

    // Verify XML structure
    expect(xmlText).toContain('<?xml version="1.0" encoding="utf-8"?>');
    expect(xmlText).toContain('<rss version="2.0"');
    expect(xmlText).toContain('xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"');
    expect(xmlText).toContain('<channel>');
    expect(xmlText).toContain('<item>');

    // Verify release metadata
    expect(xmlText).toContain('<sparkle:version>');
    expect(xmlText).toContain('<enclosure');
    expect(xmlText).toContain('sparkle:edSignature=');

    // Parse to verify it's well-formed XML
    const parser = new DOMParser();
    const doc = parser.parseFromString(xmlText, 'text/xml');
    const parseError = doc.querySelector('parsererror');
    expect(parseError).toBeNull();

    // Verify enclosure has required attributes
    const enclosures = doc.querySelectorAll('enclosure');
    expect(enclosures.length).toBeGreaterThan(0);

    const firstEnclosure = enclosures[0];
    expect(firstEnclosure.getAttribute('url')).toBeTruthy();
    expect(firstEnclosure.getAttribute('length')).toBeTruthy();
    expect(firstEnclosure.getAttributeNS('http://www.andymatuschak.org/xml-namespaces/sparkle', 'edSignature')).toBeTruthy();
  });
});
