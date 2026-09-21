/* Stickr walkthrough. Sample data is used until an OpenRouter key is entered in step 3.
   With a key, captions, emoji tags, search and pack rules all run on the real models. */
const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];
const S = window.STICKERS, NEAR = window.NEAR, PACKS = window.PACKS;
const CAPTION_MODEL = "z-ai/glm-5.3-flash", CAPTION_PROVIDER = "baseten-first", EMBED_MODEL = "baai/bge-m3";
const API = "https://openrouter.ai/api/v1/";
S.forEach(s => s.src = `stickers/s${String(s.id).padStart(2, "0")}.webp`);
const byId = id => S.find(s => s.id === id);
const esc = t => String(t ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

/* ---------- state ---------- */
const EMOJI_BY_TAG = { cat: "🐱", dog: "🐶", cortisol: "😰", stress: "😰", typing: "💻", late: "⏰", shocked: "😱", love: "😍", heart: "❤️", dance: "💃", party: "🥳", aperol: "🍹", angry: "😡", smug: "😏", "side-eye": "👀", skeptical: "🤨", "thumbs up": "👍", nerd: "🤓", comfort: "🫂", shy: "🥺", silly: "🤪", praying: "🙏", disappointed: "😞", serious: "😐", radar: "📡", chair: "🪑", evil: "😈", laughing: "😂" };
const sampleEmojis = s => [...new Set(s.t.map(t => EMOJI_BY_TAG[t]).filter(Boolean))].slice(0, 3);
let IDX = JSON.parse(localStorage.getItem("stickr.idx.v2") || "{}");   // real results, keyed by sticker id
const save = () => localStorage.setItem("stickr.idx.v2", JSON.stringify(IDX));
const rec = s => IDX[s.id] || { c: s.c, x: s.x || "", e: s.e, t: s.t, em: sampleEmojis(s), sample: true };
const key = () => sessionStorage.getItem("stickr.key") || "";
const live = () => !!key() && S.every(s => IDX[s.id]?.vec);
const flagged = s => { const r = rec(s); return r.failed || r.t.length < 3 || !r.em.length; };
const isAnimated = s => !!s.a;
let spend = +localStorage.getItem("stickr.spend") || 0;
const addSpend = c => { spend += c || 0; localStorage.setItem("stickr.spend", spend); };

/* ---------- OpenRouter ---------- */
const ROUTES = { "baseten-first": { order: ["baseten"], allow_fallbacks: true }, "baseten": { only: ["baseten"] } };
const sleep = ms => new Promise(f => setTimeout(f, ms));
async function or(path, body, k = key(), tries = 4) {   // rate limits and server errors are retried with a growing pause
  for (let n = 0; ; n++) { try { return await orOnce(path, body, k); } catch (e) { if (n >= tries - 1 || !(e.status === 429 || e.status >= 500)) throw e; await sleep(1500 * 2 ** n + Math.random() * 500); } }
}
async function orOnce(path, body, k) {
  const r = await fetch(API + path, { method: "POST", headers: { Authorization: "Bearer " + k, "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const d = await r.json().catch(() => ({}));
  if (!r.ok || d.error) throw Object.assign(new Error(d.error?.message || "Request failed"), { status: r.status });
  return d;
}
const SCHEMA = { type: "object", additionalProperties: false, required: ["caption", "text_in_image", "mood", "tags", "emojis"], properties: {
  caption: { type: "string" }, text_in_image: { type: "string" }, mood: { type: "string" },
  tags: { type: "array", items: { type: "string" } }, emojis: { type: "array", items: { type: "string" } } } };
const SYSTEM = "You describe chat stickers for a search index. Answer in English. caption: one plain sentence on what is shown. text_in_image: the exact visible text, or an empty string. mood: one word. tags: 4 to 8 lowercase words for the feelings and situations in which someone sends this sticker. emojis: 1 to 3 emoji a person would type to find this sticker.";
async function b64(url) { const b = await (await fetch(url)).blob(); return new Promise(r => { const f = new FileReader(); f.onload = () => r(f.result); f.readAsDataURL(b); }); }
async function caption(s, k = key(), provider = CAPTION_PROVIDER, model = CAPTION_MODEL) {
  const t0 = performance.now();
  const d = await or("chat/completions", { model, ...(ROUTES[provider] ? { provider: ROUTES[provider] } : {}), reasoning: { effort: "low" }, max_tokens: 1200,
    response_format: { type: "json_schema", json_schema: { name: "sticker", strict: true, schema: SCHEMA } },
    messages: [{ role: "system", content: SYSTEM }, { role: "user", content: [{ type: "image_url", image_url: { url: await b64(s.src) } }] }] }, k);
  const j = JSON.parse(d.choices[0].message.content);
  addSpend(d.usage?.cost);
  return { c: j.caption, x: j.text_in_image, e: j.mood, t: j.tags.slice(0, 8), em: j.emojis.slice(0, 3), provider: d.provider, secs: (performance.now() - t0) / 1000, cost: d.usage?.cost || 0 };
}
const docText = r => [r.c, r.x, r.e, r.t.join(" "), r.em.join(" ")].filter(Boolean).join(". ");
async function embed(texts) { const d = await or("embeddings", { model: EMBED_MODEL, input: texts }); addSpend(d.usage?.cost); return d.data.map(x => x.embedding.map(v => +v.toFixed(4))); }
const cos = (a, b) => { let d = 0, x = 0, y = 0; for (let i = 0; i < a.length; i++) { d += a[i] * b[i]; x += a[i] * a[i]; y += b[i] * b[i]; } return d / Math.sqrt(x * y); };
const qcache = new Map();
async function qvec(q) { if (!qcache.has(q)) qcache.set(q, (await embed([q]))[0]); return qcache.get(q); }

/* ---------- search: real vectors when indexed, word list otherwise ---------- */
const STOP = new Set("we you he she it they the a an to of for and or is are am be i me my your need want with that this when about so too very in on at ich du wir der die das ein eine und ist zu mit".split(" "));
function wordScore(s, q) {
  const ws = q.toLowerCase().split(/[^a-zäöüß0-9']+/).filter(w => w.length > 1 && !STOP.has(w)); if (!ws.length) return 0;
  const r = rec(s), hay = (r.c + " " + r.x + " " + r.e).toLowerCase(), tags = r.t.join(" "); let sc = 0;
  for (const w of ws) { const st = w.replace(/(ing|ed|s)$/, "");
    if (tags.includes(w) || tags.includes(st)) sc += 1; else if (hay.includes(w) || (st.length > 3 && hay.includes(st))) sc += .8;
    for (const n of (NEAR[w] || NEAR[st] || [])) if (tags.includes(n) || hay.includes(n)) sc += .55; }
  return sc / ws.length;
}
/* A hit must stand out from the rest of the library for this query. The cut is a z-score, so it works the same for German and English. */
async function search(q, cap = 15, z = 2) {
  if (live()) { const v = await qvec(q), sc = S.map(s => [s, cos(v, IDX[s.id].vec)]).sort((a, b) => b[1] - a[1]);
    const mean = sc.reduce((a, x) => a + x[1], 0) / sc.length, sd = Math.sqrt(sc.reduce((a, x) => a + (x[1] - mean) ** 2, 0) / sc.length) || 1;
    return sc.filter(x => (x[1] - mean) / sd >= z).slice(0, cap).map(x => x[0]); }
  return S.map(s => [s, wordScore(s, q)]).filter(x => x[1] >= .4).sort((a, b) => b[1] - a[1]).slice(0, cap).map(x => x[0]);
}
async function members(p) {
  const pins = (p.pins || []).map(byId), out = p.out || [];
  let auto = p.rule ? await search(p.rule, 30, 1.0) : [];   // packs cast a wider net than search
  if (!live() && p.tags?.length) auto = S.filter(s => s.t.some(t => p.tags.includes(t)));
  return [...pins, ...auto.filter(s => !pins.includes(s) && !out.includes(s.id))].slice(0, 30);
}

/* ---------- shared pieces ---------- */
const tile = (s, cls = "", extra = "") => `<button class="t ${cls}" data-id="${s.id}" aria-label="${esc(rec(s).c)}"><img loading="lazy" src="${s.src}" alt="">${extra}</button>`;
const appIcon = cls => `<span class="appicon ${cls || ""}"><i class="ph-fill ph-sticker"></i></span>`;
const win = (title, inner, cls = "") => `<section class="appwin ${cls}"><div class="tbar"><span class="lights"><span></span><span></span><span></span></span><b>${title}</b></div>${inner}</section>`;
const CHATS = [["Jonas Wiegand", "jonas-wiegand", "09:41", "Abgabe ist morgen um 9", 0, 1], ["WG Ehrenfeld", "wg-ehrenfeld-flat", "09:12", "Mira: wer hat den Müll rausgebracht?", 3], ["Mama", "mama-garden", "08:30", "Sticker", 0, 0, "ph-sticker"], ["Leonie Brandt", "leonie-brandt", "Yesterday", "ok dann Freitag bei mir", 0], ["Fußball Donnerstag", "football-thursday", "Yesterday", "Timo: bin raus, Knie", 12], ["Timo Achterberg", "timo-achterberg", "Tuesday", "Photo", 0, 0, "ph-camera"], ["Oma Hilde", "oma-hilde", "Monday", "Ruf mich mal an wenn du Zeit hast", 0], ["Carla Nowak", "carla-nowak", "Sunday", "haha nein", 0]];
const LAST_IN = "Abgabe ist morgen um 9";
const MS = [["d", "Today"], ["i", "moin"], ["i", "hast du den Pitch fertig?", "09:38"], ["o", "fast", "09:39", 1], ["o", "mir fehlen noch die Zahlen von Carla", "09:39"], ["s", 35, "09:40", "i", 1], ["i", "du weißt schon", "09:41", 1], ["i", LAST_IN, "09:41"]];
const ticks = '<i class="ph ph-checks"></i>';
function bubble(m, fresh) {
  if (m[0] === "d") return `<div class="day">${m[1]}</div>`;
  if (m[0] === "s") { const o = m[3] === "o"; return `<div class="m s ${o ? "o" : ""} ${m[4] ? "gap" : ""} ${fresh ? "new" : ""}"><img src="${byId(m[1]).src}" alt=""><span>${m[2]}${o ? ticks : ""}</span></div>`; }
  return `<div class="m ${m[0] === "o" ? "o" : ""} ${m[3] ? "gap" : ""}">${esc(m[1])}${m[2] ? `<span>${m[2]}${m[0] === "o" ? ticks : ""}</span>` : ""}</div>`;
}
const wa = (overlay, sheet) => `<section class="wa"><aside class="rail"><span class="lights"><span></span><span></span><span></span></span>
  <button class="rbtn on"><i class="ph-fill ph-chat-circle-text"></i></button><button class="rbtn"><i class="ph ph-phone"></i></button><button class="rbtn"><i class="ph ph-circle-dashed"></i></button><button class="rbtn"><i class="ph ph-archive"></i></button>
  <div class="sp"></div><button class="rbtn"><i class="ph ph-gear"></i></button><img class="me" src="https://picsum.photos/seed/luis-profile/80" alt=""></aside>
  <div class="list"><header><h3>Chats</h3><div><i class="ph ph-note-pencil"></i><i class="ph ph-dots-three-vertical"></i></div></header><div class="find"><i class="ph ph-magnifying-glass"></i>Search</div>
  <div class="rows">${CHATS.map(([n, seed, t, p, u, on, ic]) => `<div class="row ${on ? "on" : ""} ${u ? "unread" : ""}"><img src="https://picsum.photos/seed/${seed}/96" alt=""><b>${n}</b><time>${t}</time><p>${ic ? `<i class="ph ${ic}"></i>` : ""}${p}</p>${u ? `<em>${u}</em>` : ""}</div>`).join("")}</div></div>
  <div class="chat"><header><img src="https://picsum.photos/seed/jonas-wiegand/96" alt=""><div><b>Jonas Wiegand</b><small>online</small></div><nav><i class="ph ph-video-camera"></i><i class="ph ph-phone"></i><i class="ph ph-magnifying-glass"></i></nav></header>
  <div class="msgs" id="msgs">${MS.map(m => bubble(m)).join("")}</div>
  <div class="bar"><button class="ib"><i class="ph ph-plus"></i></button><div class="txt">Type a message</div><button class="ib" id="waSmile"><i class="ph ph-smiley"></i></button><button class="ib"><i class="ph ph-microphone"></i></button></div>${overlay || ""}</div>${sheet || ""}</section>`;
const modelForm = compact => `<div class="f"><label for="fKey">OpenRouter API key</label><input id="fKey" class="mono" type="password" placeholder="sk-or-v1-..." value="${esc(key())}" autocomplete="off"><small id="keyMsg">Stored in the macOS Keychain. Stickr sends sticker images to this service and to no other.</small></div>
  <div class="two"><div class="f"><label for="fModel">Caption model</label><input id="fModel" class="mono" value="${CAPTION_MODEL}"></div>
  <div class="f"><label for="fProv">Provider</label><select id="fProv"><option value="baseten-first">Baseten first, others when it is busy</option><option value="baseten">Baseten only</option><option value="">Cheapest available</option></select></div></div>
  ${compact ? "" : `<details><summary>Use another OpenAI-compatible server</summary><div class="two"><div class="f"><label for="fUrl">Base URL</label><input id="fUrl" class="mono" value="https://openrouter.ai/api/v1"></div><div class="f"><label for="fEmb">Embedding model</label><input id="fEmb" class="mono" value="${EMBED_MODEL}"></div></div></details>`}
  <div id="testOut"></div>`;
async function testKey() {
  const k = $("#fKey").value.trim(), out = $("#testOut"), msg = $("#keyMsg"); $("#fKey").classList.remove("bad"); msg.className = "";
  if (!k) { $("#fKey").classList.add("bad"); msg.className = "err"; msg.textContent = "Enter a key first."; return false; }
  out.innerHTML = `<div class="result"><div class="skel" style="width:56px"></div><div><span class="sk"></span><span class="sk"></span></div></div>`;
  try { const s = byId(33), r = await caption(s, k, $("#fProv").value, $("#fModel").value.trim());
    sessionStorage.setItem("stickr.key", k); keybox();
    out.innerHTML = `<div class="result"><img src="${s.src}" alt=""><div>${esc(r.c)}<small>${esc(r.provider)} answered in ${r.secs.toFixed(1)} s. This sticker cost $${r.cost.toFixed(5)}. Emoji: ${r.em.join(" ")}</small></div></div>`; return true;
  } catch (e) { out.innerHTML = ""; $("#fKey").classList.add("bad"); msg.className = "err";
    msg.textContent = e.status === 401 ? "OpenRouter does not accept this key." : e.status === 402 ? "This key has no credit left." : e.status === 404 ? "This provider does not serve this model." : "No answer: " + e.message; return false; }
}

/* ---------- scenes ---------- */
const SCENES = [
{ name: "Install", what: "You open the downloaded disk image and drag Stickr into Applications. Nothing else is installed.",
  checks: ["The disk image opens without a Gatekeeper warning. It is signed with the Developer ID and notarized.", "The app starts from Applications on a Mac that never saw it before.", "The app lives in the menu bar. It has no Dock icon."],
  tryit: "Click the app icon to drag it.",
  html: () => win("Stickr", `<div class="drop"><figure>${appIcon()}Stickr</figure><span class="arrow"><i class="ph ph-arrow-right"></i></span><figure><span class="folder"><i class="ph-fill ph-folder"></i></span>Applications</figure></div>`, "dmg"),
  on: st => $(".appicon", st).onclick = () => $(".dmg", st).classList.add("go") },

{ name: "Permissions", what: "On first start Stickr asks for the two things it needs and says why. It asks for nothing else.",
  checks: ["Without access to the WhatsApp data the app explains the problem and offers the button again. It never shows an empty library without a reason.", "Accessibility is optional. It is only used to remove an outdated pack copy from WhatsApp for you.", "Stickr never writes to a WhatsApp file. It reads copies."],
  tryit: "Click Allow, then answer the system question.",
  html: () => win("Welcome to Stickr", `<div class="pad"><h2>Two permissions, then you are set</h2><p>Stickr reads the stickers that WhatsApp already keeps on this Mac.</p>
    <div><div class="perm"><i class="ph ph-folder-lock"></i><div><b>Read your WhatsApp stickers</b><span>Favorites, sent and received stickers. Read only.</span></div><span id="p1"><button class="btn pri" id="allow1">Allow</button></span></div>
    <div class="perm"><i class="ph ph-cursor-click"></i><div><b>Tidy up old packs in WhatsApp</b><span>Optional. Lets Stickr remove the outdated copy after an update.</span></div><span id="p2"><button class="btn" id="allow2">Open Settings</button></span></div></div>
    <div class="rowend"><span class="grow" id="permMsg">Waiting for access to WhatsApp data.</span><button class="btn pri" id="permGo" disabled>Continue</button></div></div>
    <div class="sysalert" id="sys" hidden>${appIcon()}<b>“Stickr” would like to access data from other apps.</b><p>Stickr reads your WhatsApp sticker library to make it searchable.</p><div><button class="btn" id="sysNo">Don’t Allow</button><button class="btn pri" id="sysOk">Allow</button></div></div>`),
  on: st => { const ok = `<span class="ok"><i class="ph-fill ph-check-circle"></i>Allowed</span>`;
    $("#allow1", st).onclick = () => $("#sys", st).hidden = false;
    $("#sysOk", st).onclick = () => { $("#sys", st).hidden = true; $("#p1", st).innerHTML = ok; $("#permMsg", st).textContent = "Found WhatsApp with 122 favorite stickers."; $("#permGo", st).disabled = false; };
    $("#sysNo", st).onclick = () => { $("#sys", st).hidden = true; $("#permMsg", st).innerHTML = `<span style="color:var(--bad)">Stickr cannot see any stickers without this. Click Allow again.</span>`; };
    $("#allow2", st).onclick = () => $("#p2", st).innerHTML = ok; $("#permGo", st).onclick = () => go(2); } },

{ name: "Connect the model", what: "You paste one OpenRouter key. The default model is GLM 5.3 Flash served by Baseten. Test sends one real sticker and shows the real answer.",
  checks: ["The test makes a real request. It shows the caption, the provider that answered, the time and the cost.", "Default routing is Baseten first. When Baseten is rate limited, OpenRouter may use another provider for that one request. Baseten only is a choice in the list.", "A wrong key, an empty balance and a provider without this model each give their own plain message under the field.", "Any OpenAI-compatible server works through the base URL field.", "The key is kept in the Keychain. It is never written to a file or a log."],
  tryit: "Paste your OpenRouter key and click Test. From then on every later step uses the real models.",
  html: () => win("Stickr", `<div class="pad"><h2>Connect the model that reads your stickers</h2><p>About 500 stickers cost less than ten cents with the default model.</p>${modelForm()}
    <div class="rowend"><span class="grow">The test uses one of your stickers.</span><button class="btn" id="testBtn">Test</button><button class="btn pri" id="modelGo">Continue</button></div></div>`),
  on: st => { $("#testBtn", st).onclick = testKey; $("#modelGo", st).onclick = () => go(3); } },

{ name: "First read", what: "Stickr reads every sticker once: a caption, the text in the image, a mood, tags, and up to three emoji. Then it stores a meaning vector for search. You can keep using the Mac while it runs.",
  checks: ["Three stickers are read at the same time. The list fills in as answers arrive.", "A rate limit or a server error is retried up to four times with a growing pause. Tested fact: Baseten rate limited 18 of 40 requests in the first trial without this.", "A failed sticker shows Retry in its row. One failure never stops the run.", "Pause stops new requests. Resume continues where it stopped. A restart of the app does the same.", "Animated stickers are sent as they are. The model reads them without conversion.", "The running cost is visible during the run."],
  tryit: "Click Start. With a key from step 3 this reads your 40 sample stickers for real and takes about a minute.",
  html: () => win("Stickr", `<div class="pad"><div class="idxhead"><h2 id="ixTitle">Read 40 stickers</h2><span id="ixCount">0 of 40</span></div><div class="meter"><i id="ixBar"></i></div>
    <div class="idx" id="ixList">${S.map(s => `<div class="ix" data-id="${s.id}"><img src="${s.src}" alt=""><p><span class="sk"></span><span class="sk"></span></p><span class="st">Waiting</span></div>`).join("")}</div>
    <div class="rowend"><span class="grow" id="ixCost">${key() ? "Uses your key. Expected cost is below one cent." : "No key entered. This run is a simulation with sample captions."}</span><button class="btn" id="ixPause" disabled>Pause</button><button class="btn pri" id="ixStart">Start</button></div></div>`),
  on: st => indexScene(st) },

{ name: "Check the results", what: "You look over what the model understood. Most stickers need nothing. Stickers with thin results are marked so you find them fast. The emoji matter most: WhatsApp's own sticker search finds stickers by them.",
  checks: ["Caption, mood, tags and emoji are all editable. An edit is saved at once and updates search.", "Read again asks the model once more for this one sticker and replaces the fields.", "A sticker is marked when the read failed, when it has fewer than three tags, or when it has no emoji.", "Your edits are never overwritten by a later automatic read."],
  tryit: "Click a sticker, change a tag or an emoji, or click Read again.",
  html: () => win("Stickr", `<div class="rv"><div class="rvl"><div class="rvtop"><div class="seg" id="rvSeg"><button class="on" data-f="all">All</button><button data-f="flag">Needs a look</button><button data-f="edit">Edited</button></div><span id="rvCount"></span></div><div class="rvg" id="rvGrid"></div></div><div class="rvd" id="rvDetail"></div></div>`, "review"),
  on: st => reviewScene(st) },

{ name: "Build packs", what: "A pack is one sentence that says what belongs in it. Stickr fills the pack by meaning and keeps it current. You pin the stickers you always want and remove the ones you never want.",
  checks: ["The member list comes from the same meaning search as the search window. There is no second classifier.", "A pack holds 30 stickers at most. Pinned stickers come first. The rest are ordered by how often you sent them.", "WhatsApp does not allow still and animated stickers in one pack. Stickr splits such a pack into two and says so.", "A removed sticker never comes back into that pack."],
  tryit: "Edit the sentence and click Rebuild. Click a sticker to pin it. Alt-click removes it.",
  html: () => wa("", `<div class="veil"><div class="sheet"><div class="pl"><h4>Your packs</h4><div id="pkList"></div><button class="add" id="addPack"><i class="ph ph-plus"></i>New pack</button></div><div class="ed" id="ed"></div></div></div>`),
  on: st => packsScene(st) },

{ name: "Add to WhatsApp", what: "Add to WhatsApp hands the pack to WhatsApp through its official sticker pack interface. WhatsApp shows its own confirmation. After that the pack is in the normal sticker tray.",
  checks: ["This was tested on this Mac on 21 September 2026: WhatsApp showed this dialog and answered “Sticker pack added”.", "Stickr sends at most 30 stickers, each 512 by 512 pixels, with a 96 pixel tray icon and the emoji from step 5.", "A sticker that breaks a WhatsApp limit is left out of the pack and named in a note. Stickr never sends a broken sticker.", "If WhatsApp is not running, Stickr starts it first."],
  tryit: "Click Add to my stickers.",
  html: () => wa("", `<div class="veil"><div class="wadlg"><header><i class="ph ph-x"></i><span>Work stress</span><i class="ph ph-share-fat"></i></header><div class="g" id="dlgGrid"></div><footer><button class="btn pri" id="dlgAdd">Add to my stickers</button><button class="btn">Open in WhatsApp Business</button></footer></div></div>`),
  on: async st => { $("#dlgGrid", st).innerHTML = (await members(PACKS[0])).map(s => tile(s)).join("");
    $("#dlgAdd", st).onclick = () => { $(".veil", st).remove(); $(".chat", st).insertAdjacentHTML("beforeend", `<div class="toastwa"><i class="ph-fill ph-check-circle"></i>Sticker pack added</div>`); }; } },

{ name: "Use it in WhatsApp", what: "This is the everyday part, and it happens inside WhatsApp. Your packs are tabs in the normal sticker tray. The tray's own search finds your stickers by the emoji Stickr gave them.",
  checks: ["Every Stickr pack appears as a tab in the tray, with the first sticker as its icon.", "A search for an emoji in the tray finds the stickers that carry this emoji.", "A sticker sent from the tray arrives as a real sticker, with transparency and animation.", "A computer-use agent checks all three in the real WhatsApp app before release."],
  tryit: "Click a pack tab or a mood button, then click a sticker to send it.",
  html: () => wa(`<div class="tray"><label class="q"><i class="ph ph-magnifying-glass"></i><input id="trQ" placeholder="Search with text or emoji"></label><div class="cats" id="trCats"></div><div class="body"><div class="g" id="trGrid"></div></div><div class="ptabs" id="trTabs"></div></div>`),
  on: st => trayScene(st) },

{ name: "Keep packs current", what: "When you save new stickers, Stickr reads them and updates its packs. WhatsApp cannot replace an installed pack, so an update installs a fresh copy. Stickr then removes the old copy, or tells you the two clicks to do it.",
  checks: ["New stickers are picked up without any action from you, on the schedule in Settings.", "A pack only asks for an update when its members changed.", "Tested fact: a second import with the same pack ID creates a second pack. Stickr therefore never updates silently.", "With the Accessibility permission Stickr removes the old copy by its name. Without it, Stickr shows where to click."],
  tryit: "Click Update in WhatsApp.",
  html: () => win("Stickr", `<div class="pad"><h2>3 new stickers since Friday</h2><p>They were read and sorted. Two packs changed.</p>
    <div class="vers" id="vers"><div><img src="${byId(33).src}" alt=""><span>Work stress<small>1 sticker added</small></span><button class="btn pri" data-up>Update in WhatsApp</button></div>
    <div><img src="${byId(24).src}" alt=""><span>Cats<small>2 stickers added</small></span><button class="btn pri" data-up>Update in WhatsApp</button></div>
    <div><img src="${byId(2).src}" alt=""><span>Reactions<small>No change</small></span><span class="tag">Current</span></div></div>
    <div id="upMsg"></div></div>`),
  on: st => $$("[data-up]", st).forEach(b => b.onclick = () => { b.outerHTML = `<span class="tag">Current</span>`; $("#upMsg", st).innerHTML = `<div class="banner warn"><i class="ph ph-info"></i><span>The new copy is in WhatsApp. The old copy is still there. In the sticker tray click the pencil, then remove the older pack with the same name.</span><button>Remove it for me</button></div>`; }) },

{ name: "Find by meaning", what: "A hotkey opens a search window from anywhere. You describe a feeling or a picture in German or English. The result tells you which pack holds the sticker. Return copies it as a picture, for apps other than WhatsApp.",
  checks: ["Search works in German and English against the English captions.", "Results appear within half a second after you stop typing.", "Each result names the pack and the position, so you find it in the WhatsApp tray.", "Tested fact: WhatsApp turns any pasted or dropped sticker file into a photo. Stickr says “copy as picture” and never claims to send a sticker from here.", "With no network, search falls back to plain word match and says so."],
  tryit: "Type “we need to talk” or “Stress wegen Abgabe”.",
  html: () => wa(`<div class="pick"><label class="q"><i class="ph ph-magnifying-glass"></i><input id="q" placeholder="Describe a sticker or a feeling" autocomplete="off" spellcheck="false"></label><div class="tabs" id="tabs"></div><div class="body" id="body"></div><div class="foot"><p id="cap"></p><span><kbd>↩</kbd>copy as picture</span><span><kbd>esc</kbd>close</span></div></div>`),
  on: st => findScene(st) },

{ name: "Menu bar and settings", what: "Stickr lives in the menu bar. The menu shows the state and the two main actions. Settings holds the hotkey, the schedule, the model and what you spent.",
  checks: ["The hotkey can be changed and is checked for conflicts.", "Start at login is on by default and can be turned off.", "The spend figure comes from the cost that OpenRouter reports for each request.", "Read everything again asks first and states the expected cost."],
  tryit: "Open the menu bar icon.",
  html: () => `<div class="menu" id="menu"><small>122 stickers. Checked 4 minutes ago.</small><hr><button>Find a sticker<kbd>⌥⌘S</kbd></button><button>Check for new stickers</button><button>Packs…</button><hr><button>Settings…<kbd>⌘,</kbd></button><button>Quit Stickr</button></div>` +
    win("Settings", `<div class="pad"><div class="two"><div class="f"><span class="lab">Hotkey for search</span><div class="hot"><kbd>⌥</kbd><kbd>⌘</kbd><kbd>S</kbd><button class="btn">Change</button></div></div>
    <div class="f"><label for="sched">Look for new stickers</label><select id="sched"><option>Every hour</option><option>Every night</option><option>Only when I ask</option></select></div></div>
    <label class="chk"><input type="checkbox" checked>Start Stickr when I log in</label>${modelForm(true)}
    <div class="f"><span class="lab">Spent this month</span><div class="spend"><div><b>$${(spend || 0.0312).toFixed(4)}</b><span>${spend ? "in this walkthrough" : "sample figure"}</span></div><div><b>122</b><span>stickers read</span></div><div><b>5</b><span>packs</span></div></div></div>
    <div class="rowend"><span class="grow"></span><button class="btn" id="testBtn">Test connection</button><button class="btn">Read everything again</button></div></div>`),
  on: st => { $(".mb", st).classList.add("on"); $(".mb", st).onclick = () => $("#menu", st).hidden = !$("#menu", st).hidden; $("#testBtn", st).onclick = testKey; } },

{ name: "When things go wrong", what: "Each failure has one plain message in the place where you notice it, and one action that fixes it.",
  checks: ["No failure is silent and none shows a raw error code.", "The app keeps working with what it has: old captions stay searchable when the model is unreachable.", "Each message below must be reachable in a test by forcing its cause."],
  html: () => `<div class="fails">${[
    ["The key stopped working", `<div class="banner bad"><i class="ph ph-key"></i><span>OpenRouter does not accept the key any more. New stickers are not being read.</span><button>Open Settings</button></div>`],
    ["No network during search", `<div class="banner warn"><i class="ph ph-wifi-slash"></i><span>No connection. Showing word matches only.</span></div>`],
    ["WhatsApp data cannot be read", `<div class="none"><b>Stickr cannot see your stickers</b>macOS is blocking access to the WhatsApp data.<br><button class="btn pri">Allow access</button></div>`],
    ["Nothing matches", `<div class="none"><b>No sticker fits that</b>Say it another way, or describe the picture: “cat with glasses”.</div>`]]
    .map(([t, b]) => `<figure><figcaption>${t}</figcaption><div class="pick static"><label class="q"><i class="ph ph-magnifying-glass"></i><input placeholder="Describe a sticker or a feeling" disabled></label><div></div><div class="body">${b}</div><div class="foot"><p></p></div></div></figure>`).join("")}</div>` },
];

/* ---------- scene logic ---------- */
function indexScene(st) {
  let paused = false, running = false, done = 0, cost = 0; const isRead = s => key() && IDX[s.id] && !IDX[s.id].failed; const queue = S.filter(s => !isRead(s));
  const row = s => $(`.ix[data-id="${s.id}"]`, st);
  const paint = () => { $("#ixCount", st).textContent = `${done} of ${S.length}`; $("#ixBar", st).style.width = done / S.length * 100 + "%"; if (key()) $("#ixCost", st).textContent = `Cost of this run: $${cost.toFixed(4)}`; };
  async function one(s) {
    const el = row(s); el.className = "ix run"; $(".st", el).textContent = "Reading"; el.scrollIntoView({ block: "nearest" });
    try { let r; if (key()) { r = await caption(s); cost += r.cost; IDX[s.id] = { ...r, vec: IDX[s.id]?.vec }; save(); } else { await new Promise(f => setTimeout(f, 250 + Math.random() * 500)); r = rec(s); }
      el.className = "ix"; $("p", el).innerHTML = `${esc(r.c)}<small>${r.em.join(" ")} ${esc(r.t.join(", "))}</small>`; $(".st", el).innerHTML = `<i class="ph-fill ph-check-circle" style="color:var(--acc);font-size:16px"></i>`; done++; }
    catch (e) { el.className = "ix fail"; $("p", el).innerHTML = `${e.status === 401 ? "The key was rejected." : "The model did not answer."}<small>${esc(e.message)}</small>`; $(".st", el).innerHTML = `<button>Retry</button>`; $(".st button", el).onclick = () => { queue.push(s); pump(); }; }
    paint();
  }
  let active = 0;
  async function pump() { while (!paused && active < 3 && queue.length) { active++; one(queue.shift()).finally(() => { active--; pump(); }); }
    if (!active && !queue.length && running) { running = false; if (key()) { $("#ixTitle", st).textContent = "Storing meaning vectors"; try { const v = await embed(S.map(s => docText(rec(s)))); S.forEach((s, i) => { if (IDX[s.id]) IDX[s.id].vec = v[i]; }); save(); } catch (e) { $("#ixCost", st).textContent = "Vectors failed: " + e.message; } }
      $("#ixTitle", st).textContent = `${done} stickers are ready`; $("#ixPause", st).disabled = true; $("#ixStart", st).textContent = "Check the results"; $("#ixStart", st).disabled = false; $("#ixStart", st).onclick = () => go(4); keybox(); } }
  S.filter(isRead).forEach(s => { const el = row(s), r = rec(s); $("p", el).innerHTML = `${esc(r.c)}<small>${r.em.join(" ")} ${esc(r.t.join(", "))}</small>`; $(".st", el).innerHTML = `<i class="ph-fill ph-check-circle" style="color:var(--acc);font-size:16px"></i>`; done++; }); paint();
  $("#ixStart", st).onclick = () => { running = true; $("#ixStart", st).disabled = true; $("#ixPause", st).disabled = false; $("#ixTitle", st).textContent = "Reading your stickers"; pump(); };
  $("#ixPause", st).onclick = e => { paused = !paused; e.target.textContent = paused ? "Resume" : "Pause"; if (!paused) pump(); };
}
function reviewScene(st) {
  let filter = "all", sel = S[0].id;
  const list = () => S.filter(s => filter === "all" || (filter === "flag" ? flagged(s) : rec(s).edited));
  const edit = (s, patch) => { IDX[s.id] = { ...rec(s), ...patch, edited: true, sample: false }; save(); };
  function grid() { const l = list(); $("#rvCount", st).textContent = `${l.length} stickers`; if (!l.some(s => s.id === sel) && l[0]) sel = l[0].id;
    $("#rvGrid", st).innerHTML = l.length ? l.map(s => tile(s, s.id === sel ? "on" : "", flagged(s) ? `<span class="flag"><i class="ph-bold ph-exclamation-mark"></i></span>` : "")).join("") : `<div class="none" style="grid-column:1/-1"><b>Nothing here</b>${filter === "flag" ? "Every sticker has a caption, three tags and an emoji." : "You have not edited a sticker yet."}</div>`; detail(); }
  function detail() { const s = byId(sel), r = rec(s);
    $("#rvDetail", st).innerHTML = `<div class="pv"><img src="${s.src}" alt=""></div>
      <div class="f"><label for="dC">Caption</label><textarea id="dC" rows="2">${esc(r.c)}</textarea></div>
      <div class="two"><div class="f"><label for="dE">Mood</label><input id="dE" value="${esc(r.e)}"></div><div class="f"><span class="lab">Emoji for WhatsApp search</span><div class="emo">${[0, 1, 2].map(i => `<input data-em="${i}" maxlength="4" value="${r.em[i] || ""}" aria-label="Emoji ${i + 1}">`).join("")}</div></div></div>
      ${r.x ? `<div class="f"><span class="lab">Text in the image</span><span>${esc(r.x)}</span></div>` : ""}
      <div class="f"><span class="lab">Tags</span><div class="chips">${r.t.map((t, i) => `<span class="chip">${esc(t)}<button data-rm="${i}" aria-label="Remove ${esc(t)}"><i class="ph-bold ph-x"></i></button></span>`).join("")}<input id="dT" placeholder="Add a tag"></div></div>
      <div class="rowend"><span class="grow" id="dMsg">${r.sample ? "Sample caption" : r.edited ? "Edited by you" : "Read by " + CAPTION_MODEL}</span><button class="btn" id="dAgain"><i class="ph ph-arrows-clockwise"></i>Read again</button></div>`;
    $("#dC", st).onchange = e => edit(s, { c: e.target.value }); $("#dE", st).onchange = e => edit(s, { e: e.target.value });
    $$("[data-em]", st).forEach(i => i.onchange = () => { edit(s, { em: $$("[data-em]", st).map(x => x.value.trim()).filter(Boolean) }); grid(); });
    $$("[data-rm]", st).forEach(b => b.onclick = () => { edit(s, { t: r.t.filter((_, i) => i != b.dataset.rm) }); grid(); });
    $("#dT", st).onkeydown = e => { if (e.key === "Enter" && e.target.value.trim()) { edit(s, { t: [...r.t, e.target.value.trim().toLowerCase()] }); grid(); $("#dT", st).focus(); } };
    $("#dAgain", st).onclick = async () => { if (!key()) { $("#dMsg", st).textContent = "Enter a key in step 3 to read for real."; return; } $("#dMsg", st).textContent = "Reading"; $("#dAgain", st).disabled = true;
      try { const n = await caption(s); const v = (await embed([docText(n)]))[0]; IDX[s.id] = { ...n, vec: v }; save(); grid(); } catch (e) { $("#dMsg", st).textContent = "No answer: " + e.message; $("#dAgain", st).disabled = false; } }; }
  $("#rvSeg", st).onclick = e => { const b = e.target.closest("button"); if (!b) return; filter = b.dataset.f; $$("#rvSeg button", st).forEach(x => x.classList.toggle("on", x === b)); grid(); };
  $("#rvGrid", st).onclick = e => { const t = e.target.closest(".t"); if (t) { sel = +t.dataset.id; grid(); } };
  grid();
}
function packsScene(st) {
  let edit = PACKS[0].id; PACKS[0].pins ??= [33, 34];
  async function paint() {
    const lists = await Promise.all(PACKS.map(members));
    $("#pkList", st).innerHTML = PACKS.map((p, i) => `<button class="pk ${p.id === edit ? "on" : ""}" data-pk="${p.id}"><img src="${lists[i][0]?.src || byId(1).src}" alt=""><span>${esc(p.name)}</span><small>${lists[i].length}</small></button>`).join("");
    const p = PACKS.find(p => p.id === edit), m = lists[PACKS.indexOf(p)], mixed = m.some(isAnimated) && !m.every(isAnimated);
    $("#ed", st).innerHTML = `<div class="top"><input id="pName" value="${esc(p.name)}" aria-label="Pack name"></div>
      <div class="f"><label for="pRule">What belongs in this pack</label><textarea id="pRule" rows="2">${esc(p.rule)}</textarea><small>Write it like you would tell a friend. German or English.</small></div>
      <div class="f"><span class="lab">In the pack now: ${m.length} of 30</span><div class="mem">${m.map(s => tile(s, (p.pins || []).includes(s.id) ? "pin" : "")).join("") || `<small>No sticker fits this sentence yet.</small>`}</div>
      <small>Click pins a sticker. Alt-click removes it for good.${mixed ? " WhatsApp keeps still and animated stickers apart, so this pack goes in as two." : ""}</small></div>
      <div class="edfoot"><p id="edMsg">${live() ? "Filled by meaning with the real model." : "Filled from sample tags. Enter a key in step 3 for the real model."}</p><button class="btn" id="rebuild">Rebuild</button><button class="btn pri" id="toWa"><i class="ph ph-whatsapp-logo"></i>Add to WhatsApp</button></div>`;
    $("#pName", st).oninput = e => { p.name = e.target.value; $(".pk.on span", st).textContent = p.name; };
    $("#rebuild", st).onclick = async () => { p.rule = $("#pRule", st).value; if (!live()) p.tags = p.rule.toLowerCase().split(/[^a-zäöüß-]+/).filter(w => w.length > 2 && !STOP.has(w)).flatMap(w => [w, ...(NEAR[w] || [])]); $("#edMsg", st).textContent = "Rebuilding"; try { await paint(); } catch (e) { $("#edMsg", st).textContent = "No answer: " + e.message; } };
    $("#toWa", st).onclick = () => go(6);
  }
  $(".sheet", st).onclick = e => { const k = e.target.closest(".pk"); if (k) { edit = k.dataset.pk; return paint(); }
    const t = e.target.closest(".mem .t"); if (t) { const p = PACKS.find(p => p.id === edit), id = +t.dataset.id; if (e.altKey) { (p.out ??= []).push(id); p.pins = (p.pins || []).filter(x => x !== id); } else p.pins = (p.pins || []).includes(id) ? p.pins.filter(x => x !== id) : [...(p.pins || []), id]; return paint(); }
    if (e.target.closest("#addPack")) { const id = "p" + Date.now(); PACKS.push({ id, name: "New pack", rule: "", tags: [] }); edit = id; paint().then(() => $("#pRule", st).focus()); } };
  paint();
}
async function trayScene(st) {
  const packs = await Promise.all(PACKS.map(async p => ({ p, m: await members(p) }))); let tab = packs[0].p.id;
  const CATS = [["👋", "Hi"], ["😂", "Haha"], ["❤️", "Love"], ["😢", "Sad"], ["😰", "Stress"]];
  $("#trCats", st).innerHTML = CATS.map(([e, n]) => `<button data-e="${e}">${e} ${n}</button>`).join("");
  const show = l => $("#trGrid", st).innerHTML = l.length ? l.map(s => tile(s)).join("") : `<div class="none" style="grid-column:1/-1">No stickers found</div>`;
  const tabs = () => { $("#trTabs", st).innerHTML = `<button><i class="ph ph-clock"></i></button><button><i class="ph ph-star"></i></button>` + packs.map(x => `<button class="own ${x.p.id === tab ? "on" : ""}" data-tab="${x.p.id}" title="${esc(x.p.name)}"><img src="${x.m[0]?.src || byId(1).src}" alt=""></button>`).join(""); show(packs.find(x => x.p.id === tab).m); };
  const byEmoji = e => S.filter(s => rec(s).em.some(x => x.includes(e) || e.includes(x)));
  $("#trTabs", st).onclick = e => { const b = e.target.closest("[data-tab]"); if (b) { tab = b.dataset.tab; $$("#trCats button", st).forEach(x => x.classList.remove("on")); tabs(); } };
  $("#trCats", st).onclick = e => { const b = e.target.closest("button"); if (!b) return; $$("#trCats button", st).forEach(x => x.classList.toggle("on", x === b)); show(byEmoji(b.dataset.e)); };
  $("#trQ", st).oninput = e => { const q = e.target.value.trim(); q ? show(byEmoji(q)) : tabs(); };
  $("#trGrid", st).onclick = e => { const t = e.target.closest(".t"); if (!t) return; $("#msgs", st).insertAdjacentHTML("beforeend", bubble(["s", +t.dataset.id, "09:42", "o", 1], true)); $("#msgs", st).scrollTop = 1e6; };
  tabs(); $("#msgs", st).scrollTop = 1e6;
}
function findScene(st) {
  let sel = null, items = [], deb, where = {};
  Promise.all(PACKS.map(async p => (await members(p)).forEach((s, i) => where[s.id] ??= `${p.name}, sticker ${i + 1}`)));
  const cap = () => { const s = byId(sel); $("#cap", st).textContent = s ? (where[s.id] ? "In pack " + where[s.id] : "In no pack yet") : ""; };
  async function run(q, head) { $("#body", st).innerHTML = `<div class="sec">Searching</div><div class="g">${'<div class="skel"></div>'.repeat(10)}</div>`;
    try { items = await search(q); } catch (e) { items = S.map(s => [s, wordScore(s, q)]).filter(x => x[1] >= .4).map(x => x[0]); head = `<span style="color:var(--warn)">No connection. Showing word matches only.</span>`; }
    sel = items[0]?.id ?? null;
    $("#body", st).innerHTML = items.length ? `<div class="sec">${head}</div><div class="g">${items.map(s => tile(s, s.id === sel ? "on" : "")).join("")}</div>` : `<div class="none"><b>No sticker fits that</b>Say it another way, or describe the picture: “cat with glasses”.</div>`; cap(); }
  const home = () => run(LAST_IN + " deadline stressed late", `Fits the last message: <q>${LAST_IN}</q>`);
  $("#tabs", st).innerHTML = `<button class="tab on"><i class="ph ph-sparkle"></i><b>${live() ? "Real meaning search" : "Sample search"}</b></button>`;
  $("#q", st).oninput = e => { clearTimeout(deb); const q = e.target.value.trim(); deb = setTimeout(() => q ? run(q, `Results for <q>${esc(q)}</q>`) : home(), 300); };
  $("#body", st).onclick = e => { const t = e.target.closest(".t"); if (t) { sel = +t.dataset.id; $$(".pick .t", st).forEach(x => x.classList.toggle("on", x === t)); cap(); } };
  st.onkeydown = e => { if (e.key === "Enter" && sel) { $("#cap", st).textContent = "Copied as a picture."; e.preventDefault(); }
    const d = { ArrowDown: 5, ArrowUp: -5 }[e.key]; if (!d) return; e.preventDefault(); e.stopPropagation(); const ids = items.map(s => s.id), i = ids.indexOf(sel) + d; if (i < 0 || i >= ids.length) return; sel = ids[i]; $$(".pick .t", st).forEach(x => x.classList.toggle("on", +x.dataset.id === sel)); cap(); };
  home(); $("#q", st).focus(); $("#msgs", st).scrollTop = 1e6;
}

/* ---------- shell ---------- */
let step = Math.min(SCENES.length - 1, Math.max(0, (+location.hash.slice(1) || 1) - 1));
function keybox() { $("#keybox").innerHTML = key() ? `<b>Real mode.</b> ${Object.values(IDX).filter(r => r.vec).length} of ${S.length} stickers read by the real model. Spent in this walkthrough: $${spend.toFixed(4)}. <a href="#" id="forget">Forget key and results</a>` : `<b>Sample mode.</b> Enter an OpenRouter key in step 3 to run every step on the real models.`;
  const f = $("#forget"); if (f) f.onclick = e => { e.preventDefault(); sessionStorage.clear(); localStorage.removeItem("stickr.idx.v2"); localStorage.removeItem("stickr.spend"); IDX = {}; spend = 0; go(step); }; }
function go(i) {
  step = i; history.replaceState(null, "", "#" + (i + 1)); const sc = SCENES[i], st = $("#stage");
  $("#steps").innerHTML = SCENES.map((s, j) => `<li><button class="${j === i ? "on" : ""}" data-i="${j}"><span>${j + 1}</span>${s.name}</button></li>`).join("");
  $("#note").innerHTML = `<h2>What happens</h2><p>${sc.what}</p><h2>Must be true in the real app</h2><ul>${sc.checks.map(c => `<li>${c}</li>`).join("")}</ul>${sc.tryit ? `<p class="try">${sc.tryit}</p>` : ""}`;
  st.onkeydown = null;
  st.innerHTML = `<div class="menubar"><i class="ph-fill ph-apple-logo"></i><b>${i >= 5 && i !== 8 && i !== 10 && i !== 11 ? "WhatsApp" : "Stickr"}</b><span>File</span><span>Edit</span><span>View</span><span>Window</span><span class="sp"></span><button class="mb" aria-label="Stickr menu"><i class="ph-fill ph-sticker"></i></button><i class="ph ph-wifi-high"></i><span>Mon 21 Sep 09:41</span></div><div class="desk">${sc.html()}</div>`;
  if (i !== 10) $("#menu", st)?.remove(); sc.on?.(st); keybox();
}
$("#steps").onclick = e => { const b = e.target.closest("button"); if (b) go(+b.dataset.i); };
document.addEventListener("keydown", e => { if (e.target.matches("input,textarea,select")) return; if (e.key === "ArrowRight" && step < SCENES.length - 1) go(step + 1); if (e.key === "ArrowLeft" && step > 0) go(step - 1); });
const fit = () => { const w = $("#wrap"), k = Math.min((w.clientWidth - 32) / 1180, (w.clientHeight - 32) / 800, 1); $("#stage").style.transform = `translate(-50%,-50%) scale(${k})`; };
new ResizeObserver(fit).observe($("#wrap")); fit(); go(step);
