cask "florestan" do
  version "0.0.2"
  sha256 "b8ac6b2f14dfc841e3e4287403cd65a4bec3e1d15dfc010b60948e188f795f55"

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
