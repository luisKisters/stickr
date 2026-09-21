# Stickr: build plan
Stickr is a macOS menu bar app. It reads the WhatsApp stickers that are already on this Mac, lets a cheap vision model describe them, sorts them into packs that you define with one sentence, and installs these packs into the normal WhatsApp sticker tray.
Owner: Luis Kisters. Written 21 September 2026. The folder of this project is `~/code/projects/stickr`.
## How to use this plan
1. Open `mockup/walkthrough.html` first. Run `python3 -m http.server 4173 -d mockup` and open `http://localhost:4173/walkthrough.html`. It shows every screen. Each step lists what must be true in the real app. Those lists are part of this plan.
2. Do the phases in order. One phase per run: `scripts/run-phase.sh <number>`. The script starts Codex CLI with its default model, GLM 5.3 Flash.
3. A phase is done only when every line under "Done when" was run and its real output is in `reports/phase-<number>.md`.
4. When this plan and a verified fact disagree, the verified fact wins. When this plan and the code disagree, read the code, then fix the plan in the same change.
## What Luis wants
- His stickers sorted by meaning into packs. He writes one sentence per pack. The app fills the pack and keeps it current.
- The packs inside WhatsApp itself, in the normal sticker tray. Sending stays a normal WhatsApp click.
- Search by meaning in German and English: "Stress wegen Abgabe" finds the cortisol gauge.
- Cheap AI. Default: `z-ai/glm-5.3-flash` through OpenRouter, Baseten first. Any other OpenAI-compatible server must work through a base URL field.
- A screen where he sees and corrects what the model understood: caption, mood, tags, emoji.
- A command line tool for everything the app can do. Luis prefers CLIs over MCP servers.
- One DMG. Open it, drag the app to Applications, done. Signed and notarized, so no Gatekeeper warning.
- Proof that it works in the real WhatsApp app, produced by a computer-use agent, with screenshots.
## What Luis does not want
- No Anthropic API. No API key other than the one named in "Secrets".
- No MCP server.
- No write to any WhatsApp file, ever. Read copies of the databases. The only way into WhatsApp is its official sticker pack import.
- No claim that Stickr "sends a sticker" from its own window. WhatsApp turns every outside sticker file into a photo. See "Verified facts".
- No Electron, no React, no bundler, no CSS framework, no UI kit. The UI is the HTML, CSS and JS of the mockup.
- No second classifier for packs. A pack is a saved meaning search plus pins and removals.
- No local model, no vector database, no background daemon besides the app itself. Around 500 stickers need none of that.
- No feature that is not in the walkthrough. No settings that the walkthrough does not show.
- No iPhone app in this version. See "Later".
- No memory files, journals or handoff notes. State lives in code, tests, this plan and `reports/`.
## Verified facts
All of this was tested on this Mac on 21 September 2026. Do not re-argue these points. Build on them.
| Fact | How it was tested |
|---|---|
| WhatsApp keeps all stickers unencrypted in `~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/`. `Sticker.sqlite` has the library, `stickers/` has the WebP files, `ChatStorage.sqlite` has sent and received sticker messages with file paths (`ZMESSAGETYPE = 15`). | Read with `sqlite3`. |
| Stickers without a pack in `ZWACDSTICKER` (`ZSTICKERPACK is null`) are the user's favorites and saved stickers. They sync from the phone. | 122 rows on this Mac. |
| WhatsApp is sandboxed and uses the hardened runtime. Code cannot be injected. | `codesign -d --entitlements`. |
| A WebP file pasted into a chat opens the photo editor. It is sent as a photo, not as a sticker. The same happens with drag and drop. Raw WebP data on the pasteboard does nothing. | Done in the "Message yourself" chat with synthetic events. |
| The official third-party sticker pack import works on the Mac. Put the pack JSON on the general pasteboard with type `net.whatsapp.third-party.sticker-pack`, then open `whatsapp://stickerPack`. WhatsApp shows the pack with an "Add to my stickers" button and then says "Sticker pack added". The pack appears as a tab in the native tray and as a row in `ZWACDABSTRACTSTICKERPACK` with `Z_ENT = 2`. | `tools/bin/wa-ui import-pack`, 5 static stickers of 512 x 512 px, tray icon PNG 96 x 96 px. |
| A second import with the same `identifier` creates a second pack. WhatsApp appends a random UUID to the ID. A pack can not be updated in place. | Two imports, two rows. Both test packs are still installed and are named "Stickr test cats". |
| The native tray has its own search field, "Search with text or emoji", and mood buttons. Tray buttons have Accessibility identifiers, for example `StickerBrowserView_StickerEditButton`. Single stickers in the tray have no usable label. | `wa-ui ax`. |
| The menu item with identifier `send_stickers` opens the tray. | `AXPress`. |
| `z-ai/glm-5.3-flash` on OpenRouter accepts images, including animated WebP sent as it is, and supports strict JSON schema output. Baseten serves it under provider slug `baseten`. Reasoning can not be switched off, so send `reasoning: {effort: "low"}` and at least `max_tokens: 1200`. | Real requests. About 2 to 6 s and 0.0001 USD per sticker. |
| Baseten rate limits the shared pool. In the first trial 18 of 40 parallel requests failed with HTTP 429. With three parallel requests, four tries with a growing pause, and routing `{"order": ["baseten"], "allow_fallbacks": true}`, 40 of 40 passed. 26 were served by Baseten. | Walkthrough step 4 in real mode. |
| `baai/bge-m3` on the OpenRouter embeddings endpoint returns 1024 numbers and matches German queries to English captions. | Real requests. |
| A fixed similarity cut fails across languages. A z-score cut works: keep a sticker when `(score - mean) / standard deviation` over the whole library is at least 2.0 for search and 0.6 for packs. | `tests/search_cases.json` holds the measured cases. |
| Codex CLI 0.154 with the default model `opencode-go/glm-5.3-flash` runs on this Mac and reads screenshots passed with `-i`. | `codex exec -i`. |
| A "Developer ID Application: Luis William Kisters (4C8444267Z)" certificate is in the keychain. Xcode is in `/Applications/Xcode.app`, but the active developer directory is the command line tools. `xcodegen` is installed. `create-dmg` is not. | `security find-identity`, `xcodebuild -version`. |
## Secrets
- The only OpenRouter key for this project is in `.env` as `OPENROUTER_API_KEY`. The file is gitignored and has mode 600. The key has a 1 USD limit. The whole project needs a few cents.
- Luis wants credentials in 1Password. `op item create` timed out twice while this plan was written, because nobody confirmed the Touch ID prompt. When Luis is at the Mac, run this once, then delete the value from `.env` and load it with `op read`:
```
op item create --category "API Credential" --title "OpenRouter API Key - stickr" --vault Personal "credential=$(grep -o 'sk-or-.*' .env)"
```
- The app itself stores the key in the macOS Keychain, never in a file, a log, a test fixture or a commit.
- Notarization needs an Apple ID app-specific password. The 1Password item "iCloud notetakr-notarization" is the likely source. Phase 6 says what to do.
## The three moments that need Luis
Everything else runs without him.
1. Phase 0, gate G6: look at WhatsApp on the iPhone and say whether the pack "Stickr test cats" is there.
2. Phase 5: allow the built app to read data from other apps, and allow Accessibility, when macOS asks.
3. Phase 6: confirm one Touch ID prompt so `op` can read the notarization password.
## Architecture
Keep it this small.
- `StickrCore`, a Swift package. All logic lives here: read WhatsApp data, model client, store, search, packs, WhatsApp export. No AppKit UI in it.
- `stickr`, a command line tool on top of `StickrCore`. Every feature is reachable here first. The tests and the computer-use agent use it.
- `Stickr.app`, a menu bar app (`LSUIElement`), Swift 6, AppKit, minimum macOS 14. Its windows are `WKWebView`s that show the screens from `mockup/`. Reasons: the approved design is reused as it is, and WebKit plays animated WebP, which AppKit image views do not.
- Bridge between web UI and Swift: one function, `window.stickr.call(method, params)`, that returns a Promise, built on `WKScriptMessageHandlerWithReply`. Sticker images load through a `WKURLSchemeHandler` as `stickr://sticker/<id>`. The web UI never calls OpenRouter itself and never sees the key.
- Store: one SQLite file in `~/Library/Application Support/Stickr/`, through GRDB. Vectors are `Float32` blobs. Search is a plain loop over all vectors with Accelerate. The only other dependency allowed is `libwebp`, and only if gate G3 demands it.
- Project file: generated with `xcodegen` from `project.yml`. Build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild`. Do not run `sudo xcode-select`.
### Data that must exist
Name the tables and columns as you see fit. This content is required:
- Sticker: stable ID (hash of the file bytes, so duplicates collapse), path of the private copy of the file, animated or still, pixel size, byte size, source (favorite, sent, received), times sent by the user, first seen, caption, text in image, mood, tags, emoji (up to 3), vector, state (waiting, read, failed), "edited by user" flag, model and provider that produced the row.
- Pack: name, rule sentence, rule vector, pinned sticker IDs in order, removed sticker IDs, member list at the last build.
- Pack install: pack, member list that was sent to WhatsApp, time, the pack ID that WhatsApp created.
- Settings: hotkey, schedule, base URL, caption model, routing choice, embedding model. The key is in the Keychain.
### Fixed behavior
- Stickr copies the WhatsApp databases with their `-wal` and `-shm` files to a temp folder and reads the copies. It copies sticker files into its own folder, so a WhatsApp cleanup can not break the library.
- Caption request: system prompt and JSON schema exactly as in `mockup/walkthrough.js` (`SYSTEM`, `SCHEMA`). Send the original file bytes as a data URL.
- Vector text: caption, text in image, mood, tags and emoji, joined with ". ". Function `docText` in the mockup.
- Search and pack cut: the z-score rule from "Verified facts". The numbers live in one place and `tests/search_cases.json` checks them.
- Pack order: pinned stickers first in their pinned order, then by times sent, then by similarity. At most 30. Still and animated stickers go into separate packs, named "<name>" and "<name> animated".
- Pack JSON for WhatsApp: `identifier`, `name`, `publisher` ("Stickr"), `tray_image` (base64 PNG, 96 x 96), `stickers` (each with base64 `image_data` and `emojis`), and `animated_sticker_pack: true` for animated packs. Add `accessibility_text` per sticker with the caption if gate G2 shows that WhatsApp accepts it.
- A sticker edited by the user is never overwritten by an automatic read.
- Errors: retry HTTP 429 and 5xx up to four times with a pause of 1.5 s, 3 s, 6 s, plus jitter. Every other error goes to the user in plain words, as in walkthrough step 12.
## Rules for the code and the UI
- Write the simplest code that meets the "Done when" list. No abstraction with a single user. No protocol with one implementation, except the model client, which needs a fake for tests.
- No dead code, no commented-out code, no TODO comments, no compatibility layers. Remove what is obsolete.
- Comments say why, not what. No doc comment that repeats a function name.
- Every module in `StickrCore` has unit tests that run offline against fixtures. Network tests are separate and need the key.
- Fixtures for the WhatsApp databases are built by a script from an empty schema plus a few invented rows. Never copy Luis's real chat database into the repository.
- UI: take `mockup/walkthrough.css` and the markup from `mockup/walkthrough.js` as they are. Remove only the parts that fake the desktop: `.stage`, `.menubar`, `.desk`, the fake window title bars, the fake WhatsApp window and the guide column. Do not add colors, fonts, radii, shadows, icons or animations. One accent color, one radius scale, system font, Phosphor icons bundled as local files. Light and dark mode both work.
- UI copy: plain sentences as in the walkthrough. No em-dashes, no exclamation marks, no marketing words, no raw error codes.
- Every screen has its empty, loading and error state, as the walkthrough shows.
- Commit after each passed phase with a message that says what now works. Do not push. There is no remote yet.
## Phase 0: finish the gates in the real WhatsApp app
The goal is to close the open questions before any app code exists. The computer-use agent is Codex with `tools/bin/wa-ui`. Build the tool first: `mkdir -p tools/bin && swiftc -O tools/wa-ui/main.swift -o tools/bin/wa-ui`.
Safety rule for every WhatsApp test in this plan: run `wa-ui open-self` first. `wa-ui` refuses to click, type or press while any chat other than "Message yourself" is open. Never work around this guard. If Luis uses WhatsApp at the same time, stop and try later.
Loop for the agent: `wa-ui shot reports/x.png`, look at the image, act with `wa-ui press`, `wa-ui click` or `wa-ui key`, take the next shot. Prefer `press` with a label over `click` with coordinates.
| Gate | Question | How to decide |
|---|---|---|
| G1 | Does a sticker that is sent from an installed Stickr pack arrive as a real sticker? | Open the tray (`wa-ui press send_stickers`), open the "Stickr test cats" tab, click a sticker. Then `wa-ui last-message` must print `type=15`. |
| G2 | Does the tray search find a Stickr sticker by its emoji? Does WhatsApp accept `accessibility_text`? | Build a test pack where one sticker has the emoji 🦖 and an `accessibility_text`. Import it. Type 🦖 into the tray search. Take a screenshot. Then search for a word from the text. |
| G3 | Does WhatsApp on the Mac enforce the iOS limits: still sticker at most 100 KB, animated at most 500 KB, 512 x 512 px, 3 to 30 stickers? | Import test packs that break one limit each. `mockup/stickers/s16.webp` is a still sticker of 137 KB. `s01.webp` is 320 px. |
| G4 | Does an animated pack import and play? | Pack of `s02`, `s17`, `s30` with `animated_sticker_pack: true`. |
| G5 | Can Stickr remove an installed pack by name through Accessibility? | Press `StickerBrowserView_StickerEditButton`, run `wa-ui ax "Stickr test cats"`, find the delete control, remove one of the two test packs. `wa-ui packs` must then show one row less. |
| G6 | Do installed packs sync to the iPhone? | Luis looks at the phone. |
Done when:
- `reports/phase-0.md` has one section per gate with the commands, the outputs and the screenshots, and a one-line verdict: yes, no, or blocked with the reason.
- This plan is edited where a gate result changes it. G3 "no limits enforced" removes every size check. G3 "limits enforced" means: leave such stickers out of packs and name them in the pack editor. G5 "no" removes the second permission from the app and keeps the two-click instruction. G6 "no" changes nothing in this version.
- All Stickr test packs are removed from WhatsApp again, by G5 or by hand.
## Phase 1: read the library
Build `StickrCore` and `stickr scan`.
- Find the WhatsApp container. Copy the databases. Collect favorites, stickers sent by the user and received stickers. Collapse duplicates by file hash. Count how often the user sent each sticker. Copy the files into Stickr's folder.
- `stickr scan` prints how many stickers are new, known and gone. A second run right after the first reports zero new.
- `stickr list --json` prints the library.
Done when:
- `swift test` passes offline, including: duplicate files collapse to one sticker; a missing WhatsApp folder gives the message from walkthrough step 12; a locked or half-written database copy does not crash the scan.
- On this Mac, `stickr scan` finds at least 122 favorites, and `stickr list --json | jq length` prints a number above 300.
- `ls -la` on the WhatsApp container shows no file changed by Stickr. Compare modification times before and after.
## Phase 2: let the model read the stickers
Build the model client, `stickr read`, `stickr read --retry-failed`, `stickr show <id>` and `stickr edit <id>`.
- Three requests at a time. Retries and routing as in "Fixed behavior". The run can be stopped with Ctrl-C and continues where it stopped.
- Vectors are requested in batches of up to 64 texts after the captions.
- Every request adds its reported cost to a monthly total. `stickr cost` prints it.
- `stickr test-connection` sends one sticker and prints caption, provider, seconds and cost. A wrong key, an empty balance and an unknown provider print the three messages from walkthrough step 3.
Done when:
- `swift test` passes offline with a fake model client: retry on 429, no retry on 401, resume after a stop, an edited sticker is not overwritten.
- With the real key: `stickr read --limit 40` ends with 40 read and 0 failed, and `stickr cost` prints less than 0.02 USD.
- `stickr test-connection --key sk-or-v1-wrong` prints "OpenRouter does not accept this key." and exits with a code other than 0.
- `grep -r "sk-or-" . --exclude-dir=.git --exclude=.env --exclude=PLAN.md` prints nothing.
## Phase 3: search and packs
Build `stickr find "<text>"`, `stickr pack add|list|show|build|pin|remove`.
- A search embeds the query once and caches the vector for the session.
- Without a network, `find` falls back to plain word match over caption, tags and text, and says so on stderr.
Done when:
- A test runs every case in `tests/search_cases.json` against the 40 stickers in `mockup/stickers` with the real models and passes. Tune only the two z values, and only if a case fails. Write the new values into the JSON and into "Verified facts".
- `stickr find "Stress wegen Abgabe"` prints the cortisol gauge first. `stickr find "qwertz nonsense zzz"` prints "No sticker fits that." and exits 0.
- `stickr pack show "Cats"` lists at most 30 stickers, pinned ones first. A removed sticker stays out after `stickr pack build`.
- A pack with still and animated members shows as two packs in `stickr pack show`.
## Phase 4: install packs into WhatsApp
Build `stickr pack install <name>` and `stickr pack status`.
- `install` builds the pack JSON, puts it on the pasteboard, opens `whatsapp://stickerPack`, starts WhatsApp first if needed, and records the member list. It restores the previous pasteboard content afterwards.
- `status` compares the current members with the installed members and prints "current", "changed: 2 added, 1 removed" or "not installed".
- After an install over an older copy, Stickr removes the older copy by name if gate G5 said yes. If not, it prints the two-click instruction.
Done when:
- Offline tests check the pack JSON against the rules in "Fixed behavior": at most 30, never mixed, tray icon 96 x 96 PNG, emoji present, stickers that break a limit from G3 left out and reported.
- The computer-use agent runs `stickr pack install "Cats"`, confirms the WhatsApp dialog in the self chat session, and `wa-ui packs` lists "Cats". Screenshot in the report.
- After pinning one more sticker, `stickr pack status` prints "changed". After a second install it prints "current", and `wa-ui packs` lists exactly one "Cats" when G5 said yes.
## Phase 5: the app
Build `Stickr.app` around `StickrCore` with the screens of the walkthrough, steps 2 to 6 and 9 to 12. Steps 7 and 8 happen in WhatsApp and need no Stickr UI.
- Menu bar item with the menu from step 11. No Dock icon. Starts at login by default (`SMAppService`).
- First start: permissions, then model, then first read, then results. Later starts open nothing.
- A timer runs scan, read and pack build on the schedule from Settings. When a pack changed, the menu bar item shows it and the "Keep packs current" window lists the packs.
- The search window opens with the global hotkey, default Option-Command-S, as a floating panel. Return copies the selected sticker to the pasteboard as a PNG picture. The footer says "copy as picture". Each result names its pack and position.
- The web UI gets all data through `window.stickr.call`. Port the scene code from `mockup/walkthrough.js`. Replace the OpenRouter calls and the sample data with bridge calls. Delete the sample mode.
Done when:
- Every line under "Must be true in the real app" in walkthrough steps 2 to 6 and 9 to 12 is checked by hand by the computer-use agent against the running app, with one screenshot per step in `reports/phase-5.md`. For the app windows use `screencapture` on the Stickr window.
- Each of the four failure states from step 12 was forced and photographed: wrong key in Settings, network off (`networksetup -setairportpower en0 off`, and on again after), container access denied, a search with no match.
- The app shows the same screens in light and dark mode without layout breaks. Two screenshots of the results screen.
- The key is in the Keychain: `security find-generic-password -s Stickr` finds it, and no file under `~/Library/Application Support/Stickr` contains `sk-or-`.
- `swift test` still passes.
## Phase 6: the DMG
- Build Release. Sign the app with "Developer ID Application: Luis William Kisters (4C8444267Z)", hardened runtime on, entitlements: none beyond what the app needs to run outside the sandbox. The app is not sandboxed, because it must read another app's container.
- `brew install create-dmg`. Make `Stickr.dmg` with the app on the left, an Applications link on the right, as in walkthrough step 1. Sign the DMG.
- Notarize with `xcrun notarytool submit --wait` and staple. Store the credentials once: `xcrun notarytool store-credentials stickr-notary --apple-id luis.w.kisters.services@gmail.com --team-id 4C8444267Z --password "$(op read 'op://Personal/iCloud notetakr-notarization/password')"`. This needs Luis for one Touch ID prompt. If the item has another field name, run `op item get "iCloud notetakr-notarization"` and use the right field.
- `scripts/release.sh` does all of it in one run and ends by printing the path of the DMG.
Done when:
- `spctl -a -t open --context context:primary-signature -v Stickr.dmg` prints "accepted" and "Notarized Developer ID".
- `xcrun stapler validate Stickr.dmg` prints "The validate action worked".
- The app, copied out of the mounted DMG into `/Applications` and started with `open`, shows the permissions screen. Screenshot in the report.
- If notarization is blocked because Luis is not there, the report says so at the top, and everything else in this phase is still done.
## Phase 7: the final test in WhatsApp
A fresh run of the whole user journey by the computer-use agent, with the app installed from the DMG. Start with `wa-ui open-self`. Stop at once if the guard refuses.
1. Remove Stickr's data folder and its Keychain item, so the app starts like new.
2. Go through first start: permissions, key, test connection, first read of the whole real library. Record the number of stickers, the failures and the cost.
3. Correct one sticker in the results screen. Check with `stickr show` that the edit was saved.
4. Create the pack "Cats" with the rule "Every sticker with a cat". Pin one sticker. Remove one.
5. Add the pack to WhatsApp. Confirm the dialog. `wa-ui packs` lists it.
6. In the self chat, open the tray, open the "Cats" tab, send one sticker. `wa-ui last-message` prints `type=15`.
7. Type an emoji that Stickr assigned into the tray search. The sticker shows up. Screenshot. Skip this step if gate G2 said no, and say so.
8. Search in the Stickr search window for "Stress wegen Abgabe" and for "we need to talk". Screenshots.
9. Pin another sticker, update the pack in WhatsApp, and check that exactly one "Cats" pack remains, or that Stickr showed the two-click instruction.
10. Remove the test pack from WhatsApp.
Done when:
- `reports/final.md` has the ten steps with pass or fail, the command outputs and the screenshots.
- Every fail has a cause and either a fix that was tested again, or a clear statement of what is blocked and by what.
- The self chat contains only stickers sent by this test. No other chat was opened.
## Later, not now
- iPhone: if gate G6 says packs do not sync, the same pack JSON works with the iOS import, which uses the same pasteboard type and URL. That needs a small iOS app and is a separate project.
- Sending a single sticker from the search window. It needs a path that WhatsApp does not offer today. Look again only when WhatsApp changes.
- Sparkle auto update, a website, sharing packs with friends.
