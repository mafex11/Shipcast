export function PricingTable() {
  return (
    <div className="max-w-2xl mx-auto">
      <h2 className="text-3xl font-bold text-gray-900 text-center mb-8">
        Pricing
      </h2>
      <div className="border border-gray-200 rounded-lg p-8 text-center">
        <div className="mb-4">
          <p className="text-4xl font-bold text-gray-900">Free</p>
          <p className="text-gray-600 mt-2">During Beta</p>
        </div>
        <div className="border-t border-gray-200 pt-6 mb-6">
          <ul className="space-y-3 text-gray-600">
            <li>Unlimited apps and releases</li>
            <li>Hosted appcast.xml</li>
            <li>Analytics dashboard</li>
            <li>GitHub integration</li>
          </ul>
        </div>
        <div className="bg-gray-50 rounded-lg p-4">
          <p className="text-sm text-gray-600 mb-2">After beta launch:</p>
          <p className="text-2xl font-semibold text-gray-900">$9/month</p>
          <p className="text-sm text-gray-600 mt-1">per app</p>
          <p className="text-xs text-gray-500 mt-3">
            CLI always free and open source (MIT)
          </p>
        </div>
      </div>
    </div>
  );
}
