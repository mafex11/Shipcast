# Deployment Checklist

Self-host the Shipcast Cloud service (Next.js app) on Vercel with Neon Postgres. This guide walks through a production deployment to `shipcast.devmafex.com`.

## Prerequisites

- Vercel account (free tier supports this workload)
- Neon account (free tier: 10 GB storage, 100 hours compute/month)
- Cloudflare account (for DNS)
- GitHub account (for OAuth)

## Step 1: Neon Postgres Setup

### Create Database

1. Go to [neon.tech](https://neon.tech)
2. Sign in or create account
3. Click **New Project**
4. Name: `shipcast`
5. Region: Choose closest to your users (e.g., `us-east-1`)
6. Click **Create Project**

### Get Connection String

1. After project creation, copy the **Connection string**
2. Format: `postgresql://user:password@host/dbname?sslmode=require`
3. Save this for Step 3 (Vercel env vars)

### Run Migrations

Migrations are in `cloud/prisma/migrations/`. Apply them to your Neon database.

**Option A: Local Prisma CLI**

Install dependencies:
```bash
cd cloud
npm install
```

Set database URL:
```bash
export DATABASE_URL="postgresql://user:password@host/dbname?sslmode=require"
```

Run migrations:
```bash
npx prisma migrate deploy
```

**Option B: Vercel Post-Build Hook**

Vercel can run migrations on deploy. Add to `package.json`:

```json
{
  "scripts": {
    "build": "next build",
    "postbuild": "prisma migrate deploy"
  }
}
```

Set `DATABASE_URL` in Vercel (Step 3), and migrations run automatically on each deploy.

## Step 2: GitHub OAuth App

### Create OAuth App

1. Go to [github.com/settings/developers](https://github.com/settings/developers)
2. Click **New OAuth App**
3. Fill in:
   - **Application name**: Shipcast
   - **Homepage URL**: `https://shipcast.devmafex.com`
   - **Authorization callback URL**: `https://shipcast.devmafex.com/api/auth/callback/github`
4. Click **Register application**

### Get Credentials

1. Copy **Client ID**
2. Click **Generate a new client secret**
3. Copy **Client Secret** (shown once, save it securely)

Save these for Step 3 (Vercel env vars).

## Step 3: Vercel Deployment

### Install Vercel CLI

```bash
npm install -g vercel
vercel login
```

### Link Project

Navigate to the `cloud/` directory:

```bash
cd cloud
vercel link
```

Follow prompts:
- Set up and deploy: **Y**
- Scope: Your Vercel account
- Link to existing project: **N** (create new)
- Project name: `shipcast`
- Directory: `.` (current directory)

This creates `.vercel/` directory with project config.

### Set Environment Variables

Required environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | Neon Postgres connection string | `postgresql://user:password@host/dbname?sslmode=require` |
| `NEXTAUTH_SECRET` | Secret for NextAuth session encryption | Generate: `openssl rand -base64 32` |
| `NEXTAUTH_URL` | Full URL of your deployment | `https://shipcast.devmafex.com` |
| `GITHUB_ID` | GitHub OAuth Client ID | From Step 2 |
| `GITHUB_SECRET` | GitHub OAuth Client Secret | From Step 2 |
| `CRON_SECRET` | Secret for cron job authentication | Generate: `openssl rand -base64 32` |

Add them via Vercel CLI:

```bash
# Database
vercel env add DATABASE_URL production
# Paste connection string when prompted

# NextAuth
vercel env add NEXTAUTH_SECRET production
# Paste: openssl rand -base64 32

vercel env add NEXTAUTH_URL production
# Enter: https://shipcast.devmafex.com

# GitHub OAuth
vercel env add GITHUB_ID production
# Paste Client ID

vercel env add GITHUB_SECRET production
# Paste Client Secret

# Cron
vercel env add CRON_SECRET production
# Paste: openssl rand -base64 32
```

**Note**: Also add these variables to `preview` and `development` environments if needed:

```bash
vercel env add VARIABLE_NAME preview
vercel env add VARIABLE_NAME development
```

### Deploy to Production

```bash
vercel --prod
```

Vercel will:
1. Build the Next.js app
2. Run `prisma generate` (automatically detected)
3. Run `prisma migrate deploy` (if using postbuild hook)
4. Deploy to production

After deployment, Vercel outputs:

```
✅  Production: https://shipcast-abc123.vercel.app
```

## Step 4: Cloudflare DNS

### Add CNAME Record

1. Log in to [Cloudflare](https://dash.cloudflare.com)
2. Select your domain: `devmafex.com`
3. Go to **DNS** → **Records**
4. Click **Add record**
5. Fill in:
   - **Type**: CNAME
   - **Name**: `shipcast`
   - **Target**: `cname.vercel-dns.com`
   - **Proxy status**: Proxied (orange cloud) or DNS only (gray cloud)
   - **TTL**: Auto
6. Click **Save**

### Add Domain to Vercel

1. Go to [vercel.com/dashboard](https://vercel.com/dashboard)
2. Select your `shipcast` project
3. Go to **Settings** → **Domains**
4. Click **Add**
5. Enter: `shipcast.devmafex.com`
6. Click **Add**

Vercel will verify the CNAME record and issue an SSL certificate (typically 1-5 minutes).

### Verify

Visit `https://shipcast.devmafex.com` in a browser. You should see the Shipcast landing page.

## Step 5: Verify Database Connection

Check that the app connects to Neon:

1. Visit `https://shipcast.devmafex.com/api/health` (if you added a health endpoint)
2. Or sign in with GitHub and check that the dashboard loads

If errors occur, check Vercel logs:

```bash
vercel logs --prod
```

Common issues:
- **"Connection refused"**: Check `DATABASE_URL` format (must include `?sslmode=require`)
- **"Invalid schema"**: Run `npx prisma migrate deploy` again
- **"Authentication failed"**: Verify Neon credentials

## Step 6: Seed Database (Optional)

For testing, seed the database with a test user and app.

Create `cloud/prisma/seed.ts`:

```typescript
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  const user = await prisma.user.create({
    data: {
      githubId: 12345,
      githubLogin: 'testuser',
      email: 'test@example.com',
      apiToken: 'test-token-12345',
    },
  });

  const app = await prisma.app.create({
    data: {
      slug: 'test-app',
      name: 'Test App',
      userId: user.id,
    },
  });

  console.log('Seeded:', { user, app });
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
```

Run seed:

```bash
export DATABASE_URL="your-neon-connection-string"
npx prisma db seed
```

## Step 7: Cron Job (Optional)

The analytics feature requires a daily cron to aggregate `FetchEvent` rows into `FetchDaily` rollups.

### Vercel Cron Configuration

Add to `cloud/vercel.json`:

```json
{
  "crons": [
    {
      "path": "/api/cron/rollup",
      "schedule": "0 1 * * *"
    }
  ]
}
```

This schedules the cron at 1:00 AM UTC daily.

### Cron Route Implementation

The cron route is at `cloud/app/api/cron/rollup/route.ts`. It must verify the `CRON_SECRET` header to prevent unauthorized calls.

Example:

```typescript
import { headers } from 'next/headers';
import { NextResponse } from 'next/server';

export async function GET() {
  const headersList = await headers();
  const authHeader = headersList.get('authorization');
  const expectedSecret = process.env.CRON_SECRET;

  if (!authHeader || authHeader !== `Bearer ${expectedSecret}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  // Run aggregation SQL (see Prisma schema in design spec)
  // ...

  return NextResponse.json({ success: true });
}
```

### Test Cron Locally

```bash
export CRON_SECRET="your-secret"
curl -H "Authorization: Bearer your-secret" http://localhost:3000/api/cron/rollup
```

## Step 8: Monitor

### Vercel Analytics

Enable Vercel Analytics:
1. Project dashboard → **Analytics** → **Enable**
2. Free tier: 100k events/month

### Vercel Logs

View real-time logs:

```bash
vercel logs --prod --follow
```

Filter by function:

```bash
vercel logs --prod --follow --filter="/api/v1/apps"
```

### Neon Monitoring

1. Go to [neon.tech](https://neon.tech) → Your project
2. **Monitoring** tab shows:
   - Compute hours used
   - Storage used
   - Connection count

Free tier limits:
- **Compute**: 100 hours/month (resets monthly)
- **Storage**: 10 GB

If you exceed limits, Neon pauses the database. Upgrade to paid tier ($19/month for 300 hours compute).

## Environment Variables Reference

Complete list for production:

```bash
# Database
DATABASE_URL=postgresql://user:password@host/dbname?sslmode=require

# NextAuth
NEXTAUTH_SECRET=<generated-secret>
NEXTAUTH_URL=https://shipcast.devmafex.com

# GitHub OAuth
GITHUB_ID=<client-id>
GITHUB_SECRET=<client-secret>

# Cron
CRON_SECRET=<generated-secret>

# Optional: Override for CLI
SHIPCAST_BASE_URL=https://shipcast.devmafex.com
```

## Troubleshooting

### Build Failures

**Error: "Prisma schema not found"**  
**Fix**: Ensure `prisma/schema.prisma` exists in `cloud/` directory.

**Error: "Module not found: Can't resolve '@prisma/client'"**  
**Fix**: Vercel auto-detects Prisma. If it fails, add to `package.json`:

```json
{
  "scripts": {
    "postinstall": "prisma generate"
  }
}
```

### Runtime Errors

**"Invalid `prisma.user.findUnique()` invocation"**  
**Cause**: Schema mismatch between generated client and database.  
**Fix**: Run `npx prisma migrate deploy` again.

**"Connection pool timeout"**  
**Cause**: Too many concurrent connections (Neon free tier: 100 max).  
**Fix**: Use Prisma connection pooling:

```typescript
// lib/prisma.ts
import { PrismaClient } from '@prisma/client';
import { Pool } from 'pg';
import { PrismaPg } from '@prisma/adapter-pg';

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const adapter = new PrismaPg(pool);

export const prisma = new PrismaClient({ adapter });
```

### DNS Not Resolving

**Symptom**: `shipcast.devmafex.com` shows "ERR_NAME_NOT_RESOLVED"  
**Fix**:
1. Verify CNAME record in Cloudflare: `dig shipcast.devmafex.com`
2. Wait up to 5 minutes for DNS propagation
3. Clear browser cache

## Scaling Beyond Free Tier

When to upgrade:

- **Vercel**: Free tier supports ~100k requests/month. Upgrade to Pro ($20/month) for 1M+ requests.
- **Neon**: Free tier is 100 hours compute/month. Upgrade to Scale ($19/month) for 300 hours.

### Cost Estimate for 1,000 Active Apps

- **Database**: 1,000 apps × 365 days × 5 versions = ~1.8M rows → ~1 GB storage (free tier OK)
- **Compute**: Edge-cached appcasts (minimal compute) → free tier OK
- **Bandwidth**: 1 KB appcast × 10k installs checking daily × 1,000 apps × 30 days = ~300 GB/month → Vercel Pro required

Expected monthly cost at 1,000 apps: ~$20 (Vercel Pro).

## Next Steps

- **Test the API**: See [Getting Started](getting-started.md) for CLI usage
- **Monitor analytics**: Dashboard at `https://shipcast.devmafex.com/dashboard`
- **Set up alerts**: Vercel supports Slack/email notifications for deployment failures
