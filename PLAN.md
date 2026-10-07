# Stickr: mockup approval and implementation plan
The review artifact is [the interactive prototype](mockup/prototype.html). It uses 40 local sample stickers and simulates WhatsApp on an iPhone. It does not read WhatsApp, call a model, install a pack, or send a message. [The older walkthrough](mockup/walkthrough.html) is supporting context; the prototype is the current design candidate.
## Approval gate
1. Review the prototype in a browser. Check the library, groups, sticker inspector, sentence sorting, new group flow, pack preview, search picker, menu, and settings in light and dark mode.
2. Decide whether the prototype is the design to build. Settle these product choices before app work: manual group filing versus saved meaning rules; whether the iPhone view is a preview or a promised sync result; and how optional WhatsApp cleanup is presented.
3. Wait for Luis to say to build the app. Until then, make mockup and plan changes only. Do not run WhatsApp tests, publish code, or release a build.
## What the approved app must do
1. Read copies of the WhatsApp sticker databases and copy sticker files into Stickr storage. Never change WhatsApp files. Show permission state in the main app window; keep the window visible after opening macOS Settings. When access succeeds, replace “Allow access” with a clear allowed state.
2. Describe stickers once with the configured OpenAI-compatible service and store captions, text, mood, tags, emoji, and vectors. Keep the key in Keychain. Limit model work to three concurrent requests. Retry temporary errors. Never overwrite a user edit during an automatic read.
3. Show the library and groups in the approved layout. Support selection, pin, remove, move, show in another group, undo, a group created from a selection or sentence, and a clear “Needs a decision” list. Explain why a sticker was filed or left out.
4. Search by meaning in German and English. The global shortcut opens the picker. Command-comma opens Settings. Return copies the chosen sticker as a picture, with that behavior named in the UI. The result shows its group and position. Provide a word-match fallback when the model service is unavailable.
5. Build valid still and animated packs separately. Show what fits the iPhone limits and why a sticker is omitted. Import each pack through WhatsApp’s official sticker-pack interface with one confirmation at a time. Do not imply that a pack was installed before WhatsApp confirms it. Do not silently replace an old pack.
6. Keep background work quiet: one scheduled check at the selected interval, tolerance for coalescing, no busy polling, and utility priority. Start at login only when the user setting permits it.
7. Match the approved mockup in system light and dark modes, at the intended Mac window size. Support keyboard operation, visible focus, VoiceOver labels, and reduced motion. The prototype’s iPhone view is a design preview unless real device sync is verified.
## Build and verification after approval
1. Compare the current Swift code with the approved prototype. Reuse code that meets it; replace mismatched UI and behavior. Build with at most two Xcode jobs to limit CPU load. Run the Swift tests and meaningful integration checks.
2. Test every visible action through native computer use. Only interact with WhatsApp after a guard confirms the open chat is “Notizen”. If the guard cannot confirm it, stop WhatsApp testing and use app-only checks. If a test message lands in any other chat, delete it immediately.
3. Verify one real sticker sent from an installed pack has WhatsApp message type 15. Check native tray search and pack counts. Record any iPhone sync claim only after a device check.
4. Build a Developer ID signed app and DMG with a secure timestamp, notarize and staple the DMG, then verify it with `spctl` and `stapler`. Install it from the DMG and test the installed app.
5. Create a private GitHub repository and publish the first stable GitHub release with the verified DMG and its SHA-256 file. Do this only after approval and the checks above.
## Current state
The repository already contains an unapproved Swift implementation and a local signed, notarized DMG from work done too early. The app has been quit. Nothing has been pushed or published. The prototype and this plan are the items for review now; the existing app is parked until approval.
