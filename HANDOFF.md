# Stickr handoff

## Where things are
- Worktree (source of truth): `/Users/kisters/.t3/worktrees/stickr/t3code-b5f79a4c`
- Primary checkout (kept in sync for mockup files): `/Users/kisters/code/projects/stickr`
- Mockup served at `http://localhost:4173/prototype.html` (`python3 -m http.server 4173 -d mockup` from the worktree). Preview browser blocks `file://`; use this URL.
- Real app: `Sources/StickrApp/` + `Resources/Web/` (copied into the worktree; mostly uncommitted).

## Mockup status (current)
Done in `mockup/prototype.js` / `prototype.css`:
- Double-click rename: sidebar groups, grid title, inspector title, tiles.
- **All stickers** group at top of sidebar (count = full library).
- Drag tiles: reorder inside a group; drop on a sidebar group = **copy** (stays in the old group).
- Settings is a **pane in the main window** (gear toggles Library ↔ Settings); no floating window. ⌘, opens the pane.
- Footer “Add to WhatsApp” **removed**. Status line only: In sync / Syncing…
- **Auto-sync to WhatsApp is ON by default** (`state.autoSync`). Mutations call `markDirty()` → ~1.1s → toast “Synced to WhatsApp.” Toggle in Settings: “Sync packs to WhatsApp automatically”.
- New group button has a folder-plus icon.

### Find stickers for a group (replaces sidebar Auto-file)
- Lives in the gridhead of an open group (`#steerForm`, `steerMatches()` / `applySteer()` in `prototype.js`). Not shown on All stickers / Needs a decision.
- Live preview while typing: candidate thumbnails (click to leave one out), count, "N already here". Button reads `Add N to {group}`, disabled at 0.
- Adds as copies (stays in other groups), toast with Undo. No "future stickers" claim until group rules exist.
- Submit is handled on click with `stopPropagation`: the `.appwin` `data-act="front"` handler re-renders and dropped the old form submit.
- Real app must wire the same flow to embeddings/`ModelClient` (mockup uses `NEAR` + substring only).

## Still open (from preview annotations + earlier plan)
- Group settings pane: description of what belongs + auto-scan-on-new-stickers toggle; explain “Left out” copy in gridhead.
- Shorter tile titles generally (code-side captions); inspector already clamps via `shortLabel`.
- Funny AI captions/tags/character groups + AI pack naming (`ModelClient.swift` prompt rework).
- Embeddings behind Auto-file / steer in the **real** app (`Search`/`ModelClient.embed`); mockup is fake.
- Find button polish; Find = in-app search, global hotkey stays the picker (⌥⌘S).
- Settings as tab in real `Resources/Web/app.js` (mirror mockup pane).
- Cmd+S must never open settings globally (`AppMain.swift` hotkey audit).
- WhatsApp install: prefer direct DB write if safe (spike); fallback pasteboard deep-link; auto-reinstall on pack change.
- Prototype vs real app parity for all of the above (user wants **both**).

## Constraints
- Do not treat localhost-only workflows as done if files diverge; after mockup edits, copy `prototype.*` to the primary checkout too.
- Phosphor icons already loaded via unpkg in `prototype.html`.
- Packs/groups: sidebar rename only; pack rename in real app needs Store id migration (name-keyed today).
