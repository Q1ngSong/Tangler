const desktop = document.querySelector(".desktop");
const modeButtons = [...document.querySelectorAll(".mode-picker button")];
const modes = modeButtons.map((button) => button.dataset.mode);
const appButtons = [...document.querySelectorAll(".tab-group button")];
const motionButton = document.querySelector(".motion-toggle");
const preference = window.matchMedia("(prefers-reduced-motion: reduce)");
const searchInput = document.querySelector(".command-search-input");
const status = document.querySelector("#demo-status");
const windows = {
  browser: { title: "Field Notes", app: "Safari", style: "safari", headline: "Room to think." },
  reading: { title: "Reading list", app: "Safari", style: "safari", headline: "A little inspiration." },
  notes: { title: "Notes", app: "Notes", style: "notes", headline: "A clearer headspace." },
  files: { title: "Ideas", app: "Finder", style: "files", headline: "Everything, together." },
};
const hints = {
  layout: [["right ⌘", "←"], "Left half"],
  tabs: [["right ⌘", "T, T"], "Group windows"],
  workspace: [["right ⌘", "W, 1"], "Open workspace"],
  switcher: [["⌘", "⇥"], "Switch windows"],
  dock: [[], "Hover a Dock icon · choose a window"],
  search: [["right ⌘", "Space"], "Search commands and windows"],
};
const commands = [
  { title: "Left half", detail: "Layout", keys: "←", scene: "layout" },
  { title: "Group windows", detail: "Tab groups", keys: "T, T", scene: "tabs" },
  { title: "Open Design workspace", detail: "Workspaces", keys: "W, 1", scene: "workspace" },
  { title: "Notes", detail: "Window", keys: "↵", window: "notes" },
];
let timer;
let phaseTimer;
let playing = !preference.matches;

function hint(keys, label) {
  const content = [];
  keys.forEach((key, index) => {
    if (index) {
      const plus = document.createElement("span");
      plus.className = "command-plus";
      plus.textContent = "+";
      content.push(plus);
    }
    const keycap = document.createElement("kbd");
    keycap.textContent = key;
    content.push(keycap);
  });
  const text = document.createElement("span");
  text.className = "command-label";
  text.textContent = label;
  document.querySelector(".command-hint").replaceChildren(...content, text);
}

function updateVisibility() {
  const scene = desktop.dataset.scene;
  for (const [selector, shown] of [
    [".tab-group", scene === "tabs"],
    [".switcher-preview", desktop.dataset.mode === "switcher" && desktop.dataset.open === "true"],
    [".dock-stage", desktop.dataset.mode === "dock"],
    [".dock-preview", desktop.dataset.mode === "dock" && desktop.dataset.open === "true"],
    [".search-preview", desktop.dataset.mode === "search" && desktop.dataset.open === "true"],
  ]) {
    const element = document.querySelector(selector);
    element.inert = !shown;
    element.setAttribute("aria-hidden", String(!shown));
  }
  for (const name of Object.keys(windows)) {
    const visible = name === "files"
      ? ["workspace", "switcher"].includes(scene) || desktop.dataset.focus === "files"
      : name === "reading"
        ? desktop.dataset.mode === "dock" && desktop.dataset.focus === "reading"
        : scene !== "tabs" || desktop.dataset.active === name;
    document.querySelector(`.${name}-window`).setAttribute("aria-hidden", String(!visible));
  }
  appButtons.forEach((button) => {
    button.tabIndex = scene === "tabs" ? 0 : -1;
    button.setAttribute("aria-pressed", String(button.dataset.app === desktop.dataset.active));
  });
}

function setMode(mode, announce = false) {
  clearTimeout(phaseTimer);
  desktop.dataset.mode = mode;
  desktop.dataset.scene = mode;
  desktop.dataset.phase = "rest";
  desktop.dataset.focus = "";
  desktop.dataset.open = "true";
  modeButtons.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.mode === mode)));
  hint(...hints[mode]);
  if (mode === "dock") showDock("browser");
  if (mode === "search") {
    searchInput.value = "";
    renderCommands();
  }
  updateVisibility();
  if (preference.matches) desktop.dataset.phase = "active";
  else phaseTimer = setTimeout(() => { desktop.dataset.phase = "active"; }, 700);
  if (announce) {
    status.textContent = hints[mode][1] + " preview selected.";
    if (mode === "search") searchInput.focus({ preventScroll: true });
  }
}

function focusWindow(name) {
  setPlayback(false);
  desktop.dataset.focus = name;
  desktop.dataset.open = "false";
  hint(hints[desktop.dataset.mode][0], windows[name].title + " brought to front");
  updateVisibility();
  modeButtons.find((button) => button.dataset.mode === desktop.dataset.mode).focus({ preventScroll: true });
  status.textContent = windows[name].title + " brought to the front in the preview.";
}

function windowCard(name) {
  const app = windows[name];
  const button = document.createElement("button");
  button.type = "button";
  button.className = "window-choice";
  button.setAttribute("aria-label", `Bring ${app.title} to front`);
  button.dataset.window = name;
  const thumbnail = document.createElement("span");
  thumbnail.className = "window-thumbnail thumbnail-" + name;
  thumbnail.setAttribute("aria-hidden", "true");
  const headline = document.createElement("span");
  headline.textContent = app.headline;
  thumbnail.append(headline);
  const caption = document.createElement("span");
  caption.className = "window-choice-label";
  const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  icon.setAttribute("class", "app-icon preview-app-icon");
  icon.setAttribute("viewBox", "0 0 64 64");
  icon.setAttribute("aria-hidden", "true");
  const artwork = document.createElementNS("http://www.w3.org/2000/svg", "use");
  artwork.setAttribute("href", "#preview-" + app.style);
  icon.append(artwork);
  caption.append(icon, document.createTextNode(app.title));
  button.append(thumbnail, caption);
  button.addEventListener("click", () => focusWindow(name));
  return button;
}

function showDock(app) {
  desktop.dataset.open = "true";
  desktop.dataset.dock = app;
  const choices = app === "browser" ? ["browser", "reading"] : ["notes"];
  document.querySelector(".dock-windows").replaceChildren(...choices.map(windowCard));
  document.querySelector(".dock-preview-title").textContent = windows[app].app;
  document.querySelectorAll(".dock-app").forEach((button) =>
    button.setAttribute("aria-pressed", String(button.dataset.app === app)),
  );
  updateVisibility();
}

function renderCommands() {
  const query = searchInput.value.trim().toLowerCase();
  const matches = commands.filter((command) => `${command.title} ${command.detail}`.toLowerCase().includes(query));
  const results = matches.map((command) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "search-result";
    const title = document.createElement("span");
    title.textContent = command.title;
    const detail = document.createElement("small");
    detail.textContent = command.detail;
    const key = document.createElement("kbd");
    key.textContent = command.keys;
    title.append(detail);
    button.append(title, key);
    button.addEventListener("click", () => {
      if (command.window) return focusWindow(command.window);
      setPlayback(false);
      desktop.dataset.scene = command.scene;
      desktop.dataset.open = "false";
      desktop.dataset.phase = "active";
      hint(...hints[command.scene]);
      updateVisibility();
      modeButtons.find((item) => item.dataset.mode === "search").focus({ preventScroll: true });
      status.textContent = command.title + " applied in the preview.";
    });
    return button;
  });
  document.querySelector(".search-results").replaceChildren(...results);
  document.querySelector(".search-empty").hidden = matches.length !== 0;
  document.querySelector(".search-count").textContent = `${matches.length} ${matches.length === 1 ? "result" : "results"}`;
}

function setPlayback(enabled) {
  playing = enabled;
  clearInterval(timer);
  motionButton.setAttribute("aria-pressed", String(enabled));
  motionButton.setAttribute("aria-label", enabled ? "Pause automatic preview" : "Play automatic preview");
  document.querySelector(".motion-symbol").textContent = enabled ? "Ⅱ" : "▶";
  document.body.classList.toggle("motion-paused", !enabled);
  if (enabled && !document.hidden)
    timer = setInterval(() => setMode(modes[(modes.indexOf(desktop.dataset.mode) + 1) % modes.length]), 7000);
}

document.querySelector(".switcher-windows").replaceChildren(...["browser", "notes", "files"].map(windowCard));
modeButtons.forEach((button) => button.addEventListener("click", () => {
  setPlayback(false);
  setMode(button.dataset.mode, true);
}));
appButtons.forEach((button) => button.addEventListener("click", () => {
  setPlayback(false);
  desktop.dataset.active = button.dataset.app;
  updateVisibility();
  status.textContent = windows[button.dataset.app].title + " brought to the front in the preview.";
}));
document.querySelectorAll(".dock-app").forEach((button) => {
  for (const event of ["pointerenter", "focus", "click"])
    button.addEventListener(event, () => { setPlayback(false); showDock(button.dataset.app); });
});
desktop.addEventListener("focusin", () => setPlayback(false));
searchInput.addEventListener("input", renderCommands);
searchInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    document.querySelector(".search-result")?.click();
  } else if (event.key === "ArrowDown") {
    event.preventDefault();
    document.querySelector(".search-result")?.focus();
  }
});
desktop.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && ["search", "switcher", "dock"].includes(desktop.dataset.mode)) {
    desktop.dataset.open = "false";
    updateVisibility();
    modeButtons.find((button) => button.dataset.mode === desktop.dataset.mode).focus({ preventScroll: true });
    status.textContent = "Preview closed. Select the feature again to reopen it.";
  }
});
motionButton.addEventListener("click", () => setPlayback(!playing));
preference.addEventListener("change", () => { setPlayback(!preference.matches); setMode(desktop.dataset.mode); });
document.addEventListener("visibilitychange", () => setPlayback(playing));
setMode("layout");
setPlayback(playing);

if ("IntersectionObserver" in window) {
  const reveals = document.querySelectorAll(".download-section > div, .guide-heading");
  const observer = new IntersectionObserver((entries) => entries.forEach((entry) => {
    if (entry.isIntersecting) { entry.target.classList.add("visible"); observer.unobserve(entry.target); }
  }), { threshold: 0.1 });
  reveals.forEach((element) => { element.classList.add("reveal"); observer.observe(element); });
  const links = [...document.querySelectorAll(".guide-nav a")];
  const sections = new IntersectionObserver((entries) => entries.forEach((entry) => {
    if (entry.isIntersecting) links.forEach((link) => link.classList.toggle("current", link.hash === "#" + entry.target.id));
  }), { rootMargin: "-5% 0px -70% 0px" });
  document.querySelectorAll(".readme-content h2").forEach((heading) => sections.observe(heading));
}
