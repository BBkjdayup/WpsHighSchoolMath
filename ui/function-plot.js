var currentPlot = null;
var currentConfig = null;
var editingSelectedPlot = false;
var renderedEditingMode = null;
var selectionMonitorId = null;

var PRESETS = {
  quadratic: { expression: "x^2" },
  absolute: { expression: "abs(x)" },
  reciprocal: { expression: "1/x" },
  sine: { expression: "sin(x)" },
  cosine: { expression: "cos(x)" },
  exponential: { expression: "2^x" },
  logarithm: { expression: "log(x)" }
};

function node(id) {
  return document.getElementById(id);
}

function elements(selector) {
  var list = document.querySelectorAll(selector);
  var result = [];
  for (var index = 0; index < list.length; index += 1) {
    result.push(list[index]);
  }
  return result;
}

function setStatus(message, isError) {
  node("status").textContent = message;
  node("status").className = isError ? "status error" : "status";
}

function setEditingMode(isEditing) {
  editingSelectedPlot = Boolean(isEditing);
  if (renderedEditingMode === editingSelectedPlot) {
    return;
  }
  renderedEditingMode = editingSelectedPlot;
  node("editModeBadge").textContent = editingSelectedPlot ? "编辑所选图像" : "新建图像";
  node("editModeBadge").className = editingSelectedPlot ? "mode-badge editing" : "mode-badge";
  node("insertButton").textContent = editingSelectedPlot ? "更新所选图像" : "插入新图像";
}

function expressionInputs() {
  return elements(".expression-input");
}

function refreshRemoveButtons() {
  var rows = elements(".expression-row");
  rows.forEach(function (row, index) {
    var input = row.querySelector(".expression-input");
    var remove = row.querySelector(".remove-expression");
    input.setAttribute("aria-label", "函数表达式 " + (index + 1));
    remove.setAttribute("aria-label", "删除函数表达式 " + (index + 1));
    remove.disabled = rows.length === 1;
  });
}

function addExpressionRow(value, focusInput) {
  var row = document.createElement("div");
  row.className = "expression-row";

  var prefix = document.createElement("span");
  prefix.className = "expression-prefix";
  prefix.textContent = "y =";

  var input = document.createElement("input");
  input.type = "text";
  input.className = "expression-input";
  input.value = value || "";
  input.placeholder = "例如：x^2 或 sin(x)";
  input.addEventListener("keydown", function (event) {
    if (event.key === "Enter" || event.keyCode === 13) {
      event.preventDefault();
      addExpressionRow("", true);
    }
  });

  var remove = document.createElement("button");
  remove.type = "button";
  remove.className = "remove-expression";
  remove.title = "删除这一行";
  remove.textContent = "×";
  remove.addEventListener("click", function () {
    if (row.parentNode) {
      row.parentNode.removeChild(row);
    }
    refreshRemoveButtons();
    renderPreview();
  });

  row.appendChild(prefix);
  row.appendChild(input);
  row.appendChild(remove);
  node("expressionRows").appendChild(row);
  refreshRemoveButtons();
  if (focusInput) {
    input.focus();
  }
  return input;
}

function resetExpressionRows(values) {
  var expressions = Array.isArray(values) ? values : [values || ""];
  node("expressionRows").innerHTML = "";
  expressions.forEach(function (value) { addExpressionRow(value, false); });
  if (!expressions.length) {
    addExpressionRow("", false);
  }
}

function readPlotInput() {
  var input = {
    expressions: expressionInputs().map(function (entry) { return entry.value; }),
    bounds: {
      xMin: node("xMin").value,
      xMax: node("xMax").value,
      yMin: node("yMin").value,
      yMax: node("yMax").value
    },
    options: {
      showTickLabels: node("showTickLabels").checked,
      showGrid: node("showGrid").checked,
      showBorder: node("showBorder").checked,
      showLegend: node("showLegend").checked
    }
  };
  if (window.MathFunctionDocument) {
    return window.MathFunctionDocument.normalizeConfig(input);
  }
  return input;
}

function applyConfig(config, editing) {
  var normalized = window.MathFunctionDocument ?
    window.MathFunctionDocument.normalizeConfig(config) : config;
  resetExpressionRows(normalized.expressions);
  node("xMin").value = normalized.bounds.xMin;
  node("xMax").value = normalized.bounds.xMax;
  node("yMin").value = normalized.bounds.yMin;
  node("yMax").value = normalized.bounds.yMax;
  node("showTickLabels").checked = normalized.options.showTickLabels !== false;
  node("showGrid").checked = normalized.options.showGrid !== false;
  node("showBorder").checked = normalized.options.showBorder !== false;
  node("showLegend").checked = normalized.options.showLegend !== false;
  setEditingMode(editing);
  renderPreview();
}

function renderPreview() {
  try {
    currentConfig = readPlotInput();
    currentPlot = FunctionPlotter.generatePlotSvg(
      currentConfig.expressions,
      currentConfig.bounds,
      currentConfig.options
    );
    node("preview").innerHTML = currentPlot.svg;
    setStatus("预览已更新，可" + (editingSelectedPlot ? "更新所选图像。" : "插入到 WPS。"), false);
    return true;
  } catch (error) {
    currentPlot = null;
    currentConfig = null;
    node("preview").innerHTML = "";
    setStatus(error.message || String(error), true);
    return false;
  }
}

function getApplication() {
  return window.Application || window.wps || null;
}

function synchronizeSelectionMode() {
  var selected = null;
  try {
    var app = getApplication();
    if (app && window.MathFunctionDocument) {
      selected = window.MathFunctionDocument.getSelectedPlot(app);
    }
  } catch (_) {
    selected = null;
  }
  setEditingMode(Boolean(selected));
  return Boolean(selected);
}

function startSelectionMonitor() {
  synchronizeSelectionMode();
  if (selectionMonitorId !== null || typeof window.setInterval !== "function") {
    return selectionMonitorId;
  }
  selectionMonitorId = window.setInterval(synchronizeSelectionMode, 250);
  return selectionMonitorId;
}

function tempFilePath(app) {
  if (!app.FileSystem || !app.Env) {
    throw new Error("当前 WPS 版本缺少插入函数图像所需的文件接口。");
  }
  var tempDirectory = String(app.Env.GetTempPath());
  var separator = tempDirectory.charAt(tempDirectory.length - 1) === "\\" ? "" : "\\";
  var unique = Date.now() + "-" + Math.floor(Math.random() * 1000000);
  return tempDirectory + separator + "math-function-plot-" + unique + ".svg";
}

function writePlotFile(app, path) {
  if (!app.FileSystem.WriteFile(path, currentPlot.svg)) {
    throw new Error("无法写入临时图像文件");
  }
}

function loadSelectedPlot(showMissingMessage) {
  var app = getApplication();
  if (!app || !window.MathFunctionDocument) {
    if (showMissingMessage) {
      setStatus("当前 WPS 版本无法读取所选函数图像。", true);
    }
    return false;
  }
  try {
    var selected = window.MathFunctionDocument.getSelectedPlot(app);
    if (!selected) {
      setEditingMode(false);
      if (showMissingMessage) {
        setStatus("请先在文档或幻灯片中选中由本插件生成的函数图像。", true);
      }
      return false;
    }
    applyConfig(selected.config, true);
    setStatus("已载入所选函数图像，可修改后点击“更新所选图像”。", false);
    return true;
  } catch (error) {
    setStatus("无法读取所选函数图像：" + error.message, true);
    return false;
  }
}

function insertCurrentPlot() {
  if (window.MathLicense && !window.MathLicense.requirePaidFeature("插入函数图像")) {
    setStatus("试用已到期，请激活后继续插入函数图像。", true);
    return;
  }
  if (!window.MathFunctionDocument) {
    setStatus("函数图像文档组件未加载，请关闭 WPS 后重试。", true);
    return;
  }
  if (!renderPreview()) {
    return;
  }

  var app = getApplication();
  if (!app) {
    setStatus("当前未连接到 WPS。", true);
    return;
  }
  var path = "";
  try {
    path = tempFilePath(app);
    writePlotFile(app, path);
    var result = window.MathFunctionDocument.insertOrUpdate(app, path, currentPlot, currentConfig);
    var placementMessage = "";
    if (!result.updated && result.host === "presentation" && result.placement) {
      placementMessage = result.placement.overlapArea > 0 ?
        " 当前页没有完整空白区域，已采用最低重叠位置。" :
        " 已自动避开当前页已有内容。";
    }
    setEditingMode(result.updated || result.host === "presentation");
    setStatus(result.message + placementMessage, false);
  } catch (error) {
    setStatus("无法插入函数图像：" + error.message, true);
  } finally {
    if (path) {
      try { app.FileSystem.Remove(path); } catch (_) {}
    }
  }
}

function applyPreset(name) {
  var preset = PRESETS[name];
  if (!preset) {
    return;
  }
  var emptyInput = expressionInputs().filter(function (input) {
    return !input.value.trim();
  })[0];
  if (emptyInput) {
    emptyInput.value = preset.expression;
  } else {
    addExpressionRow(preset.expression, false);
  }
  renderPreview();
}

window.addEventListener("DOMContentLoaded", function () {
  var defaultConfig = window.MathFunctionDocument ?
    window.MathFunctionDocument.getDefaultConfig() : {
      expressions: ["x^2"],
      bounds: { xMin: -10, xMax: 10, yMin: -10, yMax: 10 },
      options: { showTickLabels: true, showGrid: true, showBorder: true, showLegend: true }
    };
  applyConfig(defaultConfig, false);
  node("addExpressionButton").addEventListener("click", function () {
    addExpressionRow("", true);
  });
  node("loadSelectionButton").addEventListener("click", function () {
    loadSelectedPlot(true);
  });
  node("previewButton").addEventListener("click", renderPreview);
  node("insertButton").addEventListener("click", insertCurrentPlot);
  ["showTickLabels", "showGrid", "showBorder", "showLegend"].forEach(function (id) {
    node(id).addEventListener("change", renderPreview);
  });
  elements("[data-preset]").forEach(function (button) {
    button.addEventListener("click", function () {
      applyPreset(button.getAttribute("data-preset"));
    });
  });

  if (!loadSelectedPlot(false)) {
    setStatus("可输入多条函数并设置坐标范围；选中旧图后可点“载入所选图像”重新编辑。", false);
  }
  startSelectionMonitor();
  if (window.MathTaskPanes && !window.HSM_TASK_PANE_NAME) {
    window.MathTaskPanes.signalReady("function-plot");
  }
});

window.MathFunctionPlotPanel = window.MathFunctionPlotPanel || {};
window.MathFunctionPlotPanel.synchronizeSelection = synchronizeSelectionMode;
window.MathFunctionPlotPanel.startSelectionMonitor = startSelectionMonitor;
window.MathFunctionPlotPanel.isEditingSelectedPlot = function () {
  return editingSelectedPlot;
};
