# Stickr

Stickr is a private macOS menu bar app for a local WhatsApp sticker library. It reads copies of WhatsApp data, describes stickers through an OpenAI-compatible model, searches them by meaning, and imports rule-based packs through WhatsApp's official sticker-pack flow.

## Build

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stickr.xcodeproj -scheme Stickr build
```

The release script builds with at most two Xcode jobs, signs the app and DMG, submits the DMG to Apple notarization, staples it, and verifies Gatekeeper:

```sh
scripts/release.sh
```

It expects a Developer ID certificate for team `4C8444267Z` and a `notarytool` keychain profile named `stickr-notary`.

## Privacy

Stickr never writes to WhatsApp files. The app keeps the OpenRouter key in the macOS Keychain. Personal stickers, screenshots, reports, and `.env` are excluded from Git.
