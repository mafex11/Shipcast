import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  console.log('Seeding database...');

  const user = await prisma.user.create({
    data: {
      githubId: 12345,
      githubLogin: 'testuser',
      apiToken: 'test-token-12345',
      email: 'testuser@example.com',
    },
  });
  console.log('Created test user:', user.githubLogin);

  const app = await prisma.app.create({
    data: {
      slug: 'test-app',
      name: 'Test App',
      userId: user.id,
    },
  });
  console.log('Created test app:', app.name);

  const release1 = await prisma.release.create({
    data: {
      appId: app.id,
      version: '1.0.0',
      artifactUrl: 'https://github.com/testuser/test-app/releases/download/v1.0.0/TestApp.zip',
      sha256: 'abc123def456789012345678901234567890123456789012345678901234567890',
      edSignature: 'placeholder-ed25519-signature-for-v1.0.0',
      length: 5242880,
      minSystemVersion: '14.0',
      releaseNotesHtml: '<p>Initial release</p>',
      channel: 'stable',
    },
  });
  console.log('Created release:', release1.version);

  const release2 = await prisma.release.create({
    data: {
      appId: app.id,
      version: '1.1.0',
      artifactUrl: 'https://github.com/testuser/test-app/releases/download/v1.1.0/TestApp.zip',
      sha256: 'def456abc789012345678901234567890123456789012345678901234567890123',
      edSignature: 'placeholder-ed25519-signature-for-v1.1.0',
      length: 5300000,
      minSystemVersion: '14.0',
      releaseNotesHtml: '<p>Bug fixes and improvements</p>',
      channel: 'stable',
    },
  });
  console.log('Created release:', release2.version);

  console.log('Seeding complete!');
}

main()
  .catch((e) => {
    console.error('Error seeding database:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
