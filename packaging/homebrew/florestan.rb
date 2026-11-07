cask "florestan" do
  version "0.0.4"
  sha256 "ec332049ab213312114418d6f5f1b445f804e17bebdacf4d1c1aa0a90d7c6774"

  url "https://github.com/ingridstevens/florestan/releases/download/v#{version}/Florestan.exe.dmg"
  name "Florestan.exe"
  desc "Menu bar app that puts YouTube songs and playlists into Apple Music"
  homepage "https://github.com/ingridstevens/florestan"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Florestan.exe.app"

  uninstall quit: "local.florestan"

  zap trash: [
    "~/Library/Application Support/Florestan",
    "~/Library/Preferences/local.florestan.plist",
    "~/Music/Florestan",
  ]

  caveats <<~EOS
    Florestan.exe isn't notarized by Apple. The first time you open it, macOS blocks it:
    click Done, then System Settings › Privacy & Security › Open Anyway.

    Only download content you own or have the rights to.
  EOS
end
