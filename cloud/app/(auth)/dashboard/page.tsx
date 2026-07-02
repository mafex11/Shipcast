import { auth } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import { redirect } from "next/navigation";
import Link from "next/link";
import { CreateAppForm } from "@/components/CreateAppForm";

export const dynamic = "force-dynamic";

async function getAppsWithStats(userId: string) {
  const apps = await prisma.app.findMany({
    where: { userId },
    include: {
      releases: {
        orderBy: { publishedAt: "desc" },
        take: 1,
      },
      fetchDailies: {
        where: {
          date: {
            gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
          },
        },
      },
    },
  });

  return apps.map((app) => {
    const latestVersion = app.releases[0]?.version || "N/A";
    const totalFetches = app.fetchDailies.reduce((sum, fd) => sum + fd.fetchCount, 0);
    const avgDaily = app.fetchDailies.length > 0 ? Math.round(totalFetches / 7) : 0;

    return {
      id: app.id,
      slug: app.slug,
      name: app.name,
      latestVersion,
      installEstimate: avgDaily,
    };
  });
}

export default async function DashboardPage() {
  const session = await auth();
  if (!session?.user?.id) {
    redirect("/api/auth/signin");
  }

  const apps = await getAppsWithStats(session.user.id);

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-7xl mx-auto">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-3xl font-bold text-gray-900">Your Apps</h1>
          <div className="flex items-center gap-4">
            <span className="text-sm text-gray-600">
              Signed in as {session.user.githubLogin}
            </span>
            <form action="/api/auth/signout" method="post">
              <button
                type="submit"
                className="px-4 py-2 text-sm text-gray-700 hover:text-gray-900"
              >
                Sign out
              </button>
            </form>
          </div>
        </div>

        <div className="mb-8">
          <CreateAppForm />
        </div>

        {apps.length === 0 ? (
          <div className="bg-white rounded-lg shadow p-8 text-center">
            <p className="text-gray-600">
              No apps yet. Create your first app to get started.
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {apps.map((app) => (
              <Link
                key={app.id}
                href={`/dashboard/${app.slug}`}
                className="block bg-white rounded-lg shadow hover:shadow-lg transition-shadow p-6"
              >
                <h2 className="text-xl font-semibold text-gray-900 mb-2">
                  {app.name}
                </h2>
                <div className="space-y-1 text-sm text-gray-600">
                  <p>Latest: {app.latestVersion}</p>
                  <p>Installs: ~{app.installEstimate}/day</p>
                </div>
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
