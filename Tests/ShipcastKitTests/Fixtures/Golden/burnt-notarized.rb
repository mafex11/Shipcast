cask "burnt" do
  version "1.2.0"
  sha256 "abc123"

  url "https://github.com/mafex11/burnt/releases/download/v#{version}/Burnt.zip"
  name "Burnt"
  desc "Burnt for macOS"
  homepage "https://github.com/mafex11/burnt"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Burnt.app"

  uninstall quit: "dev.mafex.burnt"

  zap trash: [
    "~/Library/Preferences/dev.mafex.burnt.plist",
    "~/Library/Application Support/Burnt",
    "~/Library/Caches/dev.mafex.burnt",
  ]
end
