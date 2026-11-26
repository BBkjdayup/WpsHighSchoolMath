const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const projectRoot = path.join(__dirname, "..");
const panelSource = fs.readFileSync(path.join(projectRoot, "ui", "function-plot.js"), "utf8");

const nodes = {
  editModeBadge: { textContent: "", className: "" },
  insertButton: { textContent: "" },
  status: {}
};
let selectedPlot = { host: "presentation", config: { expressions: ["x^2"] } };
let intervalCallback = null;
let intervalDelay = null;
let stopped = null;

const document = {
  getElementById(id) {
    return nodes[id] || null;
  },
  querySelectorAll() {
    return [];
  }
};

const window = {
  Application: { ActivePresentation: {} },
  MathFunctionDocument: {
    samePlot(a, b) { return a === b; },
    getSelectedPlot() {
      return selectedPlot;
    }
  },
  MathFunctionPlotPanel: {},
  addEventListener() {},
  setInterval(callback, delay) {
    intervalCallback = callback;
    intervalDelay = delay;
    return 17;
  },
  clearInterval(id) { stopped = id; }
};

const context = vm.createContext({
  window,
  document,
  FunctionPlotter: {},
  Date,
  Math,
  console
});
vm.runInContext(panelSource, context);

assert.equal(typeof window.MathFunctionPlotPanel.synchronizeSelection, "function");
assert.equal(typeof window.MathFunctionPlotPanel.startSelectionMonitor, "function");

assert.equal(window.MathFunctionPlotPanel.synchronizeSelection(), false, "a new selection never silently binds an edit");
context.applyConfig = () => true;
assert(context.loadSelectedPlot(true));
window.MathFunctionPlotPanel.startSelectionMonitor();
assert.equal(intervalDelay, 250);
assert.equal(typeof intervalCallback, "function");
assert.equal(window.MathFunctionPlotPanel.isEditingSelectedPlot(), true);
assert.equal(nodes.editModeBadge.textContent, "编辑所选图像");
assert.equal(nodes.editModeBadge.className, "mode-badge editing");
assert.equal(nodes.insertButton.textContent, "更新所选图像");

selectedPlot = null;
intervalCallback();
assert.equal(window.MathFunctionPlotPanel.isEditingSelectedPlot(), false);
assert.equal(nodes.editModeBadge.textContent, "新建图像");
assert.equal(nodes.editModeBadge.className, "mode-badge");
assert.equal(nodes.insertButton.textContent, "插入新图像");

selectedPlot = { host: "writer", config: { expressions: ["sin(x)"] } };
intervalCallback();
assert.equal(nodes.insertButton.textContent, "重新载入所选图像");
const oldTarget = context.loadedTarget;
context.insertCurrentPlot();
assert.notEqual(context.loadedTarget, oldTarget);
assert.equal(context.loadedTarget, selectedPlot);
intervalCallback();
assert.equal(nodes.insertButton.textContent, "更新所选图像");
window.MathFunctionPlotPanel.setVisible(false);
assert.equal(stopped, 17);
window.MathFunctionPlotPanel.setVisible(true);
assert.equal(window.MathFunctionPlotPanel.isEditingSelectedPlot(), true);

{
  let updatedSelection = { host: "writer", config: { expressions: ["cos(x)"] } };
  window.Application = {
    ActiveDocument: {},
    FileSystem: { WriteFile() { return true; }, Remove() {} },
    Env: { GetTempPath() { return "C:\\Temp"; } }
  };
  window.MathFunctionDocument.insertOrUpdate = function (app, filePath, plot, cfg, target) {
    assert.equal(target, selectedPlot);
    selectedPlot = updatedSelection;
    return { host: "writer", updated: true, message: "所选函数图像已更新。" };
  };
  context.renderPreview = function () {
    context.currentPlot = { svg: "<svg/>" };
    context.currentConfig = { expressions: ["cos(x)"] };
    return true;
  };
  context.insertCurrentPlot();
  assert.equal(context.loadedTarget, updatedSelection, "Writer update rebinds the newly replaced picture");
  assert.equal(window.MathFunctionPlotPanel.isEditingSelectedPlot(), true);
  assert.equal(nodes.insertButton.textContent, "更新所选图像");

  window.FunctionPlotter = require(path.join(projectRoot, "js", "plotter.js"));
  assert.equal(context.usesParameterControls({ expressions: ["x^2"], bounds: {} }), false);
  assert.equal(context.usesParameterControls({ expressions: ["a*x^2"], bounds: {} }), true);
  assert.equal(context.usesParameterControls({ expressions: ["x^2"], guides: [{ axis: "x", expression: "b" }], bounds: {} }), true);

  nodes.xMin = { value: "", validity: { badInput: true } };
  assert.throws(() => context.readNumberControl("xMin", "横坐标最小值"), /完整数值/);

  let reopenPending = true;
  window.MathTaskPanes = {
    consumeReopen() {
      const value = reopenPending;
      reopenPending = false;
      return value;
    }
  };
  context.loadedTarget = null;
  context.formModifiedByUser = true;
  selectedPlot = { host: "writer", config: { expressions: ["2*x"] } };
  window.MathFunctionPlotPanel.synchronizeSelection();
  assert(String(nodes.status.textContent).includes("载入所选图像"), "modified draft warns instead of overwriting on reopen");
}

{
  // Every plot control marks the draft; favorite name/list/backup text do not.
  const listeners = {};
  const fakeRoot = { addEventListener(type, handler, capture) { assert.equal(capture, true); listeners[type] = handler; } };
  assert.equal(context.trackFormModifications(fakeRoot), true);
  assert.equal(context.trackFormModifications(null), false);
  context.formModifiedByUser = false;
  listeners.input({ target: { id: "favoriteName" } });
  listeners.change({ target: { id: "favoriteList" } });
  listeners.input({ target: { id: "favoriteBackup" } });
  assert.equal(context.formModifiedByUser, false, "favorite name, list and backup text are not plot edits");
  listeners.input({ target: { id: "parameter-a-slider" } });
  assert.equal(context.formModifiedByUser, true, "a slider drag marks the draft as modified");
  context.formModifiedByUser = false;
  listeners.change({ target: { className: "curve-color" } });
  assert.equal(context.formModifiedByUser, true, "a curve style change marks the draft as modified");

  let reopenSignal = false;
  window.MathTaskPanes = { consumeReopen() { const value = reopenSignal; reopenSignal = false; return value; } };

  // A slider-only draft is kept when the pane reopens over a selected picture.
  context.loadedTarget = null;
  const draftTarget = { host: "writer", config: { expressions: ["3*x"] } };
  selectedPlot = draftTarget;
  reopenSignal = true;
  window.MathFunctionPlotPanel.synchronizeSelection();
  assert.equal(context.loadedTarget, null, "a modified draft is never replaced on reopen");

  // Loading a picture synchronizes the form and clears the draft flag.
  assert(context.loadSelectedPlot(true));
  assert.equal(context.formModifiedByUser, false);
  assert.equal(context.loadedTarget, draftTarget);

  // An untouched form auto-loads the picture selected while the pane was hidden.
  context.loadedTarget = null;
  const reopenedTarget = { host: "writer", config: { expressions: ["4*x"] } };
  selectedPlot = reopenedTarget;
  reopenSignal = true;
  window.MathFunctionPlotPanel.synchronizeSelection();
  assert.equal(context.loadedTarget, reopenedTarget, "an unmodified form loads the selected picture on reopen");

  // A successful insert writes the draft to the document and clears the flag.
  context.formModifiedByUser = true;
  window.MathFunctionDocument.insertOrUpdate = function () { return { host: "writer", updated: false, message: "函数图像已插入到 WPS 文字。" }; };
  context.insertCurrentPlot();
  assert.equal(context.formModifiedByUser, false, "a successful insert clears the draft flag");
}
console.log("plot target binding, selection changes and explicit reload passed");
