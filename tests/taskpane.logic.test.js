const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const projectRoot = path.join(__dirname, "..");
const source = fs.readFileSync(path.join(projectRoot, "js", "taskpane.js"), "utf8");
const writerMain = fs.readFileSync(path.join(projectRoot, "main.js"), "utf8");
const pptMain = fs.readFileSync(path.join(projectRoot, "ppt", "main.js"), "utf8");
const writerRibbon = fs.readFileSync(path.join(projectRoot, "js", "ribbon.js"), "utf8");
const pptRibbon = fs.readFileSync(path.join(projectRoot, "js", "ribbon-ppt.js"), "utf8");

for (const main of [writerMain, pptMain]) {
  assert(main.includes("js/taskpane.js"));
  assert(!/license|tweetnacl/i.test(main));
}
assert(writerRibbon.includes("openPackaged"));
assert(pptRibbon.includes("openPackaged"));
for (const forbidden of [
  "openLocalEditor",
  "ShellExecute",
  "OAAssist",
  "XMLHttpRequest",
  "WpsHighSchoolMathEditorHost",
  "127.0.0.1",
  "localhost"
]) {
  assert(!source.includes(forbidden), `taskpane manager still contains forbidden runtime text: ${forbidden}`);
}

function createContext(url = "file:///C:/plugin/index.html", buildVersion = "dev") {
  const values = {};
  const calls = [];
  const timers = [];
  const panes = {};
  let nextPane = 1;
  const app = {
    PluginStorage: {
      getItem(key) {
        return values[key] || "";
      },
      setItem(key, value) {
        values[key] = String(value);
      }
    },
    CreateTaskPane(paneUrl, title) {
      calls.push(["CreateTaskPane", paneUrl, title]);
      const pane = { ID: `pane-${nextPane++}`, Visible: false, Width: 0, DockPosition: 0 };
      panes[pane.ID] = pane;
      return pane;
    },
    GetTaskPane(id) {
      return panes[id] || null;
    }
  };
  const window = {
    Application: app,
    document: { location: { toString: () => url } },
    setTimeout(callback, delay) {
      timers.push({ callback, delay });
    }
  };
  const context = { window, document: window.document, console };
  vm.createContext(context);
  vm.runInContext(source.replace("__PLUGIN_VERSION__", buildVersion), context);
  return { context, app, values, calls, timers, panes, window };
}

function queryValue(url, key) {
  const match = new RegExp(`[?&]${key}=([^&#]+)`).exec(url);
  return match ? decodeURIComponent(match[1]) : "";
}

const version = require("../package.json").version;
const base = "file:///C:/Program%20Files/WPS%20Math";
for (const role of ["writer", "presentation"]) {
  const { context, app, values, calls, timers, panes, window } = createContext(base + "/index.html", version);
  const api = context.MathTaskPanes;
  const ready = [];
  const failures = [];
  const options = { app, role, name: "function-plot", pluginBaseUrl: base, onReady: () => ready.push(true), onFailure: r => failures.push(r) };
  assert.equal(api._private.versionedPagePath("function-plot"), "ui/function-plot-" + version + ".html");
  for (const name of ["tool-center", "license", "../remote", "constructor"]) {
    assert.equal(api.openPackaged({ ...options, name }), false);
  }
  assert.equal(api.openPackaged({ ...options, pluginBaseUrl: "file:///C:/other" }), false);
  assert.equal(api._private.isSafeFileUrl(base + "/../other"), false);
  assert.equal(api.openPackaged(options), true);
  api.openPackaged(options);
  assert.equal(calls.length, 1);
  const url = calls[0][1];
  assert(url.startsWith(base + "/ui/function-plot-" + version + ".html?"));
  assert.equal(queryValue(url, "hsmHost"), role);
  assert.equal(queryValue(url, "hsmPane"), "function-plot");
  assert.equal(calls[0][2], "函数编辑器");
  assert.equal(panes["pane-1"].Width, 420);
  assert.equal(panes["pane-1"].DockPosition, 2);
  const location = window.document.location;
  for (const incorrect of [url.replace("file://", "https://"), url.replace("-" + version, ""), url.replace(queryValue(url, "hsmToken"), "stale")]) {
    location.toString = () => incorrect;
    assert.equal(api.signalReady("function-plot"), false);
  }
  location.toString = () => url;
  assert.equal(api.signalReady("license"), false);
  assert.equal(api.signalReady("function-plot"), true);
  location.toString = () => base + "/index.html";
  timers.shift().callback();
  assert.equal(ready.length, 1);
  panes["pane-1"].Visible = false;
  assert.equal(api.openPackaged(options), true);
  assert.equal(panes["pane-1"].Visible, true);
  assert.equal(calls.length, 1);
  delete panes["pane-1"];
  api.openPackaged(options);
  assert.equal(calls.length, 2, "a deleted pane is recreated");
  timers.shift().callback();
  assert.equal(calls.length, 3, "no ready signal permits exactly one retry");
  timers.shift().callback();
  assert.deepStrictEqual(failures, ["not-ready"]);
  assert(!panes["pane-2"].Visible && !panes["pane-3"].Visible);
  app.CreateTaskPane = () => null;
  api.openPackaged(options);
  assert.deepStrictEqual(failures, ["not-ready", "create-failed"]);
  assert(!Object.keys(values).some(key => /license|trial/.test(key)));
}
const remote = createContext("https://example.invalid/plugin/index.html", version);
assert.equal(remote.context.MathTaskPanes.openPackaged({ app: remote.app, role: "writer", name: "function-plot" }), false);
console.log("single packaged pane, readiness, reuse, close, timeout and native fallback passed");
