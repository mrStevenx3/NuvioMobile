import Foundation

/// The single-page config UI served at `/` by `RemoteSetupServer`. Plain HTML+JS, no external
/// resources (works offline on the LAN). Edits are staged client-side; "Send to TV" POSTs the
/// whole desired state to `/api/apply`, then polls `/api/status/{id}` until the user confirms
/// or rejects the change on the TV.
enum RemoteSetupWebPage {
    static let html = #"""
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Orbit · Configuration à distance</title>
<style>
  :root {
    /* Orbit: black, white, nothing to choose. */
    --bg: #000000; --card: #111214; --card2: #1b1c20; --text: #ffffff; --dim: #8e9097;
    --accent: #ffffff; --danger: #ff6b66; --ok: #4cd284;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--text);
    font: 16px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif;
    padding-bottom: 96px;
  }
  header { padding: 20px 16px 4px; max-width: 720px; margin: 0 auto; }
  header h1 {
    margin: 0; font-size: 30px; font-weight: 800; letter-spacing: -0.5px; color: var(--text);
  }
  header p { margin: 6px 0 0; color: var(--dim); font-size: 14px; }
  main { max-width: 720px; margin: 0 auto; padding: 8px 16px; }
  section { background: var(--card); border-radius: 18px; padding: 18px; margin-top: 16px; }
  h2 { margin: 0 0 4px; font-size: 18px; }
  .hint { color: var(--dim); font-size: 13px; margin: 0 0 12px; }
  .row {
    display: flex; align-items: center; gap: 10px; background: var(--card2);
    border-radius: 10px; padding: 10px 12px; margin-top: 8px;
  }
  .row .info { flex: 1; min-width: 0; }
  .row .name { font-weight: 600; font-size: 15px; }
  .row .sub {
    color: var(--dim); font-size: 12px; overflow: hidden;
    text-overflow: ellipsis; white-space: nowrap;
  }
  .row.disabled .name, .row.disabled .sub { opacity: 0.45; }
  button {
    border: 0; border-radius: 10px; background: #26272c; color: var(--text);
    font-size: 14px; padding: 8px 10px; cursor: pointer; flex-shrink: 0;
  }
  button:active { opacity: 0.7; }
  button.icon { width: 36px; height: 36px; padding: 0; font-size: 16px; }
  button.danger { background: rgba(255, 107, 102, 0.16); color: var(--danger); }
  .addbar { display: flex; gap: 8px; margin-top: 12px; }
  input[type=text], input[type=password] {
    flex: 1; min-width: 0; background: var(--card2); border: 1px solid #2c2d33;
    border-radius: 8px; color: var(--text); font-size: 15px; padding: 10px 12px;
  }
  input::placeholder { color: #5d5f66; }
  .keyrow { display: flex; gap: 8px; align-items: center; margin-top: 8px; }
  .keyrow label { width: 88px; flex-shrink: 0; font-size: 14px; }
  .footer {
    position: fixed; left: 0; right: 0; bottom: 0; padding: 12px 16px;
    background: rgba(0, 0, 0, 0.9); backdrop-filter: blur(10px);
    border-top: 1px solid #1f2024;
  }
  .footer .inner { max-width: 720px; margin: 0 auto; display: flex; gap: 10px; align-items: center; }
  .apply {
    flex: 1; background: #ffffff; font-weight: 700; font-size: 16px; padding: 14px;
    border-radius: 999px; color: #000;
  }
  .apply:disabled { opacity: 0.4; }
  #status { font-size: 13px; color: var(--dim); flex: 1; }
  #status.ok { color: var(--ok); }
  #status.err { color: var(--danger); }
  .toggle { position: relative; width: 44px; height: 26px; flex-shrink: 0; }
  .toggle input { display: none; }
  .toggle span {
    position: absolute; inset: 0; border-radius: 13px; background: #34353b; transition: 0.15s;
  }
  .toggle span::after {
    content: ""; position: absolute; top: 3px; left: 3px; width: 20px; height: 20px;
    border-radius: 50%; background: #fff; transition: 0.15s;
  }
  .toggle input:checked + span { background: var(--accent); }
  .toggle input:checked + span::after { background: #000; }
  .toggle input:checked + span::after { left: 21px; }
  .empty { color: var(--dim); font-size: 14px; padding: 8px 2px; }
</style>
</head>
<body>
<header>
  <h1>Orbit</h1>
  <p>Configuration à distance. Tes changements sont préparés ici, puis confirmés sur ton Apple&nbsp;TV.</p>
</header>
<main>
  <section>
    <h2>Add-ons</h2>
    <p class="hint">Colle l'adresse d'un manifeste pour l'installer. Réordonne avec les flèches : les rangées du premier add-on apparaissent en premier.</p>
    <div id="addons"></div>
    <div class="addbar">
      <input type="text" id="addon-url" placeholder="https://example.com/manifest.json" autocapitalize="off" autocorrect="off">
      <button onclick="addAddon()">Ajouter</button>
    </div>
  </section>

  <section>
    <h2>Rangées de l'accueil</h2>
    <p class="hint">Active ou désactive tes catalogues et choisis leur ordre sur l'accueil.</p>
    <div id="rows"></div>
  </section>

  <section>
    <h2>Clés</h2>
    <p class="hint">Facultatif. MDBList ajoute les notes IMDb, Rotten Tomatoes et Metacritic. La clé n'est envoyée que si tu en saisis une.</p>
    <div class="keyrow">
      <label>MDBList</label>
      <input type="password" id="mdblist-key" autocapitalize="off" autocorrect="off">
    </div>
  </section>

</main>
<div class="footer">
  <div class="inner">
    <div id="status">Chargement&hellip;</div>
    <button class="apply" id="apply" onclick="apply()" disabled>Envoyer à l'Apple TV</button>
  </div>
</div>

<script>
let addons = [];   // {url, name, description, enabled, isNew}
let rows = [];     // {key, title, enabled, isCollection}

const el = id => document.getElementById(id);
const esc = s => (s || "").replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

// Per-session pairing token from the QR/typed URL; the server requires it on every route.
const TOKEN = new URLSearchParams(location.search).get("t") || "";
const AUTH = { "X-Setup-Token": TOKEN };

function setStatus(text, cls) {
  const s = el("status");
  s.textContent = text;
  s.className = cls || "";
}

async function load() {
  try {
    const res = await fetch("/api/state", { headers: AUTH });
    const state = await res.json();
    addons = (state.addons || []).map(a => ({ ...a, isNew: false }));
    rows = state.rows || [];
    if (state.mdblistKeySet) el("mdblist-key").placeholder = "Enregistrée sur l'Apple TV — saisis-en une pour la remplacer";
    render();
    setStatus("Connecté à " + (state.deviceName || "l'Apple TV"), "ok");
    el("apply").disabled = false;
  } catch (e) {
    setStatus("Impossible de joindre l'Apple TV. La configuration à distance est-elle toujours ouverte ?", "err");
  }
}

function move(list, i, delta) {
  const j = i + delta;
  if (j < 0 || j >= list.length) return;
  [list[i], list[j]] = [list[j], list[i]];
  render();
}

function render() {
  el("addons").innerHTML = addons.length ? addons.map((a, i) => `
    <div class="row ${a.enabled ? "" : "disabled"}">
      <label class="toggle"><input type="checkbox" ${a.enabled ? "checked" : ""}
        onchange="addons[${i}].enabled = this.checked; render()"><span></span></label>
      <div class="info">
        <div class="name">${esc(a.name || "Nouvel add-on")}${a.isNew ? " (nouveau)" : ""}</div>
        <div class="sub">${esc(a.url)}</div>
      </div>
      <button class="icon" onclick="move(addons, ${i}, -1)">&#8593;</button>
      <button class="icon" onclick="move(addons, ${i}, 1)">&#8595;</button>
      <button class="icon danger" onclick="addons.splice(${i}, 1); render()">&#10005;</button>
    </div>`).join("") : `<div class="empty">Aucun add-on installé.</div>`;

  el("rows").innerHTML = rows.length ? rows.map((r, i) => `
    <div class="row ${r.enabled ? "" : "disabled"}">
      <label class="toggle"><input type="checkbox" ${r.enabled ? "checked" : ""}
        onchange="rows[${i}].enabled = this.checked; render()"><span></span></label>
      <div class="info">
        <div class="name">${esc(r.title)}</div>
        <div class="sub">${r.isCollection ? "Collection" : "Catalogue"}</div>
      </div>
      <button class="icon" onclick="move(rows, ${i}, -1)">&#8593;</button>
      <button class="icon" onclick="move(rows, ${i}, 1)">&#8595;</button>
    </div>`).join("") : `<div class="empty">Les rangées apparaissent une fois les add-ons chargés.</div>`;
}

function addAddon() {
  const input = el("addon-url");
  const url = input.value.trim();
  if (!url) return;
  if (addons.some(a => a.url === url)) { setStatus("Cet add-on est déjà dans la liste.", "err"); return; }
  addons.push({ url, name: "", description: "", enabled: true, isNew: true });
  input.value = "";
  render();
}

async function apply() {
  const btn = el("apply");
  btn.disabled = true;
  setStatus("En attente de confirmation sur l'Apple TV…");
  const payload = {
    addons: addons.map(a => ({ url: a.url, enabled: a.enabled })),
    rowOrder: rows.map(r => r.key),
    disabledRowKeys: rows.filter(r => !r.enabled).map(r => r.key)
  };
  const mdbl = el("mdblist-key").value.trim();
  if (mdbl) payload.mdblistKey = mdbl;

  try {
    const res = await fetch("/api/apply", {
      method: "POST",
      headers: { "Content-Type": "application/json", ...AUTH },
      body: JSON.stringify(payload)
    });
    const { id, error } = await res.json();
    if (error || !id) throw new Error(error || "bad response");
    poll(id, 0);
  } catch (e) {
    setStatus("Impossible d'envoyer les changements à l'Apple TV.", "err");
    btn.disabled = false;
  }
}

async function poll(id, tries) {
  if (tries > 120) { setStatus("L'Apple TV n'a pas répondu à temps.", "err"); el("apply").disabled = false; return; }
  try {
    const res = await fetch("/api/status/" + id, { headers: AUTH });
    const { status } = await res.json();
    if (status === "confirmed") {
      setStatus("Appliqué sur l'Apple TV ✓", "ok");
      el("mdblist-key").value = "";
      setTimeout(load, 1500);
      el("apply").disabled = false;
      return;
    }
    if (status === "rejected" || status === "not_found") {
      setStatus("Refusé sur l'Apple TV.", "err");
      el("apply").disabled = false;
      return;
    }
  } catch (e) { /* transient; keep polling */ }
  setTimeout(() => poll(id, tries + 1), 1000);
}

load();
</script>
</body>
</html>
"""#
}
