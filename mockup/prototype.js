/* Interactive Stickr mockup.
   Command-comma opens Settings and never the picker.
   The picker opens only from Option-Command-S, the menu, or the Find button.
   Groups are filed by the agent. The phone tray is the pack WhatsApp can actually install. */
(function () {
  const STICKERS = window.STICKERS;
  const NEAR = window.NEAR;
  const PACK_DEFS = [
    { id: "cats", name: "Cats", tags: ["cat"] },
    { id: "work", name: "Work stress", tags: ["cortisol", "typing", "late", "disappointed", "deadline", "busy", "sigh"] },
    { id: "react", name: "Reactions", tags: ["shocked", "side-eye", "skeptical", "thumbs up", "gasp", "suspicious", "unimpressed", "smug", "angry", "rage", "mad"] },
    { id: "party", name: "Weekend", tags: ["aperol", "dance", "cheers", "party", "celebrate", "silly", "drinks"] },
    { id: "soft", name: "Be nice", tags: ["comfort", "love", "shy", "praying", "cute", "heart"] },
  ];
  const META = {
    1: [8018, 320], 2: [53984, 512], 3: [305640, 512], 4: [4088, 512], 5: [79912, 512],
    6: [865898, 200], 7: [428848, 512], 8: [49520, 512], 9: [5996, 512], 10: [24164, 512],
    11: [10952, 512], 12: [91944, 512], 13: [144660, 512], 14: [16280, 512], 15: [7416, 512],
    16: [136834, 512], 17: [38916, 512], 18: [314276, 512], 19: [107318, 512], 20: [49422, 512],
    21: [311850, 512], 22: [52362, 512], 23: [8434, 512], 24: [8218, 512], 25: [10176, 512],
    26: [19828, 512], 27: [324648, 220], 28: [54136, 512], 29: [167740, 512], 30: [86300, 512],
    31: [476962, 512], 32: [34844, 512], 33: [24140, 512], 34: [746240, 341], 35: [11114, 512],
    36: [47868, 512], 37: [69958, 512], 38: [376992, 512], 39: [25956, 512], 40: [88046, 512],
  };
  const SUGGEST = {
    9: ["react", "It is someone laughing."],
    29: ["react", "It is a nerd face, close to a short reaction."],
    15: ["react", "It is waiting, hands on hips."],
    40: ["react", "It is a threat played as a joke."],
  };

  const state = {
    phase: "sort",
    lines: [],
    settle: false,
    groups: [],
    inbox: [],
    why: {},
    also: {},
    current: "cats",
    selected: [],
    anchor: null,
    pickerOpen: false,
    keepPicker: false,
    settingsOpen: false,
    front: "library",
    libraryOpen: true,
    pickerQuery: "",
    pickerIndex: 0,
    copied: false,
    hotkey: "option+command+s",
    schedule: "Every night",
    login: true,
    capturing: false,
    hotkeyError: "",
    lastAction: "",
    toast: "",
    undo: null,
    chat: [],
    phoneQuery: "",
    phonePack: null,
    added: false,
    confirming: false,
    dirty: false,
    autoSync: true,
    menuOpen: false,
    theme: "system",
    creating: false,
    steer: "",
    steerError: "",
    steerSkip: [],
    suggestLeft: [9, 29, 15, 40],
    names: {},
    rename: null,
    dragId: null,
  };

  const app = document.querySelector("#app");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let toastTimer = 0;
  let syncTimer = 0;
  let captureFn = null;

  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const sticker = (id) => STICKERS.find((s) => s.id === id);
  const src = (id) => `stickers/s${String(id).padStart(2, "0")}.webp`;
  const group = (id) => state.groups.find((g) => g.id === id);
  const label = (s) => state.names[s.id] || s.c.replace(/\.$/, "");
  const shortLabel = (s) => {
    const full = label(s);
    if (full.length <= 40) return full;
    return full.slice(0, 38).replace(/\s+\S*$/, "") + "…";
  };

  function iosReasons(s) {
    const [bytes, px] = META[s.id];
    const out = [];
    if (px !== 512) out.push(`${px} × ${px} px. The iPhone wants 512 × 512.`);
    const limit = s.a ? 500000 : 100000;
    if (bytes > limit) out.push(`${Math.round(bytes / 1000)} KB. ${s.a ? "Animated" : "Still"} stickers on the iPhone stop at ${s.a ? "500 KB" : "100 KB"}.`);
    return out;
  }

  function whyFor(s, pack) {
    if (pack.id === "cats") return "It shows a cat.";
    if (pack.id === "work" && s.t.includes("cortisol")) return "The gauge is about cortisol.";
    if (pack.id === "work") return "It is about work, a deadline, or running late.";
    if (pack.id === "react") return "It is a short reaction.";
    if (pack.id === "party") return "It is a drink, a dance, or a celebration.";
    return "It is comfort, affection, or asking nicely.";
  }

  function ensureManual(g) {
    if (g && !g.manual) {
      g.members = ordered(g);
      g.manual = true;
    }
  }

  function scorePacks(s) {
    const tags = new Set(s.t);
    return PACK_DEFS.map((p) => {
      let score = 0;
      for (const tag of p.tags) if (tags.has(tag)) score += p.id === "cats" ? 5 : 1;
      return { p, score };
    }).filter((x) => x.score > 0).sort((a, b) => b.score - a.score);
  }

  function buildInitial() {
    state.groups = PACK_DEFS.map((p) => ({ id: p.id, name: p.name, tags: p.tags.slice(), members: [], pins: [], removed: [], manual: false }));
    state.inbox = [];
    state.why = {};
    state.also = {};
    for (const s of STICKERS) {
      const ranked = scorePacks(s);
      if (!ranked.length) {
        state.inbox.push(s.id);
        state.why[s.id] = "Stickr is not sure where this goes.";
        state.also[s.id] = [];
        continue;
      }
      group(ranked[0].p.id).members.push(s.id);
      state.why[s.id] = whyFor(s, ranked[0].p);
      state.also[s.id] = ranked.slice(1).map((x) => x.p.id);
    }
    state.current = "cats";
  }

  function snapshot() {
    return JSON.stringify({
      groups: state.groups,
      inbox: state.inbox,
      why: state.why,
      also: state.also,
      dirty: state.dirty,
      current: state.current,
      names: state.names,
    });
  }

  function restore() {
    if (!state.undo) return;
    const data = JSON.parse(state.undo);
    Object.assign(state, data);
    state.undo = null;
    state.toast = "";
    state.rename = null;
  }

  function remember() { state.undo = snapshot(); }

  function homes(id) { return state.groups.filter((g) => g.members.includes(id)); }

  function isPinned(id) { return state.groups.some((g) => g.pins.includes(id)); }

  function detach(id) {
    state.inbox = state.inbox.filter((x) => x !== id);
    for (const g of state.groups) {
      g.members = g.members.filter((x) => x !== id);
      g.pins = g.pins.filter((x) => x !== id);
    }
  }

  function moveTo(id, groupId, { pin = false, why, keepOthers = false } = {}) {
    const dest = group(groupId);
    if (!dest || dest.removed.includes(id)) return false;
    if (keepOthers) {
      state.inbox = state.inbox.filter((x) => x !== id);
    } else {
      detach(id);
    }
    if (!dest.members.includes(id)) {
      if (pin && dest.manual) dest.members.unshift(id);
      else dest.members.push(id);
    }
    dest.removed = dest.removed.filter((x) => x !== id);
    if (pin && !dest.pins.includes(id)) dest.pins.push(id);
    if (why) state.why[id] = why;
    markDirty();
    return true;
  }

  function removeFrom(id, groupId) {
    const g = group(groupId);
    if (!g) return;
    g.members = g.members.filter((x) => x !== id);
    g.pins = g.pins.filter((x) => x !== id);
    if (!g.removed.includes(id)) g.removed.push(id);
    if (!homes(id).length && !state.inbox.includes(id)) state.inbox.push(id);
    state.why[id] = "You took it out of " + g.name + ". Stickr will not put it back.";
    markDirty();
  }

  function ordered(g) {
    if (g.manual) return g.members.filter((id) => g.members.includes(id));
    const pins = g.pins.filter((id) => g.members.includes(id));
    const rest = g.members.filter((id) => !g.pins.includes(id));
    return [...pins, ...rest];
  }

  function visibleIds() {
    if (state.current === "all") return STICKERS.map((s) => s.id);
    if (state.current === "inbox") return state.inbox.slice();
    const g = group(state.current);
    return g ? ordered(g) : [];
  }

  function reorderInCurrent(fromId, toId) {
    if (state.current === "all" || state.current === "inbox") return false;
    const g = group(state.current);
    if (!g) return false;
    if (!g.manual) {
      g.members = ordered(g);
      g.manual = true;
    }
    const ids = g.members.slice();
    const from = ids.indexOf(fromId);
    const to = ids.indexOf(toId);
    if (from < 0 || to < 0) return false;
    ids.splice(from, 1);
    ids.splice(to, 0, fromId);
    g.members = ids;
    g.pins = g.pins.filter((id) => id !== fromId);
    markDirty();
    return true;
  }

  function startRename(kind, id) {
    if (kind === "group" && (id === "inbox" || id === "all")) return;
    state.rename = { kind, id: kind === "sticker" ? Number(id) : id };
    render();
  }

  function commitRename(raw) {
    const r = state.rename;
    state.rename = null;
    if (!r) { render(); return; }
    const clean = String(raw ?? "").trim();
    if (clean) {
      if (r.kind === "group") {
        const g = group(r.id);
        if (g && g.name !== clean) {
          g.name = clean;
          markDirty();
        }
      } else if (r.kind === "sticker") {
        state.names[Number(r.id)] = clean;
        markDirty();
      }
    }
    render();
  }

  function phonePacks() {
    const out = [];
    for (const g of state.groups) {
      const fit = ordered(g).map(sticker).filter((s) => !iosReasons(s).length);
      const still = fit.filter((s) => !s.a).map((s) => s.id).slice(0, 30);
      const anim = fit.filter((s) => s.a).map((s) => s.id).slice(0, 30);
      const both = still.length >= 3 && anim.length >= 3;
      if (still.length >= 3) out.push({ id: g.id + "-still", name: g.name, groupId: g.id, members: still, animated: false });
      if (anim.length >= 3) out.push({ id: g.id + "-anim", name: both ? g.name + " animated" : g.name, groupId: g.id, members: anim, animated: true });
    }
    return out;
  }

  function plan(g) {
    const members = ordered(g).map(sticker);
    const left = members.filter((s) => iosReasons(s).length);
    const stillFit = members.filter((s) => !s.a && !iosReasons(s).length).length;
    const animFit = members.filter((s) => s.a && !iosReasons(s).length).length;
    const packs = [];
    if (stillFit >= 3 && animFit >= 3) packs.push(g.name, g.name + " animated");
    else if (stillFit >= 3) packs.push(g.name);
    else if (animFit >= 3) packs.push(g.name);
    return { left, stillFit, animFit, packs };
  }

  function planCopy(g) {
    const p = plan(g);
    if (!g.members.length) return { summary: "Nothing in this group yet.", detail: "" };
    const fit = (n, word) => n === 1 ? `1 ${word} sticker fits` : `${n} ${word} stickers fit`;
    const have = [p.stillFit ? fit(p.stillFit, "still") : "", p.animFit ? fit(p.animFit, "animated") : ""].filter(Boolean);
    let summary = have.length
      ? `The iPhone does not get this group yet. ${have.join(", and ")}. A pack needs 3 of one kind.`
      : "The iPhone does not get this group yet. None of these stickers fit the iPhone limits.";
    if (p.packs.length === 2) summary = `The iPhone gets two packs: ${p.packs[0]}, and ${p.packs[1]}.`;
    else if (p.packs.length === 1) summary = `The iPhone gets one pack: ${p.packs[0]}.`;
    const shown = p.left.slice(0, 2).map((s) => label(s) + ". " + iosReasons(s)[0]);
    const detail = shown.length ? "Left out: " + shown.join(" ") + (p.left.length > 2 ? ` ${p.left.length - 2} more are left out too.` : "") : "";
    return { summary, detail };
  }

  function offer(g) {
    const p = plan(g);
    const needStill = p.stillFit < 3;
    const needAnim = p.animFit < 3;
    if (!needStill && !needAnim) return null;
    const pool = STICKERS.filter((s) => !g.members.includes(s.id) && !g.removed.includes(s.id) && !iosReasons(s).length && s.t.some((t) => g.tags.includes(t)));
    const still = pool.filter((s) => !s.a);
    const anim = pool.filter((s) => s.a);
    const pick = needStill && p.stillFit + still.length >= 3 && still.length ? still : needAnim && p.animFit + anim.length >= 3 && anim.length ? anim : null;
    if (!pick) return null;
    const kind = pick[0].a ? "animated" : "still";
    const text = pick.length === 1
      ? `Also show this here: ${label(pick[0]).split(" ").slice(0, 7).join(" ")}`
      : `Also show ${pick.length} matching ${kind} stickers here`;
    return { ids: pick.map((s) => s.id), text };
  }

  function searchStickers(q) {
    const words = q.toLowerCase().split(/[^a-z0-9äöüß]+/).filter((w) => w.length > 2);
    if (!words.length) return [];
    const needles = new Set();
    for (const w of words) {
      needles.add(w);
      for (const [key, vals] of Object.entries(NEAR)) {
        if (key.includes(w) || w.includes(key)) vals.forEach((v) => needles.add(v.toLowerCase()));
      }
    }
    return STICKERS.map((s) => {
      const blob = `${s.c} ${s.t.join(" ")} ${s.e || ""} ${s.x || ""}`.toLowerCase();
      let score = 0;
      for (const n of needles) if (blob.includes(n)) score += n.length > 4 ? 2 : 1;
      return { s, score };
    }).filter((x) => x.score > 0).sort((a, b) => b.score - a.score || a.s.id - b.s.id);
  }

  function locate(id) {
    const found = homes(id);
    if (!found.length) return "Not in a group yet";
    return found.map((g) => `${g.name}, sticker ${ordered(g).indexOf(id) + 1}`).join(" · ");
  }

  function formatHotkey(v) {
    return v.replaceAll("option", "⌥").replaceAll("command", "⌘").replaceAll("control", "⌃").replaceAll("shift", "⇧").replaceAll("+", " ").toUpperCase();
  }

  function hotkeyEventMatches(e, value) {
    const parts = value.split("+");
    const letter = parts.at(-1);
    if (!letter || e.code !== "Key" + letter.toUpperCase()) return false;
    return !!e.metaKey === parts.includes("command")
      && !!e.altKey === parts.includes("option")
      && !!e.ctrlKey === parts.includes("control")
      && !!e.shiftKey === parts.includes("shift");
  }

  function toast(msg) {
    state.toast = msg;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { state.toast = ""; render(); }, 4200);
  }

  function markDirty() {
    state.dirty = true;
    if (!state.autoSync) return;
    clearTimeout(syncTimer);
    syncTimer = setTimeout(() => {
      if (!state.autoSync || !state.dirty) return;
      state.dirty = false;
      state.added = true;
      toast("Synced to WhatsApp.");
      render();
    }, 1100);
  }

  function openSettings(fromComma) {
    state.settingsOpen = true;
    state.libraryOpen = true;
    state.front = "library";
    state.menuOpen = false;
    state.lastAction = fromComma ? "comma" : "menu";
    render();
  }

  function openPicker() {
    state.pickerOpen = true;
    state.front = "picker";
    state.menuOpen = false;
    state.copied = false;
    state.pickerIndex = 0;
    state.lastAction = "picker";
    if (!state.libraryOpen) state.libraryOpen = true;
    render();
    document.querySelector("#pickerQuery")?.focus();
  }

  function copyResult(index) {
    const rows = searchStickers(state.pickerQuery);
    const row = rows[index];
    if (!row) return;
    state.copied = true;
    state.pickerIndex = index;
    toast("Copied " + label(row.s) + " as a picture.");
    if (!state.keepPicker) {
      state.pickerOpen = false;
    }
    render();
  }

  const STEER_STOP = new Set("put move every all the a an in into to with and sticker stickers group groups please my them those that this for of on from keep place send about belong belongs goes go fitting fits ones file filed auto add".split(" "));

  function steerForms(w) {
    const forms = [w];
    if (w.endsWith("ing") && w.length > 5) forms.push(w.slice(0, -3), w.slice(0, -1));
    if (w.endsWith("s") && w.length > 3) forms.push(w.slice(0, -1));
    if (w.endsWith("ed") && w.length > 4) forms.push(w.slice(0, -2), w.slice(0, -1));
    for (const extra of [...forms]) for (const x of NEAR[extra] || []) forms.push(x.toLowerCase());
    return forms.filter((f) => f.length >= 3);
  }

  // Stickers that fit the words and are not in the group yet. Mockup matching; the app uses embeddings.
  function steerMatches(g, text) {
    const nameWords = new Set(g.name.toLowerCase().split(/\s+/));
    const words = text.toLowerCase().split(/[^a-z0-9äöüß]+/).filter((w) => w.length > 2 && !STEER_STOP.has(w) && !nameWords.has(w));
    const forms = words.flatMap(steerForms);
    const add = [];
    let already = 0;
    if (!forms.length) return { words, add, already };
    for (const s of STICKERS) {
      if (g.removed.includes(s.id)) continue;
      const blob = `${s.c} ${s.t.join(" ")} ${s.e || ""} ${s.x || ""}`.toLowerCase();
      if (!forms.some((f) => blob.includes(f))) continue;
      if (g.members.includes(s.id)) already += 1;
      else add.push(s.id);
    }
    return { words, add, already };
  }

  function steerPreviewHtml(g) {
    const text = state.steer.trim();
    if (state.steerError) return `<p class="err">${esc(state.steerError)}</p>`;
    if (!text) return `<p class="hint">Describe what belongs in ${esc(g.name)}. Matching stickers show here before anything changes.</p>`;
    const m = steerMatches(g, text);
    if (!m.words.length) return `<p class="hint">Add a word that describes the pictures, such as laughing or cat.</p>`;
    if (!m.add.length) {
      return `<p class="hint">${m.already ? `All ${m.already} matching sticker${m.already === 1 ? " is" : "s are"} already here.` : "No sticker fits those words. Try another word."}</p>`;
    }
    const picked = m.add.filter((id) => !state.steerSkip.includes(id));
    const note = `${picked.length} of ${m.add.length} new${m.already ? ` · ${m.already} already here` : ""} · click one to leave it out`;
    return `<p class="hint">${esc(note)}</p><div class="steer-strip">${m.add.map((id) => {
      const s = sticker(id);
      const off = state.steerSkip.includes(id);
      return `<button type="button" class="cand${off ? " off" : ""}" data-act="steerSkip" data-id="${id}" aria-pressed="${!off}" title="${esc(label(s))}"><img src="${src(id)}" alt="${esc(label(s))}"></button>`;
    }).join("")}</div>`;
  }

  function steerCount(g) {
    const text = state.steer.trim();
    if (!text) return 0;
    return steerMatches(g, text).add.filter((id) => !state.steerSkip.includes(id)).length;
  }

  function steerButton(g) {
    const n = steerCount(g);
    return `<button class="btn pri" type="submit"${n ? "" : " disabled"}>${n ? `Add ${n} to ${esc(g.name)}` : "Add"}</button>`;
  }

  function paintSteer() {
    const g = group(state.current);
    const box = document.querySelector("#steerPreview");
    const btn = document.querySelector("#steerForm button[type=submit]");
    if (!g || !box || !btn) return;
    box.innerHTML = steerPreviewHtml(g);
    btn.outerHTML = steerButton(g);
    box.querySelectorAll("[data-act]").forEach((node) => {
      node.onclick = (event) => { event.stopPropagation(); actions[node.dataset.act]?.(node, event); };
    });
  }

  function applySteer() {
    const g = group(state.current);
    if (!g) return;
    if (!state.steer.trim()) {
      state.steerError = "Type words that describe the stickers first.";
      paintSteer();
      document.querySelector("#steer")?.focus();
      return;
    }
    const ids = steerMatches(g, state.steer).add.filter((id) => !state.steerSkip.includes(id));
    if (!ids.length) return;
    remember();
    for (const id of ids) moveTo(id, g.id, { keepOthers: true, why: `Added to ${g.name}: matches "${state.steer.trim()}".` });
    state.steer = "";
    state.steerSkip = [];
    toast(ids.length === 1 ? `Added 1 sticker to ${g.name}. It stays in its other groups too.` : `Added ${ids.length} stickers to ${g.name}. They stay in their other groups too.`);
    render();
  }

  function checkNew() {
    state.menuOpen = false;
    const next = state.suggestLeft.find((id) => state.inbox.includes(id) && SUGGEST[id] && !group(SUGGEST[id][0]).removed.includes(id));
    if (!next) {
      toast(state.inbox.length ? "No new stickers in WhatsApp. " + state.inbox.length + " still need a decision." : "No new stickers in WhatsApp.");
      render();
      return;
    }
    remember();
    const [gid, why] = SUGGEST[next];
    moveTo(next, gid, { why });
    state.suggestLeft = state.suggestLeft.filter((id) => id !== next);
    state.current = gid;
    state.selected = [next];
    toast("Filed 1 sticker in " + group(gid).name + ".");
    render();
  }

  function createGroup(name, sentence) {
    const clean = name.trim();
    if (!clean) return;
    if (state.groups.some((g) => g.name.toLowerCase() === clean.toLowerCase())) {
      state.steerError = "That group already exists.";
      state.creating = false;
      render();
      return;
    }
    const id = "g" + Math.random().toString(36).slice(2, 7);
    const tags = sentence.toLowerCase().split(/[^a-z0-9äöüß]+/).filter((w) => w.length > 2);
    state.groups.push({ id, name: clean, tags, members: [], pins: [], removed: [], manual: false });
    const chosen = state.selected.filter((sid) => sticker(sid));
    if (chosen.length) {
      remember();
      for (const sid of chosen) moveTo(sid, id, { pin: true, why: "You put it in " + clean + "." });
    } else if (tags.length) {
      remember();
      for (const s of STICKERS) {
        if (isPinned(s.id)) continue;
        const blob = `${s.c} ${s.t.join(" ")} ${s.e || ""}`.toLowerCase();
        if (tags.some((w) => blob.includes(w))) moveTo(s.id, id, { why: "The group sentence matched it." });
      }
    }
    state.current = id;
    state.creating = false;
    markDirty();
    render();
  }

  function onTileClick(id, event) {
    const ids = visibleIds();
    if (event.shiftKey && state.anchor != null) {
      const a = ids.indexOf(state.anchor);
      const b = ids.indexOf(id);
      const [lo, hi] = a < b ? [a, b] : [b, a];
      state.selected = ids.slice(lo, hi + 1);
    } else if (event.metaKey) {
      state.selected = state.selected.includes(id) ? state.selected.filter((x) => x !== id) : state.selected.concat(id);
      state.anchor = id;
    } else {
      state.selected = [id];
      state.anchor = id;
    }
    render();
  }

  function bind() {
    document.querySelectorAll("[data-act]").forEach((node) => {
      node.onclick = (event) => {
        event.stopPropagation();
        actions[node.dataset.act]?.(node, event);
      };
    });
    document.querySelectorAll("select[data-act]").forEach((node) => node.addEventListener("change", () => actions[node.dataset.act]?.(node)));
    document.querySelector("#steer")?.addEventListener("input", (event) => {
      state.steer = event.target.value;
      state.steerError = "";
      state.steerSkip = [];
      paintSteer();
    });
    // Handle the click here: the window's own click handler re-renders and would drop the submit.
    document.querySelector("#steerForm")?.addEventListener("click", (event) => {
      if (!event.target.closest("button[type=submit]")) return;
      event.preventDefault();
      event.stopPropagation();
      state.steer = document.querySelector("#steer")?.value || "";
      applySteer();
    });
    document.querySelector("#pickerQuery")?.addEventListener("input", (event) => {
      state.pickerQuery = event.target.value;
      state.pickerIndex = 0;
      state.copied = false;
      paintPickerResults();
    });
    document.querySelector("#phoneQuery")?.addEventListener("input", (event) => {
      state.phoneQuery = event.target.value;
      paintPhoneGrid();
    });
    document.querySelector("#newForm")?.addEventListener("submit", (event) => {
      event.preventDefault();
      createGroup(document.querySelector("#newName").value, document.querySelector("#newRule").value);
    });
    const log = document.querySelector(".wa-chat");
    if (log) log.scrollTop = log.scrollHeight;
    if (state.pickerOpen) document.querySelector("#pickerQuery")?.focus();
    document.querySelector(".result.on")?.scrollIntoView({ block: "nearest" });
    bindDnd();
    bindRename();
  }

  function bindRename() {
    document.querySelectorAll("[data-rename-id]").forEach((node) => {
      node.ondblclick = (event) => {
        event.preventDefault();
        event.stopPropagation();
        startRename(node.dataset.renameKind || "group", node.dataset.renameId);
      };
    });
    const input = document.querySelector(".rename-input");
    if (input) {
      input.onkeydown = (event) => {
        event.stopPropagation();
        if (event.key === "Enter") { event.preventDefault(); commitRename(input.value); }
        if (event.key === "Escape") { event.preventDefault(); state.rename = null; render(); }
      };
      input.onblur = () => { if (state.rename) commitRename(input.value); };
      input.focus();
      input.select();
    }
  }

  function bindDnd() {
    document.querySelectorAll(".tile[draggable='true']").forEach((node) => {
      node.ondragstart = (event) => {
        const id = Number(node.dataset.id);
        state.dragId = id;
        node.classList.add("dragging");
        event.dataTransfer.setData("text/plain", String(id));
        event.dataTransfer.effectAllowed = "move";
      };
      node.ondragend = () => {
        state.dragId = null;
        document.querySelectorAll(".dragging,.drop-on,.drop-before").forEach((n) => n.classList.remove("dragging", "drop-on", "drop-before"));
      };
    });
    document.querySelectorAll(".grid .tile").forEach((node) => {
      node.ondragover = (event) => {
        if (state.dragId == null) return;
        event.preventDefault();
        event.dataTransfer.dropEffect = "move";
        node.classList.add("drop-before");
      };
      node.ondragleave = () => node.classList.remove("drop-before");
      node.ondrop = (event) => {
        event.preventDefault();
        event.stopPropagation();
        node.classList.remove("drop-before");
        const from = Number(event.dataTransfer.getData("text/plain") || state.dragId);
        const to = Number(node.dataset.id);
        if (!from || !to || from === to) return;
        remember();
        if (reorderInCurrent(from, to)) {
          render();
        } else if (state.current !== "all" && state.current !== "inbox") {
          state.undo = null;
        }
      };
    });
    document.querySelectorAll(".gbtn[data-id]").forEach((node) => {
      const gid = node.dataset.id;
      node.ondragover = (event) => {
        if (state.dragId == null || gid === "inbox") return;
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
        node.classList.add("drop-on");
      };
      node.ondragleave = () => node.classList.remove("drop-on");
      node.ondrop = (event) => {
        event.preventDefault();
        node.classList.remove("drop-on");
        if (gid === "inbox" || gid === "all") return;
        const from = Number(event.dataTransfer.getData("text/plain") || state.dragId);
        if (!from || !group(gid)) return;
        const already = group(gid).members.includes(from) && homes(from).some((h) => h.id === gid);
        remember();
        if (already) {
          if (!reorderInCurrent(from, from)) {
            state.current = gid;
          }
          toast("Already in " + group(gid).name + ".");
        } else {
          moveTo(from, gid, { keepOthers: true, pin: true, why: "You dropped it into " + group(gid).name + "." });
          toast("Copied to " + group(gid).name + ". It stays in its other group too.");
        }
        state.current = gid;
        state.selected = [from];
        render();
      };
    });
  }

  const actions = {
    menu() { state.menuOpen = !state.menuOpen; render(); },
    find() { openPicker(); },
    settings() { openSettings(false); },
    comma() { openSettings(true); },
    closeSettings() { state.settingsOpen = false; state.front = "library"; render(); },
    closePicker() { state.pickerOpen = false; state.copied = false; state.front = "library"; render(); },
    closeLibrary() { state.libraryOpen = false; state.menuOpen = false; render(); },
    openLibrary() { state.libraryOpen = true; state.menuOpen = false; state.front = "library"; render(); },
    quit() { state.libraryOpen = false; state.settingsOpen = false; state.pickerOpen = false; state.menuOpen = false; render(); },
    group(node) {
      if (state.rename) return;
      if (state.current !== node.dataset.id) { state.steer = ""; state.steerError = ""; state.steerSkip = []; }
      state.current = node.dataset.id;
      state.selected = [];
      state.front = "library";
      render();
    },
    steerSkip(node) {
      const id = Number(node.dataset.id);
      state.steerSkip = state.steerSkip.includes(id) ? state.steerSkip.filter((x) => x !== id) : state.steerSkip.concat(id);
      paintSteer();
    },
    tile(node, event) { if (state.rename) return; onTileClick(Number(node.dataset.id), event); },
    pin() {
      const id = state.selected[0];
      const g = group(state.current);
      if (!g || !id) return;
      remember();
      if (g.pins.includes(id)) {
        g.pins = g.pins.filter((x) => x !== id);
        toast("Unpinned.");
      } else {
        g.pins = g.pins.concat(id);
        if (g.manual) {
          g.members = [id, ...g.members.filter((x) => x !== id)];
        }
        toast("Pinned. Stickr will leave it here.");
      }
      markDirty();
      render();
    },
    remove() {
      const id = state.selected[0];
      if (state.current === "inbox" || state.current === "all" || !id) return;
      remember();
      removeFrom(id, state.current);
      toast("Removed from " + group(state.current).name + ".");
      render();
    },
    move(node) {
      const id = state.selected[0];
      if (!id) return;
      remember();
      moveTo(id, node.dataset.id, { pin: true, why: "You moved it here." });
      state.current = node.dataset.id;
      toast("Moved to " + group(node.dataset.id).name + ".");
      render();
    },
    also(node) {
      const id = state.selected[0];
      if (!id) return;
      remember();
      moveTo(id, node.dataset.id, { pin: true, keepOthers: true, why: state.why[id] });
      toast("Also in " + group(node.dataset.id).name + ".");
      render();
    },
    takeOffer(node) {
      const g = group(state.current);
      const ids = node.dataset.ids.split(",").map(Number);
      remember();
      for (const id of ids) moveTo(id, g.id, { pin: true, keepOthers: true });
      toast(`Added ${ids.length} to ${g.name}. They stay in their other group too.`);
      render();
    },
    check() { checkNew(); },
    send(node) {
      state.chat.push(Number(node.dataset.id));
      render();
    },
    phonePack(node) { state.phonePack = node.dataset.id; state.phoneQuery = ""; render(); },
    undo() { restore(); render(); },
    create() { state.creating = true; state.menuOpen = false; render(); },
    cancelCreate() { state.creating = false; render(); },
    theme() {
      state.theme = state.theme === "system" ? "dark" : state.theme === "dark" ? "light" : "system";
      document.documentElement.dataset.theme = state.theme === "system" ? "" : state.theme;
      if (state.theme === "system") delete document.documentElement.dataset.theme;
      state.menuOpen = false;
      render();
    },
    login(node) { state.login = node.checked; },
    autoSync(node) {
      state.autoSync = node.checked;
      if (state.autoSync) markDirty();
      else clearTimeout(syncTimer);
      toast(state.autoSync ? "Auto-sync on. Pack changes push to WhatsApp." : "Auto-sync off. Changes wait until you turn it back on.");
      render();
    },
    keep(node) {
      state.keepPicker = node.checked;
      if (node.checked) state.pickerOpen = true;
      render();
    },
    schedule(node) { state.schedule = node.value; },
    capture() { startCapture(); },
    front(node) { state.front = node.dataset.front; render(); },
    result(node) { copyResult(Number(node.dataset.index)); },
  };

  function startCapture() {
    state.capturing = true;
    state.hotkeyError = "";
    render();
    captureFn = (event) => {
      event.preventDefault();
      event.stopPropagation();
      if (event.key === "Escape") { stopCapture(); return; }
      if (event.metaKey && event.key === "," && !event.altKey && !event.shiftKey && !event.ctrlKey) {
        state.hotkeyError = "Command-comma is Settings.";
        render();
        return;
      }
      const letter = /^Key([A-Z])$/.exec(event.code)?.[1].toLowerCase();
      if (!letter || !(event.metaKey || event.altKey || event.ctrlKey)) {
        if (letter) state.hotkeyError = "Use a letter with Command, Option, or Control.";
        render();
        return;
      }
      state.hotkey = [event.ctrlKey && "control", event.altKey && "option", event.shiftKey && "shift", event.metaKey && "command", letter].filter(Boolean).join("+");
      stopCapture();
    };
    window.addEventListener("keydown", captureFn, true);
  }

  function stopCapture() {
    state.capturing = false;
    if (captureFn) window.removeEventListener("keydown", captureFn, true);
    captureFn = null;
    render();
  }

  function inspector() {
    const ids = state.selected;
    if (!ids.length) return `<div class="hint">Select a sticker. Shift-click selects a run. Command-click adds one. Double-click renames. Drag tiles to reorder or onto a group in the sidebar to copy.</div>`;
    if (ids.length > 1) {
      return `<h3>${ids.length} stickers selected</h3><p class="hint">Make a group from the selection, or keep filing them one by one.</p><button class="btn pri" data-act="create">New group from these</button>`;
    }
    const s = sticker(ids[0]);
    const reasons = iosReasons(s);
    const here = state.current !== "inbox" && state.current !== "all" ? group(state.current) : null;
    const pinned = here?.pins.includes(s.id);
    const others = state.groups.filter((g) => g.id !== state.current && !g.members.includes(s.id) && !g.removed.includes(s.id));
    const also = (state.also[s.id] || []).map(group).filter((g) => g && !g.members.includes(s.id));
    const suggestion = state.current === "inbox" && SUGGEST[s.id] ? SUGGEST[s.id] : null;
    const renaming = state.rename?.kind === "sticker" && Number(state.rename.id) === s.id;
    const title = renaming
      ? `<input class="rename-input" value="${esc(label(s))}" aria-label="Rename sticker">`
      : `<h3 data-rename-kind="sticker" data-rename-id="${s.id}" title="Double-click to rename">${esc(shortLabel(s))}</h3>`;
    return `<div class="hero"><img src="${src(s.id)}" alt="${esc(label(s))}"></div>
      ${title}
      <p class="hint">${s.a ? "Animated" : "Still"} · ${META[s.id][1]} × ${META[s.id][1]} px · ${Math.round(META[s.id][0] / 1000)} KB · ${esc(s.e || "")}</p>
      <p>${esc(state.why[s.id] || "")}</p>
      ${reasons.length ? `<div class="note warn">Left out of the iPhone pack. ${esc(reasons.join(" "))}</div>` : `<div class="note">This file meets the iPhone limits.</div>`}
      ${suggestion ? `<button class="btn" data-act="move" data-id="${suggestion[0]}">Put in ${esc(group(suggestion[0]).name)}. ${esc(suggestion[1])}</button>` : ""}
      ${also.map((g) => `<button class="btn" data-act="also" data-id="${g.id}">Also show in ${esc(g.name)}</button>`).join("")}
      <div class="moves"><span class="lab">Move to</span>${others.map((g) => `<button class="btn" data-act="move" data-id="${g.id}">${esc(g.name)}</button>`).join("")}</div>
      ${here ? `<div class="row"><button class="btn" data-act="pin">${pinned ? "Unpin" : "Pin here"}</button><button class="btn" data-act="remove">Remove from ${esc(here.name)}</button></div>` : ""}`;
  }

  function gridPane() {
    if (state.current === "all") {
      const ids = visibleIds();
      return `<div class="gridhead"><h2>All stickers</h2><p>Every sticker Stickr can see. Drag one onto a group in the sidebar to copy it there. Double-click a tile to rename it.</p></div>
        <div class="grid">${ids.map((id, i) => tile(sticker(id), i)).join("")}</div>`;
    }
    if (state.current === "inbox") {
      const ids = state.inbox;
      return `<div class="gridhead"><h2>Needs a decision</h2><p>${ids.length ? "Stickr did not file these. Drag each one onto a group, or leave it out of WhatsApp." : "Every sticker is in a group."}</p></div>
        <div class="grid">${ids.map((id, i) => tile(sticker(id), i)).join("") || `<p class="hint">Nothing waiting.</p>`}</div>`;
    }
    const g = group(state.current);
    const copy = planCopy(g);
    const extra = offer(g);
    const renaming = state.rename?.kind === "group" && String(state.rename.id) === g.id;
    const title = renaming
      ? `<input class="rename-input" value="${esc(g.name)}" aria-label="Rename group">`
      : `<h2 data-rename-kind="group" data-rename-id="${g.id}" title="Double-click to rename">${esc(g.name)}</h2>`;
    return `<div class="gridhead">${title}<p>${esc(copy.summary)}</p>${copy.detail ? `<p class="detail">${esc(copy.detail)}</p>` : ""}
      ${extra ? `<button class="btn wrap" data-act="takeOffer" data-ids="${extra.ids.join(",")}">${esc(extra.text)}</button>` : ""}
      <form class="steer" id="steerForm">
        <label for="steer"><i class="ph ph-magic-wand"></i>Find stickers for ${esc(g.name)}</label>
        <div class="steer-row"><input id="steer" value="${esc(state.steer)}" placeholder="laughing, giggling, smile" autocomplete="off">${steerButton(g)}</div>
        <div id="steerPreview">${steerPreviewHtml(g)}</div>
      </form>
      </div><div class="grid">${ordered(g).map((id, i) => tile(sticker(id), i)).join("") || `<p class="hint">Nothing in this group yet. Describe what belongs here above, or drag stickers onto ${esc(g.name)} in the sidebar.</p>`}</div>`;
  }

  function tile(s, i) {
    const on = state.selected.includes(s.id);
    const g = state.current === "inbox" || state.current === "all" ? null : group(state.current);
    const pinned = g?.pins.includes(s.id);
    const blocked = iosReasons(s).length;
    return `<button class="tile${on ? " on" : ""}" style="--i:${i}" data-act="tile" data-id="${s.id}" aria-pressed="${on}" draggable="true" title="Drag to reorder or onto a group · Double-click to rename">
      <img src="${src(s.id)}" alt="${esc(label(s))}" draggable="false">
      ${pinned ? `<i class="ph ph-push-pin pin" aria-label="Pinned"></i>` : ""}
      ${blocked ? `<span class="flag">Left out</span>` : ""}
    </button>`;
  }

  function settingsPane() {
    const proof = state.lastAction === "comma"
      ? "Command-comma opens Settings here in the main window."
      : "Settings live in the main window. Command-comma jumps here and never opens the picker.";
    return `<div class="settings-pane pad">
        <p>${proof}</p>
        <div class="field"><span class="lab">Picker shortcut</span><div class="hot"><span class="tag" id="hotkeyLabel">${esc(formatHotkey(state.hotkey))}</span><button class="btn" data-act="capture">${state.capturing ? "Press a shortcut" : "Change"}</button></div>
          ${state.hotkeyError ? `<p class="err">${esc(state.hotkeyError)}</p>` : `<p class="hint">A letter with Command, Option, or Control. Command-comma stays Settings.</p>`}</div>
        <label class="check"><input type="checkbox" data-act="keep" ${state.keepPicker ? "checked" : ""}>Leave the picker open after a copy</label>
        <p class="hint">Off by default. Turning it on is the only way the picker stays on screen. It still will not open from Command-comma.</p>
        <label class="check"><input type="checkbox" data-act="autoSync" ${state.autoSync ? "checked" : ""}>Sync packs to WhatsApp automatically</label>
        <p class="hint">On by default. When a group changes, Stickr updates the WhatsApp packs for you — no button to press.</p>
        <div class="two"><div class="field"><label for="schedule">Check for new stickers</label><select id="schedule" data-act="schedule"><option>Every night</option><option>Every day</option><option>Every week</option><option>Manually</option></select></div>
          <label class="check"><input id="login" type="checkbox" data-act="login" ${state.login ? "checked" : ""}>Start Stickr when I log in</label></div>
        <div class="note">This mockup does not call a model. A read of these 40 stickers is about one cent with the default model. The key would live in the macOS Keychain.</div>
      </div>`;
  }

  function libraryChrome(title, actionsHtml, bodyHtml) {
    return `<section class="appwin" data-act="front" data-front="library">
      <header class="tbar"><div class="lights"><button class="close" data-act="closeLibrary" aria-label="Close"></button><button class="min" aria-label="Minimize" disabled></button><button class="zoom" aria-label="Zoom" disabled></button></div>
        <h1>${title}</h1>
        <div class="actions">${actionsHtml}</div>
      </header>
      ${bodyHtml}
    </section>`;
  }

  function library() {
    const syncBadge = state.dirty && state.autoSync
      ? `<span class="sync on"><i class="ph ph-arrows-clockwise"></i> Syncing…</span>`
      : `<span class="sync"><i class="ph ph-check-circle"></i> ${state.autoSync ? "In sync with WhatsApp" : "Auto-sync off"}</span>`;
    const actions = `<button class="btn" data-act="find"><i class="ph ph-magnifying-glass"></i>Find</button>
      <button class="btn${state.settingsOpen ? " pri" : ""}" data-act="${state.settingsOpen ? "closeSettings" : "settings"}"><i class="ph ph-gear"></i>${state.settingsOpen ? "Library" : "Settings"}</button>`;
    if (state.settingsOpen) {
      return libraryChrome("Settings", actions, settingsPane());
    }
    return libraryChrome("Library", actions, `<div class="body">
        <aside class="side">
          <h2>Groups</h2>
          <nav>
            <button class="gbtn${state.current === "all" ? " on" : ""}" data-act="group" data-id="all">All stickers<b>${STICKERS.length}</b></button>
            ${state.groups.map((g) => {
              if (state.rename?.kind === "group" && String(state.rename.id) === g.id) {
                return `<div class="gbtn on renaming"><input class="rename-input" value="${esc(g.name)}" aria-label="Rename group"><b>${g.members.length}</b></div>`;
              }
              return `<button class="gbtn${state.current === g.id ? " on" : ""}" data-act="group" data-id="${g.id}" data-rename-id="${g.id}" data-rename-kind="group" title="Double-click to rename">${esc(g.name)}<b>${g.members.length}</b></button>`;
            }).join("")}
            <div class="rule"></div>
            <button class="gbtn${state.current === "inbox" ? " on" : ""}" data-act="group" data-id="inbox">Needs a decision<b>${state.inbox.length}</b></button>
            <button class="newg" data-act="create"><i class="ph ph-folder-plus"></i><span>New group</span></button>
          </nav>
        </aside>
        <div class="gridwrap${state.settle ? " settle" : ""}">${gridPane()}</div>
        <aside class="inspector">${inspector()}</aside>
      </div>
      <footer class="foot">${syncBadge}<span class="sp"></span><span>${state.groups.length} groups · ${state.inbox.length} undecided</span></footer>`);
  }

  function sorting() {
    return `<section class="appwin"><header class="tbar"><div class="lights"><span class="close"></span></div><h1>Library</h1></header>
      <div class="sort"><h2>Sorting 40 stickers</h2><ul>${state.lines.map((line) => `<li>${esc(line)}</li>`).join("")}</ul></div></section>`;
  }

  function pickerResultsHtml() {
    const rows = searchStickers(state.pickerQuery);
    if (!state.pickerQuery.trim()) return `<p class="hint" style="padding:16px">Describe a feeling or a picture, in German or English.</p>`;
    if (!rows.length) return `<p class="hint" style="padding:16px">No sticker fits that.</p>`;
    return rows.map((row, i) => `<button class="result${i === state.pickerIndex ? " on" : ""}" data-act="result" data-index="${i}"><img src="${src(row.s.id)}" alt=""><span><b>${esc(label(row.s))}</b><small>${esc(locate(row.s.id))}</small></span></button>`).join("");
  }

  function paintPickerResults() {
    const box = document.querySelector(".picker .results");
    if (!box) return;
    box.innerHTML = pickerResultsHtml();
    box.querySelectorAll("[data-act]").forEach((node) => {
      node.onclick = (event) => { event.stopPropagation(); actions[node.dataset.act]?.(node, event); };
    });
  }

  function paintPhoneGrid() {
    const packs = phonePacks();
    const pack = packs.find((p) => p.id === state.phonePack) || packs[0];
    const q = state.phoneQuery.trim().toLowerCase();
    const members = (pack?.members || []).map(sticker).filter((s) => !q || `${s.c} ${s.t.join(" ")} ${s.e || ""}`.toLowerCase().includes(q));
    const box = document.querySelector(".tray .g");
    if (!box) return;
    box.innerHTML = members.map((s) => `<button data-act="send" data-id="${s.id}" aria-label="${esc(label(s))}"><img src="${src(s.id)}" alt=""></button>`).join("")
      || `<p class="hint" style="grid-column:1/-1;padding:8px">Nothing in this pack matches.</p>`;
    box.querySelectorAll("[data-act]").forEach((node) => {
      node.onclick = (event) => { event.stopPropagation(); actions[node.dataset.act]?.(node, event); };
    });
  }

  function picker() {
    return `<section class="picker" role="dialog" aria-label="Find a sticker">
      <input class="search" id="pickerQuery" placeholder="Find a sticker" value="${esc(state.pickerQuery)}" autocomplete="off" aria-label="Find a sticker">
      <div class="results">${pickerResultsHtml()}</div>
      <footer class="foot"><span>${state.copied ? "Copied as a picture. Sending stays in WhatsApp." : "↑↓ choose · Return copies as a picture · Esc closes"}</span><button class="btn text" data-act="closePicker">Close</button></footer>
    </section>`;
  }

  function phone() {
    const packs = phonePacks();
    if (state.phonePack && !packs.some((p) => p.id === state.phonePack)) state.phonePack = packs[0]?.id || null;
    if (!state.phonePack) state.phonePack = packs[0]?.id || null;
    const pack = packs.find((p) => p.id === state.phonePack);
    const q = state.phoneQuery.trim().toLowerCase();
    const members = (pack?.members || []).map(sticker).filter((s) => !q || `${s.c} ${s.t.join(" ")} ${s.e || ""}`.toLowerCase().includes(q));
    const status = !packs.length
      ? "No pack fits the iPhone yet."
      : !state.autoSync
        ? "Auto-sync is off. Turn it on in Settings."
        : state.dirty
          ? "Syncing changes from Stickr…"
          : "In sync with Stickr. Updates push automatically.";
    return `<div class="phonewrap"><p>WhatsApp on iPhone</p><div class="phone"><div class="screen">
      <header class="wa-head"><i class="ph ph-caret-left"></i><span>Notizen<small>${esc(status)}</small></span></header>
      <div class="wa-chat">${state.chat.length ? state.chat.map((id) => `<div class="bubble"><img src="${src(id)}" alt="${esc(label(sticker(id)))}"></div>`).join("") : `<div class="empty">Tap a sticker in the tray to send it in this chat.</div>`}</div>
      <div class="tray"><label class="q"><input id="phoneQuery" value="${esc(state.phoneQuery)}" placeholder="Search this pack" aria-label="Search this pack" autocomplete="off"></label>
        <div class="g">${members.map((s) => `<button data-act="send" data-id="${s.id}" aria-label="${esc(label(s))}"><img src="${src(s.id)}" alt=""></button>`).join("") || `<p class="hint" style="grid-column:1/-1;padding:8px">Nothing in this pack matches.</p>`}</div>
        <div class="tabs">${packs.map((p) => `<button class="${p.id === state.phonePack ? "on" : ""}" data-act="phonePack" data-id="${p.id}" aria-label="${esc(p.name)}"><img src="${src(p.members[0])}" alt=""></button>`).join("")}</div>
      </div>
      <div class="composer">Message</div>
    </div></div></div>`;
  }

  function menu() {
    const theme = state.theme === "dark" ? "Use light appearance" : state.theme === "light" ? "Use system appearance" : "Use dark appearance";
    return `<div class="menu" role="menu">
      <div class="mute">${STICKERS.length} stickers · ${phonePacks().length} packs fit the iPhone</div><hr>
      <button data-act="find">Find a sticker <kbd>${esc(formatHotkey(state.hotkey))}</kbd></button>
      <button data-act="openLibrary">Groups</button>
      <button data-act="check">Check for new stickers</button>
      <button data-act="theme">${theme}</button>
      <hr>
      <button data-act="comma">Settings <kbd>⌘,</kbd></button>
      <button data-act="quit">Close windows</button>
    </div>`;
  }

  function render() {
    const focus = document.activeElement;
    const focusId = focus?.id;
    const caret = focus?.selectionStart;
    const open = state.libraryOpen || state.phase === "sort";
    app.innerHTML = `<header class="menubar"><span class="brand">Stickr mockup</span><span class="sp"></span>
      <button class="status" data-act="menu" aria-expanded="${state.menuOpen}" aria-label="Stickr menu"><span class="mark"><i class="ph ph-smiley"></i></span>Stickr</button>
      ${state.menuOpen ? menu() : ""}</header>
      <main class="desk" data-front="${state.front}">
        ${state.phase === "sort" ? sorting() : open ? library() : `<div class="quiet"><b>Stickr is in the menu bar.</b><p>Open Groups from the Stickr menu. The picker stays closed until you ask for it.</p><button class="btn pri" data-act="openLibrary">Open Groups</button></div>`}
        ${phone()}
        ${state.pickerOpen ? picker() : ""}
        ${state.creating ? `<div class="sheet"><form id="newForm"><h2>New group</h2><div class="field"><label for="newName">Name</label><input id="newName" autocomplete="off"></div><div class="field"><label for="newRule">What belongs here</label><input id="newRule" placeholder="Optional. Leave blank to use the selection." autocomplete="off"></div><div class="row"><button class="btn" type="button" data-act="cancelCreate">Cancel</button><button class="btn pri" type="submit">Create</button></div></form></div>` : ""}
        ${state.toast ? `<div class="toast" role="status">${esc(state.toast)}${state.undo ? `<button type="button" data-act="undo">Undo</button>` : ""}</div>` : ""}
      </main>`;
    const schedule = document.querySelector("#schedule");
    if (schedule) schedule.value = state.schedule;
    bind();
    if (state.creating) document.querySelector("#newName")?.focus();
    else if (focusId && document.getElementById(focusId)) {
      const el = document.getElementById(focusId);
      el.focus();
      if (caret != null && el.setSelectionRange) el.setSelectionRange(caret, caret);
    }
  }

  document.addEventListener("click", (event) => {
    if (!state.menuOpen) return;
    if (event.target.closest(".menu") || event.target.closest(".status")) return;
    state.menuOpen = false;
    render();
  });

  window.addEventListener("keydown", (event) => {
    if (state.capturing) return;
    if (event.metaKey && event.code === "Comma" && !event.altKey && !event.shiftKey && !event.ctrlKey) {
      event.preventDefault();
      openSettings(true);
      return;
    }
    if (hotkeyEventMatches(event, state.hotkey)) {
      event.preventDefault();
      openPicker();
      return;
    }
    if (event.key === "Escape") {
      if (state.rename) {
        state.rename = null;
        render();
        return;
      }
      if (state.menuOpen) {
        state.menuOpen = false;
        render();
        return;
      }
      if (state.creating) {
        state.creating = false;
        render();
        return;
      }
      if (state.pickerOpen) {
        state.pickerOpen = false;
        state.copied = false;
        state.front = "library";
        render();
        return;
      }
      if (state.settingsOpen) {
        state.settingsOpen = false;
        state.front = "library";
        render();
        return;
      }
      return;
    }
    if (!state.pickerOpen) return;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      const n = searchStickers(state.pickerQuery).length;
      if (!n) return;
      event.preventDefault();
      state.pickerIndex = (state.pickerIndex + (event.key === "ArrowDown" ? 1 : -1) + n) % n;
      paintPickerResults();
      document.querySelector(".result.on")?.scrollIntoView({ block: "nearest" });
    }
    if (event.key === "Enter" && document.activeElement?.id === "pickerQuery") {
      event.preventDefault();
      copyResult(state.pickerIndex);
    }
  }, true);

  buildInitial();
  if (reduce) {
    state.phase = "app";
    render();
  } else {
    const lines = state.groups.map((g) => `${g.name}, ${g.members.length}`).concat([`${state.inbox.length} need a decision`]);
    render();
    lines.forEach((line, i) => {
      setTimeout(() => {
        state.lines.push(line);
        if (i === lines.length - 1) setTimeout(() => {
          state.phase = "app";
          state.settle = true;
          render();
          setTimeout(() => {
            state.settle = false;
            document.querySelector(".gridwrap")?.classList.remove("settle");
          }, 700);
        }, 320);
        else render();
      }, 180 * (i + 1));
    });
  }
})();
