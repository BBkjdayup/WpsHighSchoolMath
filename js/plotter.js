(function (root, factory) {
  var api = factory();
  root.FunctionPlotter = api;
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
})(typeof window !== "undefined" ? window : globalThis, function () {
  var FUNCTIONS = {
    sin: Math.sin,
    cos: Math.cos,
    tan: Math.tan,
    cot: function (value) { return 1 / Math.tan(value); },
    sec: function (value) { return 1 / Math.cos(value); },
    csc: function (value) { return 1 / Math.sin(value); },
    asin: Math.asin,
    acos: Math.acos,
    atan: Math.atan,
    sqrt: Math.sqrt,
    abs: Math.abs,
    ln: Math.log,
    log: function (value) { return Math.log(value) / Math.LN10; },
    lg: function (value) { return FUNCTIONS.log(value); },
    exp: Math.exp,
    floor: Math.floor,
    ceil: Math.ceil,
    sign: Math.sign
  };

  var COLORS = ["#2563eb", "#dc2626", "#059669", "#7c3aed", "#d97706", "#0891b2"];

  function normalizeExpression(expression) {
    return String(expression || "")
      .trim()
      .replace(/^[yf]\s*(?:\(\s*x\s*\))?\s*=/i, "")
      .replace(/[−–—]/g, "-")
      .replace(/[×·]/g, "*")
      .replace(/÷/g, "/")
      .replace(/π/g, "pi")
      .replace(/√\s*\(/g, "sqrt(")
      .replace(/√\s*([A-Za-z]+|(?:\d+(?:\.\d*)?|\.\d+))/g, "sqrt($1)")
      .replace(/([A-Za-z0-9.)])²/g, "$1^2")
      .replace(/([A-Za-z0-9.)])³/g, "$1^3");
  }

  function rawTokens(expression) {
    var input = normalizeExpression(expression);
    var tokens = [];
    var index = 0;

    while (index < input.length) {
      var rest = input.slice(index);
      var whitespace = rest.match(/^\s+/);
      if (whitespace) {
        index += whitespace[0].length;
        continue;
      }

      var number = rest.match(/^(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?/i);
      if (number) {
        tokens.push({ type: "number", value: Number(number[0]) });
        index += number[0].length;
        continue;
      }

      var identifier = rest.match(/^[A-Za-z]+/);
      if (identifier) {
        tokens.push({ type: "identifier", value: identifier[0].toLowerCase() });
        index += identifier[0].length;
        continue;
      }

      var character = input[index];
      if ("+-*/^(),".indexOf(character) >= 0) {
        tokens.push({ type: character, value: character });
        index += 1;
        continue;
      }

      throw new Error("无法识别字符：" + character);
    }

    return addImplicitMultiplication(tokens);
  }

  function endsValue(token) {
    return token && (
      token.type === "number" ||
      token.type === "identifier" ||
      token.type === ")"
    );
  }

  function startsValue(token) {
    return token && (
      token.type === "number" ||
      token.type === "identifier" ||
      token.type === "("
    );
  }

  function addImplicitMultiplication(tokens) {
    var result = [];
    for (var index = 0; index < tokens.length; index += 1) {
      var current = tokens[index];
      var previous = result[result.length - 1];
      var isFunctionCall = previous &&
        previous.type === "identifier" &&
        FUNCTIONS[previous.value] &&
        current.type === "(";
      if (endsValue(previous) && startsValue(current) && !isFunctionCall) {
        result.push({ type: "*", value: "*" });
      }
      result.push(current);
    }
    return result;
  }

  function compileExpression(expression) {
    var tokens = rawTokens(expression);
    var position = 0;

    function peek(type) {
      return tokens[position] && tokens[position].type === type;
    }

    function take(type) {
      if (!peek(type)) {
        throw new Error("表达式格式错误，缺少 " + type);
      }
      return tokens[position++];
    }

    function combine(operator, left, right) {
      if (operator === "+") {
        return function (x) { return left(x) + right(x); };
      }
      if (operator === "-") {
        return function (x) { return left(x) - right(x); };
      }
      if (operator === "*") {
        return function (x) { return left(x) * right(x); };
      }
      return function (x) { return left(x) / right(x); };
    }

    function parseExpression() {
      var left = parseTerm();
      while (peek("+") || peek("-")) {
        var operator = tokens[position++].type;
        var right = parseTerm();
        left = combine(operator, left, right);
      }
      return left;
    }

    function parseTerm() {
      var left = parseUnary();
      while (peek("*") || peek("/")) {
        var operator = tokens[position++].type;
        var right = parseUnary();
        left = combine(operator, left, right);
      }
      return left;
    }

    function parseUnary() {
      if (peek("+")) {
        position += 1;
        return parseUnary();
      }
      if (peek("-")) {
        position += 1;
        var value = parseUnary();
        return function (x) { return -value(x); };
      }
      return parsePower();
    }

    function parsePower() {
      var base = parsePrimary();
      if (peek("^")) {
        position += 1;
        var exponent = parseUnary();
        return function (x) { return Math.pow(base(x), exponent(x)); };
      }
      return base;
    }

    function parsePrimary() {
      if (peek("number")) {
        var number = tokens[position++].value;
        return function () { return number; };
      }

      if (peek("identifier")) {
        var name = tokens[position++].value;
        if (name === "x") {
          return function (x) { return x; };
        }
        if (name === "pi") {
          return function () { return Math.PI; };
        }
        if (name === "e") {
          return function () { return Math.E; };
        }
        if (!FUNCTIONS[name]) {
          throw new Error("不支持的函数或变量：" + name);
        }
        take("(");
        var argument = parseExpression();
        take(")");
        return function (x) { return FUNCTIONS[name](argument(x)); };
      }

      if (peek("(")) {
        position += 1;
        var value = parseExpression();
        take(")");
        return value;
      }

      throw new Error("表达式格式错误");
    }

    if (!tokens.length) {
      throw new Error("请输入函数表达式");
    }
    var evaluator = parseExpression();
    if (position !== tokens.length) {
      throw new Error("表达式末尾存在无法解析的内容");
    }
    return evaluator;
  }

  function evaluateExpression(expression, x) {
    return compileExpression(expression)(x);
  }

  function escapeXml(text) {
    return String(text || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&apos;");
  }

  function niceStep(range) {
    var rough = Math.abs(range) / 10;
    var power = Math.pow(10, Math.floor(Math.log(rough) / Math.LN10));
    var normalized = rough / power;
    var factor = normalized < 1.5 ? 1 : normalized < 3 ? 2 : normalized < 7 ? 5 : 10;
    return factor * power;
  }

  function formatNumber(value) {
    if (Math.abs(value) < 1e-10) {
      return "0";
    }
    if (Math.abs(value) >= 10000 || Math.abs(value) < 0.001) {
      return value.toExponential(1);
    }
    return String(Number(value.toFixed(4)));
  }

  function validateBounds(bounds) {
    var result = {
      xMin: Number(bounds.xMin),
      xMax: Number(bounds.xMax),
      yMin: Number(bounds.yMin),
      yMax: Number(bounds.yMax)
    };
    if (!isFinite(result.xMin) || !isFinite(result.xMax) || result.xMin >= result.xMax) {
      throw new Error("横坐标范围无效");
    }
    if (!isFinite(result.yMin) || !isFinite(result.yMax) || result.yMin >= result.yMax) {
      throw new Error("纵坐标范围无效");
    }
    return result;
  }

  function generatePlotSvg(expressions, bounds, options) {
    var formulas = expressions
      .map(normalizeExpression)
      .filter(function (value) { return value.length > 0; });
    if (!formulas.length) {
      throw new Error("请至少输入一个函数表达式");
    }

    var compiled = formulas.map(function (formula) {
      return { label: formula, evaluate: compileExpression(formula) };
    });
    var limits = validateBounds(bounds);
    var settings = options || {};
    var showTickLabels = settings.showTickLabels !== false;
    var showGrid = settings.showGrid !== false;
    var showBorder = settings.showBorder !== false;
    var showLegend = settings.showLegend !== false;
    var width = Number(settings.width) || 720;
    var height = Number(settings.height) || 460;
    var margin = {
      left: showTickLabels ? 62 : 30,
      right: 24,
      top: 16,
      bottom: showTickLabels ? 48 : 24
    };
    var legendItemWidth = 130;
    var availableLegendWidth = width - margin.left - margin.right;
    var legendItemsPerRow = showLegend ?
      Math.max(1, Math.floor(availableLegendWidth / legendItemWidth)) :
      0;
    var legendRows = showLegend ? Math.ceil(compiled.length / legendItemsPerRow) : 0;
    if (showLegend) {
      margin.top = 18 + legendRows * 20;
    }
    var plotWidth = width - margin.left - margin.right;
    var plotHeight = height - margin.top - margin.bottom;
    var xScale = plotWidth / (limits.xMax - limits.xMin);
    var yScale = plotHeight / (limits.yMax - limits.yMin);
    var clipId = "plotArea";

    function px(x) {
      return margin.left + (x - limits.xMin) * xScale;
    }

    function py(y) {
      return margin.top + (limits.yMax - y) * yScale;
    }

    var body = [];
    body.push('<rect x="0" y="0" width="' + width + '" height="' + height + '" fill="#fff"/>');
    body.push('<defs><clipPath id="' + clipId + '"><rect x="' + margin.left + '" y="' + margin.top + '" width="' + plotWidth + '" height="' + plotHeight + '"/></clipPath></defs>');
    body.push('<rect x="' + margin.left + '" y="' + margin.top + '" width="' + plotWidth + '" height="' + plotHeight + '" fill="#fff"' + (showBorder ? ' stroke="#94a3b8" stroke-width="1"' : "") + "/>");

    var xStep = niceStep(limits.xMax - limits.xMin);
    var yStep = niceStep(limits.yMax - limits.yMin);
    var firstX = Math.ceil(limits.xMin / xStep) * xStep;
    var firstY = Math.ceil(limits.yMin / yStep) * yStep;
    var value;

    for (value = firstX; value <= limits.xMax + xStep * 0.01; value += xStep) {
      var xPosition = px(value);
      if (showGrid) {
        body.push('<line x1="' + xPosition + '" y1="' + margin.top + '" x2="' + xPosition + '" y2="' + (margin.top + plotHeight) + '" stroke="#e2e8f0" stroke-width="1"/>');
      }
      if (showTickLabels) {
        body.push('<text x="' + xPosition + '" y="' + (height - 24) + '" text-anchor="middle" font-size="12" fill="#475569">' + formatNumber(value) + '</text>');
      }
    }
    for (value = firstY; value <= limits.yMax + yStep * 0.01; value += yStep) {
      var yPosition = py(value);
      if (showGrid) {
        body.push('<line x1="' + margin.left + '" y1="' + yPosition + '" x2="' + (margin.left + plotWidth) + '" y2="' + yPosition + '" stroke="#e2e8f0" stroke-width="1"/>');
      }
      if (showTickLabels) {
        body.push('<text x="' + (margin.left - 10) + '" y="' + (yPosition + 4) + '" text-anchor="end" font-size="12" fill="#475569">' + formatNumber(value) + '</text>');
      }
    }

    if (limits.yMin <= 0 && limits.yMax >= 0) {
      body.push('<line x1="' + margin.left + '" y1="' + py(0) + '" x2="' + (margin.left + plotWidth) + '" y2="' + py(0) + '" stroke="#334155" stroke-width="1.4"/>');
    }
    if (limits.xMin <= 0 && limits.xMax >= 0) {
      body.push('<line x1="' + px(0) + '" y1="' + margin.top + '" x2="' + px(0) + '" y2="' + (margin.top + plotHeight) + '" stroke="#334155" stroke-width="1.4"/>');
    }

    body.push('<g clip-path="url(#' + clipId + ')">');
    compiled.forEach(function (formula, formulaIndex) {
      var segments = [];
      var current = [];
      var lastY = null;
      var samples = Math.min(8000, Math.max(1000, Math.ceil(plotWidth * 2)));
      for (var index = 0; index <= samples; index += 1) {
        var x = limits.xMin + (limits.xMax - limits.xMin) * index / samples;
        var y;
        try {
          y = formula.evaluate(x);
        } catch (_) {
          y = NaN;
        }
        var screenY = py(y);
        var valid = isFinite(y) && Math.abs(y) < 1e12 && screenY > margin.top - plotHeight * 4 && screenY < margin.top + plotHeight * 5;
        var discontinuity = lastY !== null && Math.abs(screenY - lastY) > plotHeight * 1.5;
        if (!valid || discontinuity) {
          if (current.length > 1) {
            segments.push(current.join(" "));
          }
          current = [];
          lastY = null;
          continue;
        }
        current.push((current.length ? "L" : "M") + px(x).toFixed(2) + " " + screenY.toFixed(2));
        lastY = screenY;
      }
      if (current.length > 1) {
        segments.push(current.join(" "));
      }
      segments.forEach(function (path) {
        body.push('<path d="' + path + '" fill="none" stroke="' + COLORS[formulaIndex % COLORS.length] + '" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round"/>');
      });
    });
    body.push("</g>");

    if (showLegend) {
      compiled.forEach(function (formula, index) {
        var legendColumn = index % legendItemsPerRow;
        var legendRow = Math.floor(index / legendItemsPerRow);
        var legendX = margin.left + legendColumn * legendItemWidth;
        var legendY = 18 + legendRow * 20;
        body.push('<line x1="' + legendX + '" y1="' + legendY + '" x2="' + (legendX + 20) + '" y2="' + legendY + '" stroke="' + COLORS[index % COLORS.length] + '" stroke-width="3"/>');
        body.push('<text x="' + (legendX + 26) + '" y="' + (legendY + 4) + '" font-size="13" fill="#1e293b">y=' + escapeXml(formula.label) + '</text>');
      });
    }
    body.push('<text x="' + (margin.left + plotWidth + 8) + '" y="' + (py(0) - 6) + '" font-size="14" fill="#334155">x</text>');
    body.push('<text x="' + (px(0) + 7) + '" y="' + (margin.top + 14) + '" font-size="14" fill="#334155">y</text>');

    return {
      width: width,
      height: height,
      expressions: formulas,
      bounds: limits,
      svg: '<svg xmlns="http://www.w3.org/2000/svg" width="' + width + '" height="' + height + '" viewBox="0 0 ' + width + " " + height + '" role="img" aria-label="函数图像">' + body.join("") + "</svg>"
    };
  }

  return {
    normalizeExpression: normalizeExpression,
    compileExpression: compileExpression,
    evaluateExpression: evaluateExpression,
    generatePlotSvg: generatePlotSvg
  };
});
