cask "kol" do
  version "0.2.11"
  sha256 :no_check  # Will be filled after first release

  url "https://github.com/alandotcom/Kol/releases/download/v#{version}/Kol-v#{version}.zip"
  name "Kol"
  desc "On-device voice-to-text for macOS"
  homepage "https://github.com/alandotcom/Kol"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "Kol.app"

  zap trash: [
    "~/Library/Application Support/com.alandotcom.Kol",
    "~/Library/Caches/com.alandotcom.Kol",
    "~/Library/Containers/com.alandotcom.Kol",
    "~/Library/Preferences/com.alandotcom.Kol.plist",
  ]
end
