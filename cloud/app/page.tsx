import Link from "next/link";
import { CopyButton } from "@/components/CopyButton";
import { FeatureGrid } from "@/components/FeatureGrid";
import { PricingTable } from "@/components/PricingTable";

export default function Home() {
  const brewCommand = "brew install mafex11/tap/shipcast";

  return (
    <div className="min-h-screen bg-white">
      <nav className="border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center h-16">
            <div className="flex-shrink-0 font-bold text-xl text-gray-900">
              ShipCast
            </div>
            <div className="flex items-center gap-4">
              <a
                href="https://github.com/mafex11/ShipCast"
                target="_blank"
                rel="noopener noreferrer"
                className="text-gray-600 hover:text-gray-900"
              >
                GitHub
              </a>
              <Link
                href="/api/auth/signin"
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
              >
                Sign In
              </Link>
            </div>
          </div>
        </div>
      </nav>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-16">
        <div className="text-center mb-16">
          <h1 className="text-5xl font-bold text-gray-900 mb-6">
            Push a tag. Ship a Mac app.
          </h1>
          <p className="text-xl text-gray-600 mb-8 max-w-2xl mx-auto">
            Zero-config CI pipeline that turns GitHub tags into signed, notarized,
            auto-updating Mac apps. No Apple Developer account required during development.
          </p>
          <div className="flex flex-col items-center gap-4">
            <div className="flex items-center gap-2 bg-gray-100 px-6 py-3 rounded-lg">
              <code className="text-sm font-mono">{brewCommand}</code>
              <CopyButton text={brewCommand} />
            </div>
            <p className="text-sm text-gray-500">
              Free and open source. MIT licensed.
            </p>
          </div>
        </div>

        <FeatureGrid />

        <div className="mt-16">
          <PricingTable />
        </div>

        <div className="mt-16 text-center">
          <h2 className="text-3xl font-bold text-gray-900 mb-4">
            Ready to ship?
          </h2>
          <p className="text-gray-600 mb-8">
            Get started with the CLI and push your first release in minutes.
          </p>
          <Link
            href="/api/auth/signin"
            className="inline-block px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium"
          >
            Get Started
          </Link>
        </div>
      </main>

      <footer className="border-t border-gray-200 mt-16">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          <div className="text-center text-gray-600 text-sm">
            <p>
              Built by{" "}
              <a
                href="https://github.com/mafex11"
                target="_blank"
                rel="noopener noreferrer"
                className="text-blue-600 hover:text-blue-800"
              >
                mafex11
              </a>
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
