type Release = {
  version: string;
  publishedAt: Date;
  channel: string;
  artifactUrl: string;
};

export function ReleaseTable({ releases }: { releases: Release[] }) {
  return (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Version
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Date
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Channel
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
              Artifact
            </th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {releases.map((release) => (
            <tr key={`${release.version}-${release.channel}`}>
              <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                {release.version}
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {release.publishedAt.toLocaleDateString()}
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {release.channel}
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-blue-600">
                <a
                  href={release.artifactUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:underline"
                >
                  Download
                </a>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
