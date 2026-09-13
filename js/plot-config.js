(function (root, factory) {
  var api = factory();
  root.MathPlotConfig = api;
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
})(typeof window !== "undefined" ? window : globalThis, function () {
  var MAX_CURVES = 12;
  var COLORS = ["#2563eb", "#dc2626", "#059669", "#7c3aed", "#d97706", "#0891b2"];
  var LINE_STYLES = ["solid", "dashed", "dotted", "dashdot"];
  var DEFAULT_CONFIG = {
    expressions: ["x^2"],
    bounds: { xMin: -10, xMax: 10, yMin: -10, yMax: 10 },
    options: { showTickLabels: true, showGrid: true, showBorder: true, showLegend: true }
  };

  function clone(value) { return JSON.parse(JSON.stringify(value)); }

  function number(value, label, optional) {
    if (value === null || value === undefined || String(value).trim() === "") {
      if (optional) { return null; }
      throw new Error(label + "不能为空。");
    }
    var result = Number(value);
    if (!isFinite(result) || Math.abs(result) > 1e9) {
      throw new Error(label + "请输入绝对值不超过十亿的有限数值。");
    }
    return result;
  }

  function normalizeBounds(input) {
    var source = input || {};
    var result = {
      xMin: number(source.xMin, "横坐标最小值"),
      xMax: number(source.xMax, "横坐标最大值"),
      yMin: number(source.yMin, "纵坐标最小值"),
      yMax: number(source.yMax, "纵坐标最大值")
    };
    if (result.xMax - result.xMin < 1e-8) {
      throw new Error("横坐标范围无效：最大值须大于最小值，间距至少为 0.00000001。");
    }
    if (result.yMax - result.yMin < 1e-8) {
      throw new Error("纵坐标范围无效：最大值须大于最小值，间距至少为 0.00000001。");
    }
    return result;
  }

  function normalizeCurve(input, index) {
    var source = input || {};
    var domain = source.domain || {};
    var minimum = number(domain.min, "定义域左端", true);
    var maximum = number(domain.max, "定义域右端", true);
    if (minimum !== null && maximum !== null && minimum >= maximum) {
      throw new Error("定义域右端必须大于左端。");
    }
    var color = source.color || COLORS[index % COLORS.length];
    if (!/^#[0-9a-f]{6}$/i.test(color)) { throw new Error("曲线颜色无效。"); }
    var style = source.lineStyle || "solid";
    if (LINE_STYLES.indexOf(style) < 0) { throw new Error("曲线线型无效。"); }
    return {
      color: color.toLowerCase(),
      lineStyle: style,
      visible: source.visible !== false,
      domain: {
        min: minimum, max: maximum,
        minClosed: domain.minClosed !== false, maxClosed: domain.maxClosed !== false
      }
    };
  }

  function normalizePoints(input) {
    if (!Array.isArray(input) || input.length > 30) {
      throw new Error("坐标点最多支持 30 个。");
    }
    return input.map(function (point, index) {
      if (!point || typeof point !== "object") { throw new Error("第 " + (index + 1) + " 个坐标点无效。"); }
      var label = String(point.label || "").trim();
      if (label.length > 30) { throw new Error("坐标点名称最多 30 个字符。"); }
      return { label: label, x: number(point.x, "点的横坐标"), y: number(point.y, "点的纵坐标") };
    });
  }

  // Keep legacy configs minimal; optional V2 fields are added only when supplied.
  function normalizeConfig(input) {
    var source = input || {};
    if (!Array.isArray(source.expressions)) { throw new Error("请至少输入一个函数表达式。"); }
    if (source.expressions.length > MAX_CURVES) { throw new Error("最多支持 " + MAX_CURVES + " 条曲线，请删除多余行。"); }
    if (source.curves !== undefined && (!Array.isArray(source.curves) || source.curves.length !== source.expressions.length)) {
      throw new Error("曲线设置与表达式数量不一致。");
    }
    var expressions = [];
    var curves = [];
    source.expressions.forEach(function (entry, index) {
      var expression = String(entry === null || entry === undefined ? "" : entry).trim();
      if (!expression) { return; }
      try {
        if (expression.length > 1000) { throw new Error("表达式过长，请缩短到 1000 个字符以内。"); }
        curves.push(normalizeCurve(source.curves && source.curves[index], index));
      } catch (error) {
        error.message = "第 " + (index + 1) + " 条函数：" + error.message;
        error.curveIndex = index;
        throw error;
      }
      expressions.push(expression);
    });
    if (!expressions.length) { throw new Error("请至少输入一个函数表达式。"); }
    var options = source.options || {};
    var result = {
      expressions: expressions,
      bounds: normalizeBounds(source.bounds),
      options: {
        showTickLabels: options.showTickLabels !== false,
        showGrid: options.showGrid !== false,
        showBorder: options.showBorder !== false,
        showLegend: options.showLegend !== false
      }
    };
    if (source.curves !== undefined) { result.curves = curves; }
    if (source.points !== undefined) { result.points = normalizePoints(source.points); }
    if (options.monochrome !== undefined) { result.options.monochrome = options.monochrome === true; }
    return result;
  }

  return {
    MAX_CURVES: MAX_CURVES,
    COLORS: COLORS.slice(),
    LINE_STYLES: LINE_STYLES.slice(),
    normalizeCurve: normalizeCurve,
    normalizeBounds: normalizeBounds,
    normalizeConfig: normalizeConfig,
    getDefaultConfig: function () { return clone(DEFAULT_CONFIG); }
  };
});
