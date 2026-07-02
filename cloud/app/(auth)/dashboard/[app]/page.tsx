import { auth } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { redirect, notFound } from "next/navigation";
import Link from "next/link";
import { ReleaseTable } from "@/components/ReleaseTable";
import { AdoptionChart } from "@/components/AdoptionChart";
import { CopyButton } from "@/components/CopyButton";

export const dynamic = "force-dynamic";

async function getAppData(slug: string, userId: string) {
  const app = await prisma.app.findFirst({
    where: { slug, userId },
    include: {
      releases: {
        orderBy: { publishedAt: "desc" },
      },
      fetchDailies: {
        where: {
          date: {
            gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000),
          },
        },
        orderBy: { date: "asc" },
      },
    },
  });

  if (!app) return null;

  const chartData = app.fetchDailies.reduce((acc, fd) => {
    const dateStr = fd.date.toISOString().split("T")[0];
    const existing = acc.find((d) => d.date === dateStr);
    if (existing) {
      existing[fd.version] = fd.fetchCount;
    } else {
      acc.push({ date: dateStr, [fd.version]: fd.fetchCount });
    }
    return acc;
  }, [] as Array<{ date: string; [version: string]: number | string }>);

  return { app, chartData };
}

export default async function AppDashboardPage({
  params,
}: {
  params: Promise<{ app: string }>;
}) {
  const { app: slug } = await params;
  const session = await auth();

  if (!session?.user?.id) {
    redirect("/api/auth/signin");
  }

  const data = await getAppData(slug, session.user.id);
  if (!data) {
    notFound();
  }

  const { app, chartData } = data;
  const appcastUrl = `https://shipcast.devmafex.com/u/${session.user.githubLogin}/${slug}/appcast.xml`;

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-7xl mx-auto">
        <div className="mb-6">
          <Link
            href="/dashboard"
            className="text-blue-600 hover:text-blue-800 text-sm"
          >
            ← Back to Dashboard
          </Link>
        </div>

        <h1 className="text-3xl font-bold text-gray-900 mb-2">{app.name}</h1>
        <p className="text-gray-600 mb-8">Slug: {app.slug}</p>

        <div className="bg-white rounded-lg shadow p-6 mb-8">
          <h2 className="text-xl font-semibold mb-4">Appcast URL</h2>
          <div className="flex items-center gap-2">
            <code className="flex-1 bg-gray-100 px-4 py-2 rounded text-sm">
              {appcastUrl}
            </code>
            <CopyButton text={appcastUrl} />
          </div>
        </div>

        <div className="bg-white rounded-lg shadow p-6 mb-8">
          <h2 className="text-xl font-semibold mb-4">Adoption Over Time</h2>
          {chartData.length > 0 ? (
            <AdoptionChart data={chartData} />
          ) : (
            <p className="text-gray-600">No fetch data yet</p>
          )}
        </div>

        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-xl font-semibold mb-4">Releases</h2>
          {app.releases.length > 0 ? (
            <ReleaseTable releases={app.releases} />
          ) : (
            <p className="text-gray-600">No releases yet</p>
          )}
        </div>
      </div>
    </div>
  );
}
