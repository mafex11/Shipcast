export function FeatureGrid() {
  const features = [
    {
      title: "Free CLI",
      description:
        "Full pipeline open-source and MIT licensed. Run the entire build and signing process locally or in your CI.",
    },
    {
      title: "Hosted Updates",
      description:
        "Automatic appcast.xml generation and hosting at shipcast.devmafex.com. Your users get seamless updates via Sparkle.",
    },
    {
      title: "Ad-Hoc Signing",
      description:
        "Ship developer builds without an Apple Developer account. Perfect for internal testing and beta distributions.",
    },
    {
      title: "Auto Casks",
      description:
        "Automatic Homebrew Cask generation and pull requests. Your app lands in brew install with zero manual work.",
    },
  ];

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
      {features.map((feature, idx) => (
        <div
          key={idx}
          className="border border-gray-200 rounded-lg p-6 hover:shadow-lg transition-shadow"
        >
          <h3 className="text-xl font-semibold text-gray-900 mb-2">
            {feature.title}
          </h3>
          <p className="text-gray-600">{feature.description}</p>
        </div>
      ))}
    </div>
  );
}
