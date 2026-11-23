/// The scoreboard page: one self-contained document the director's computer
/// serves to a browser on the projector, a TV or a phone. It polls
/// `board.json` and cycles through the tables, splitting a long table
/// across screens rather than shrinking it. Every name is written with
/// `textContent`, never as markup.
const scoreboardPage = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Scoreboard</title>
<style>
:root {
  color-scheme: light dark;
  --bg: #ffffff; --fg: #10151c; --muted: #5a6472; --line: #d6dce4;
  --stripe: #f3f6fa; --accent: #1f4fd8; --warn: #a15c00;
  --scale: 1;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117; --fg: #f1f4f8; --muted: #9aa5b4; --line: #2b3441;
    --stripe: #151b24; --accent: #8fb0ff; --warn: #f0b860;
  }
}
* { box-sizing: border-box; }
html, body { height: 100%; margin: 0; }
body {
  background: var(--bg); color: var(--fg);
  font: calc(clamp(15px, 2.1vw, 34px) * var(--scale)) / 1.25
    system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
  display: flex; flex-direction: column; overflow: hidden;
}
header {
  display: flex; align-items: baseline; gap: 1em;
  padding: .45em .8em; border-bottom: 2px solid var(--line);
}
header .event {
  flex: 1; min-width: 0; font-weight: 600;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
header .clock { font-variant-numeric: tabular-nums; color: var(--muted); }
.title {
  display: flex; align-items: baseline; gap: .8em; padding: .5em .8em .2em;
}
.title h1 {
  flex: 1; min-width: 0; margin: 0; font-size: 1.25em; font-weight: 700;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.title .page { color: var(--muted); font-size: .8em; white-space: nowrap; }
main { flex: 1; min-height: 0; padding: 0 .8em; overflow: hidden; }
table { width: 100%; border-collapse: collapse; table-layout: fixed; }
th {
  text-align: left; font-size: .7em; font-weight: 600; color: var(--muted);
  text-transform: uppercase; letter-spacing: .04em;
  padding: .3em .4em; border-bottom: 2px solid var(--line);
}
td {
  padding: .28em .4em; border-bottom: 1px solid var(--line);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
tbody tr:nth-child(even) { background: var(--stripe); }
.num { width: 4.2em; text-align: right; font-variant-numeric: tabular-nums; }
.result {
  width: 6.5em; text-align: center; font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.pairings td.white { text-align: right; }
.pairings th.white { text-align: right; }
.rating { width: 5em; text-align: right; color: var(--muted);
  font-variant-numeric: tabular-nums; }
.score { width: 5em; text-align: right; font-weight: 700;
  font-variant-numeric: tabular-nums; }
.notes { padding: .4em .4em 0; color: var(--muted); font-size: .8em; }
.empty { padding: 2em .4em; color: var(--muted); }
footer {
  display: flex; align-items: center; gap: .8em;
  padding: .35em .8em; border-top: 1px solid var(--line);
  color: var(--muted); font-size: .65em;
}
footer .status { flex: 1; min-width: 0; }
footer .lost { color: var(--warn); font-weight: 600; }
button {
  font: inherit; color: var(--fg); background: transparent;
  border: 1px solid var(--line); border-radius: 6px;
  padding: .2em .7em; cursor: pointer;
}
button:hover { border-color: var(--muted); }
button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
@media (max-width: 640px) {
  .rating { display: none; }
  .num { width: 3em; }
  .result { width: 5.6em; font-size: .9em; }
}
</style>
</head>
<body>
<header>
  <div class="event" id="event">Scoreboard</div>
  <div class="clock" id="clock"></div>
</header>
<div class="title">
  <h1 id="heading"></h1>
  <div class="page" id="page"></div>
</div>
<main id="main"></main>
<footer>
  <div class="status" id="status"></div>
  <button id="smaller" title="Smaller text" aria-label="Smaller text">A−</button>
  <button id="larger" title="Larger text" aria-label="Larger text">A+</button>
  <button id="prev" title="Previous screen (left arrow)">Prev</button>
  <button id="pause" title="Pause (space)">Pause</button>
  <button id="next" title="Next screen (right arrow)">Next</button>
</footer>
<script>
"use strict";
const $ = (id) => document.getElementById(id);
const columnClass = {
  pairings: ["num", "white", "result", "black"],
  standings: ["num", "name", "rating", "score"],
};
let board = { event: "", seconds: 10, changed: "", tables: [] };
let table = 0, page = 0, pages = 1, paused = false, lost = null;
let elapsed = 0, scale = 1;

try {
  scale = Number(localStorage.getItem("scoreboard-scale")) || 1;
} catch (e) { /* private window: keep the default */ }
function applyScale() {
  scale = Math.min(2, Math.max(.6, scale));
  document.documentElement.style.setProperty("--scale", scale);
  try { localStorage.setItem("scoreboard-scale", scale); } catch (e) {}
  draw();
}

function time(date) {
  return date.toLocaleTimeString([], { hour12: false });
}

function cell(tag, text, name) {
  const el = document.createElement(tag);
  el.textContent = text;
  if (name) el.className = name;
  return el;
}

function build(t, rows) {
  const classes = columnClass[t.kind] || [];
  const el = document.createElement("table");
  el.className = t.kind;
  const head = el.createTHead().insertRow();
  t.columns.forEach((c, i) => head.appendChild(cell("th", c, classes[i])));
  const body = el.createTBody();
  for (const row of rows) {
    const tr = body.insertRow();
    row.forEach((c, i) => tr.appendChild(cell("td", c, classes[i])));
  }
  return el;
}

// How many rows of [t] fit under its heading, measured with real rows so
// text size and window height both count. The byes line sits under the
// last screen only, so it costs rows only when that screen is full.
function fit(t) {
  const main = $("main");
  main.replaceChildren(build(t, t.rows.slice(0, 1)));
  const el = main.firstChild;
  const row = el.tBodies[0].rows[0];
  if (!row) return 1;
  const room = main.clientHeight - el.tHead.offsetHeight;
  const each = row.offsetHeight || 1;
  const per = Math.max(1, Math.floor(room / each));
  if (!t.notes || !t.notes.length) return per;
  const n = cell("div", t.notes.join("  "), "notes");
  main.appendChild(n);
  const withNotes = Math.max(1, Math.floor((room - n.offsetHeight) / each));
  const last = t.rows.length - (Math.ceil(t.rows.length / per) - 1) * per;
  return last <= withNotes ? per : withNotes;
}

function draw() {
  const main = $("main");
  $("event").textContent = board.event || "Scoreboard";
  document.title = (board.event ? board.event + " · " : "") + "Scoreboard";
  if (!board.tables.length) {
    $("heading").textContent = "";
    $("page").textContent = "";
    main.replaceChildren(cell("div",
      "Nothing to show yet. Pairings appear here when a round is posted.",
      "empty"));
    status();
    return;
  }
  if (table >= board.tables.length) { table = 0; page = 0; }
  const t = board.tables[table];
  const per = fit(t);
  pages = Math.max(1, Math.ceil(t.rows.length / per));
  if (page >= pages) page = pages - 1;
  $("heading").textContent = t.section + " · " + t.title;
  $("page").textContent =
    pages > 1 ? "Screen " + (page + 1) + " of " + pages : "";
  main.replaceChildren(build(t, t.rows.slice(page * per, (page + 1) * per)));
  if (t.notes && t.notes.length && page === pages - 1) {
    main.appendChild(cell("div", t.notes.join("  "), "notes"));
  }
  status();
}

function status() {
  const el = $("status");
  el.className = "status" + (lost ? " lost" : "");
  if (lost) {
    el.textContent = "Lost contact with the director's computer at " +
      time(lost) + ". Showing the last board received.";
  } else if (board.changed) {
    el.textContent = "Last change " + time(new Date(board.changed));
  } else {
    el.textContent = "";
  }
  $("pause").textContent = paused ? "Resume" : "Pause";
}

function step(by) {
  elapsed = 0;
  if (!board.tables.length) return;
  page += by;
  if (page >= pages) {
    table = (table + 1) % board.tables.length; page = 0;
  } else if (page < 0) {
    table = (table - 1 + board.tables.length) % board.tables.length;
    page = Number.MAX_SAFE_INTEGER;
  }
  draw();
}

async function refresh() {
  try {
    const reply = await fetch("board.json", { cache: "no-store" });
    if (!reply.ok) throw new Error(reply.status);
    const next = await reply.json();
    const same = JSON.stringify(next.tables) === JSON.stringify(board.tables)
      && next.event === board.event;
    const here = board.tables[table];
    board = next;
    lost = null;
    if (!same) {
      // Stay on the table being read when it is still there.
      const at = here ? board.tables.findIndex((t) =>
        t.section === here.section && t.kind === here.kind) : -1;
      if (at >= 0) table = at; else { table = 0; page = 0; }
      draw();
    } else {
      status();
    }
  } catch (e) {
    if (!lost) { lost = new Date(); status(); }
  }
}

setInterval(() => {
  $("clock").textContent = time(new Date());
  if (paused) return;
  elapsed++;
  if (elapsed >= (board.seconds || 10)) step(1);
}, 1000);
setInterval(refresh, 3000);

$("prev").onclick = () => step(-1);
$("next").onclick = () => step(1);
$("pause").onclick = () => { paused = !paused; elapsed = 0; status(); };
$("smaller").onclick = () => { scale -= .1; applyScale(); };
$("larger").onclick = () => { scale += .1; applyScale(); };
document.addEventListener("keydown", (e) => {
  if (e.key === "ArrowRight") step(1);
  else if (e.key === "ArrowLeft") step(-1);
  else if (e.key === " ") { e.preventDefault(); $("pause").onclick(); }
});
let touch = null;
document.addEventListener("touchstart", (e) => {
  touch = e.touches.length === 1 ? e.touches[0].clientX : null;
}, { passive: true });
document.addEventListener("touchend", (e) => {
  if (touch === null) return;
  const moved = e.changedTouches[0].clientX - touch;
  touch = null;
  if (Math.abs(moved) > 60) step(moved < 0 ? 1 : -1);
}, { passive: true });
window.addEventListener("resize", draw);

$("clock").textContent = time(new Date());
document.documentElement.style.setProperty("--scale", scale);
draw();
refresh();
</script>
</body>
</html>
''';
