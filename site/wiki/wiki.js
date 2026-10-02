// HyprDarwin wiki: hash routes (#/section/page) → pages/section/page.md, rendered with marked.
const NAV = [
  { section: "Getting Started", slug: "getting-started", pages: [
    ["installation", "Installation"],
    ["master-tutorial", "Master tutorial"],
    ["preconfigured-setup", "Preconfigured setup"],
  ] },
  { section: "Configuring", slug: "configuring", pages: [
    ["basics", "Configuration basics"],
    ["keybinds", "Keybinds and modes"],
    ["workspaces-monitors", "Workspaces and monitors"],
    ["window-rules", "Window rules"],
    ["layouts", "Layouts"],
    ["gaps", "Gaps"],
    ["borders", "Borders"],
    ["bar", "Status bar"],
    ["notch", "Notch panel"],
    ["mouse", "Mouse"],
  ] },
  { section: "Plugins", slug: "plugins", pages: [
    ["using", "Using plugins"],
    ["writing", "Writing plugins"],
    ["bundled", "Bundled plugins"],
  ] },
  { section: "Reference", slug: "reference", pages: [
    ["cli", "CLI"],
    ["troubleshooting", "Troubleshooting"],
  ] },
];
const HOME = { path: "home", title: "Wiki", section: "" };
const ALL = [HOME, ...NAV.flatMap((s) => s.pages.map(([slug, title]) => ({ path: `${s.slug}/${slug}`, title, section: s.section })))];
const REPO = "https://github.com/juniorsaldanha/hyprland-darwin";
const $ = (id) => document.getElementById(id);
const cache = new Map();

const slugify = (s) => s.toLowerCase().replace(/<[^>]+>/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const fetchPage = async (path) => {
  if (!cache.has(path)) {
    cache.set(path, fetch(`pages/${path}.md`).then((r) => (r.ok ? r.text() : `# Not found\n\nNo page at \`${path}\`. [Back to the wiki home](#/home).`)));
  }
  return cache.get(path);
};
const currentPath = () => {
  const path = decodeURIComponent(location.hash.replace(/^#\/?/, "")).split("?")[0];
  return ALL.some((p) => p.path === path) ? path : "home";
};

// ---------- sidebar ----------
function renderSidebar(path) {
  const open = path.split("/")[0];
  $("sidebar").innerHTML =
    `<a class="home ${path === "home" ? "on" : ""}" href="#/home">⌂ Wiki home</a>` +
    NAV.map((s) => `
      <details ${s.slug === open || path === "home" ? "open" : ""}>
        <summary>${s.section}</summary>
        <ul>${s.pages.map(([slug, title]) => {
          const p = `${s.slug}/${slug}`;
          return `<li><a href="#/${p}" class="${p === path ? "on" : ""}">${title}</a></li>`;
        }).join("")}</ul>
      </details>`).join("");
}

// ---------- markdown ----------
const CALLOUT = /^<p>\[!(NOTE|TIP|WARNING|IMPORTANT)\]\s*/i;
function enhance(article) {
  // GitHub-style callouts: > [!NOTE]
  article.querySelectorAll("blockquote").forEach((q) => {
    const m = q.innerHTML.trim().match(CALLOUT);
    if (!m) return;
    const kind = m[1].toLowerCase();
    q.classList.add("callout", kind);
    q.innerHTML = `<div class="ctitle">${kind}</div>` + q.innerHTML.trim().replace(CALLOUT, "<p>");
  });
  // heading anchors
  article.querySelectorAll("h2, h3").forEach((h) => {
    h.id = slugify(h.textContent);
    const a = document.createElement("span");
    a.className = "anchor";
    a.textContent = "#";
    a.title = "Copy link to this section";
    a.onclick = () => navigator.clipboard?.writeText(`${location.href.split("?")[0]}?h=${h.id}`);
    h.append(a);
  });
  // copy buttons on code blocks
  article.querySelectorAll("pre").forEach((pre) => {
    const b = document.createElement("button");
    b.className = "copy";
    b.type = "button";
    b.textContent = "Copy";
    b.onclick = async () => {
      try { await navigator.clipboard.writeText(pre.querySelector("code").innerText); b.textContent = "Copied ✓"; }
      catch { b.textContent = "Select it"; }
      setTimeout(() => (b.textContent = "Copy"), 1500);
    };
    pre.append(b);
  });
  // external links open in a new tab
  article.querySelectorAll("a[href^='http']").forEach((a) => { a.target = "_blank"; a.rel = "noopener"; });
}

// ---------- on this page ----------
let tocObserver;
function renderToc(article) {
  const heads = [...article.querySelectorAll("h2, h3")];
  $("toc").innerHTML = heads.length
    ? `<div class="t">On this page</div>` + heads.map((h) => `<a href="#" data-id="${h.id}" class="${h.tagName.toLowerCase()}">${h.textContent.replace(/#$/, "")}</a>`).join("")
    : "";
  $("toc").querySelectorAll("a").forEach((a) => {
    a.onclick = (e) => { e.preventDefault(); $(a.dataset.id)?.scrollIntoView({ behavior: "smooth" }); };
  });
  tocObserver?.disconnect();
  tocObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      $("toc").querySelectorAll("a").forEach((a) => a.classList.toggle("on", a.dataset.id === entry.target.id));
    }
  }, { rootMargin: "-10% 0px -75% 0px" });
  heads.forEach((h) => tocObserver.observe(h));
}

// ---------- page ----------
async function show() {
  const path = currentPath();
  const meta = ALL.find((p) => p.path === path);
  renderSidebar(path);
  closeMenu();
  const article = $("page");
  article.innerHTML = marked.parse(await fetchPage(path));
  enhance(article);
  renderToc(article);
  article.classList.remove("enter"); void article.offsetWidth; article.classList.add("enter");
  $("crumbs").innerHTML = meta.section ? `wiki <b>/</b> ${meta.section} <b>/</b> ${meta.title}` : "wiki";
  document.title = `${meta.path === "home" ? "Wiki" : meta.title} · HyprDarwin`;
  const i = ALL.indexOf(meta), prev = ALL[i - 1], next = ALL[i + 1];
  $("pager").innerHTML =
    (prev ? `<a class="prev" href="#/${prev.path}"><small>← Previous</small>${prev.title}</a>` : "") +
    (next ? `<a class="next" href="#/${next.path}"><small>Next →</small>${next.title}</a>` : "");
  $("edit").href = `${REPO}/edit/main/site/wiki/pages/${path}.md`;
  const target = new URLSearchParams(location.hash.split("?")[1] || "").get("h");
  if (target && $(target)) $(target).scrollIntoView();
  else scrollTo({ top: 0 });
}

// ---------- mobile menu ----------
const closeMenu = () => { $("sidebar").classList.remove("open"); $("scrim").classList.remove("open"); };
$("menu").onclick = () => { $("sidebar").classList.toggle("open"); $("scrim").classList.toggle("open"); };
$("scrim").onclick = closeMenu;

// ---------- search ----------
let index = null, selected = 0;
async function buildIndex() {
  if (index) return index;
  const docs = await Promise.all(ALL.map(async (p) => ({ ...p, md: await fetchPage(p.path) })));
  index = docs.flatMap((d) => {
    // one entry per page and per section, with its text
    const parts = d.md.split(/^(?=##+ )/m);
    return parts.map((part, n) => {
      const heading = n === 0 ? null : part.match(/^##+ (.*)$/m)[1];
      return { path: d.path, page: d.title, heading, id: heading ? slugify(heading) : null, text: part.replace(/[#>*`|_[\]()-]/g, " ").replace(/\s+/g, " ") };
    });
  });
  return index;
}
const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;" })[c]);
async function runSearch() {
  const q = $("q").value.trim().toLowerCase();
  const results = $("results");
  if (!q) { results.innerHTML = ""; return; }
  const words = q.split(/\s+/);
  const hits = (await buildIndex())
    .map((e) => {
      const hay = `${e.page} ${e.heading ?? ""} ${e.text}`.toLowerCase();
      if (!words.every((w) => hay.includes(w))) return null;
      const title = `${e.page} ${e.heading ?? ""}`.toLowerCase();
      return { e, score: words.reduce((s, w) => s + (title.includes(w) ? 10 : 1), 0) };
    })
    .filter(Boolean).sort((a, b) => b.score - a.score).slice(0, 12);
  selected = 0;
  if (!hits.length) { results.innerHTML = `<div class="empty">No matches for “${esc(q)}”</div>`; return; }
  const mark = (s) => esc(s).replace(new RegExp(`(${words.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")})`, "gi"), "<mark>$1</mark>");
  results.innerHTML = hits.map(({ e }, n) => {
    const at = e.text.toLowerCase().indexOf(words[0]);
    const snippet = e.text.slice(Math.max(0, at - 40), at + 90);
    const href = `#/${e.path}${e.id ? `?h=${e.id}` : ""}`;
    return `<li><a href="${href}" class="${n === 0 ? "sel" : ""}">${mark(e.page)}${e.heading ? ` › ${mark(e.heading)}` : ""}<small>…${mark(snippet)}…</small></a></li>`;
  }).join("");
}
const openSearch = () => { $("search").classList.add("open"); $("q").value = ""; $("results").innerHTML = ""; $("q").focus(); buildIndex(); };
const closeSearch = () => $("search").classList.remove("open");
$("search-open").onclick = openSearch;
$("search").onclick = (e) => { if (e.target === $("search")) closeSearch(); };
$("results").onclick = (e) => { if (e.target.closest("a")) closeSearch(); };
$("q").oninput = runSearch;
$("q").onkeydown = (e) => {
  const links = [...$("results").querySelectorAll("a")];
  if (e.key === "ArrowDown" || e.key === "ArrowUp") {
    e.preventDefault();
    selected = (selected + (e.key === "ArrowDown" ? 1 : -1) + links.length) % Math.max(links.length, 1);
    links.forEach((a, n) => a.classList.toggle("sel", n === selected));
    links[selected]?.scrollIntoView({ block: "nearest" });
  } else if (e.key === "Enter" && links[selected]) {
    location.hash = links[selected].getAttribute("href");
    closeSearch();
  }
};
if (!/Mac|iPhone|iPad/.test(navigator.platform)) $("search-key").textContent = "Ctrl K";
addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); openSearch(); }
  else if (e.key === "Escape") { closeSearch(); closeMenu(); }
  else if (e.key === "/" && document.activeElement === document.body) { e.preventDefault(); openSearch(); }
});

addEventListener("hashchange", show);
show();
