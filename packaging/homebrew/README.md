# Homebrew cask

`florestan.rb` is the cask for a Homebrew tap, `ingridstevens/homebrew-florestan`, so Florestan.exe can be installed
with `brew install --cask ingridstevens/florestan/florestan`. For each release, set `version` and `sha256`
(`shasum -a 256 build/Florestan.exe.dmg`) and copy it to the tap's `Casks/florestan.rb`.
