if (typeof SYMBOLS === "undefined") {
  throw new Error("js/symbols.js must be loaded before js/ribbon.js.");
}

var EXAM_TEMPLATES = {
  exam_header: "学校：____________　班级：____________　姓名：____________　考号：____________\r",
  choice_stem: "一、选择题：本题共____小题，每小题____分，共____分。\r",
  fill_stem: "二、填空题：本题共____小题，每小题____分，共____分。\r",
  answer_stem: "三、解答题：本题共____小题，共____分。解答应写出文字说明、证明过程或演算步骤。\r",
  choice_one_line: "____．题目内容（　　）\rA．选项A\tB．选项B\tC．选项C\tD．选项D\r",
  choice_two_lines: "____．题目内容（　　）\rA．选项A\tB．选项B\rC．选项C\tD．选项D\r",
  choice_four_lines: "____．题目内容（　　）\rA．选项A\rB．选项B\rC．选项C\rD．选项D\r",
  fill_blank: "____．________________________________\r",
  answer_question: "____．题目内容\r\r解：\r"
};

var COMMANDS = {
  exam_header: function () { return insertExamHeader(); },
  choice_stem: function () { return insertExamTemplate("choice_stem"); },
  fill_stem: function () { return insertExamTemplate("fill_stem"); },
  answer_stem: function () { return insertExamTemplate("answer_stem"); },
  choice_one_line: function () { return insertExamTemplate("choice_one_line"); },
  choice_two_lines: function () { return insertExamTemplate("choice_two_lines"); },
  choice_four_lines: function () { return insertExamTemplate("choice_four_lines"); },
  fill_blank: function () { return insertExamTemplate("fill_blank"); },
  answer_question: function () { return insertExamTemplate("answer_question"); },
  align_left: function () { return setParagraphAlignment(0); },
  align_center: function () { return setParagraphAlignment(1); },
  remove_spaces: function () { return removeSpaces(); },
  table_to_text: function () { return tableToText(); },
  line_spacing_more: function () { return adjustLineSpacing(1); },
  line_spacing_less: function () { return adjustLineSpacing(-1); },
  underline_add: function () { return setUnderline(true); },
  underline_remove: function () { return setUnderline(false); },
  emphasis_add: function () { return setEmphasis(true); },
  emphasis_remove: function () { return setEmphasis(false); },
  toggle_hidden: function () { return toggleHidden(); },
  page_a4: function () { return setPageLayout("a4-portrait"); },
  page_a4_two_column: function () { return setPageLayout("a4-landscape-2col"); },
  add_page_number: function () { return addPageNumber(); },
  function_plot: function () { return showFunctionPlotPane(); }
};

function OnAddinLoad(ribbonUI) {
  if (typeof window.Application.ribbonUI !== "object") {
    window.Application.ribbonUI = ribbonUI;
  }
  return true;
}

function OnAction(control) {
  var symbol = SYMBOLS[control.Id];
  if (symbol !== undefined) {
    return insertMathSymbol(symbol);
  }
  var command = COMMANDS[control.Id];
  return command ? command() : true;
}

function getApplication() {
  return window.Application;
}

function getPluginBaseUrl() {
  var url = document.location.toString().split(/[?#]/)[0];
  return url.substring(0, url.lastIndexOf("/"));
}

function showFunctionPlotPane() {
  var app = getApplication();
  function nativeFallback() {
    if (typeof MathFunctionPlot !== "undefined") {
      return MathFunctionPlot.openQuickWriter ?
        MathFunctionPlot.openQuickWriter(app) : MathFunctionPlot.openWriter(app);
    }
    alert("当前 WPS 版本无法打开函数编辑器。");
    return false;
  }
  if (!app || typeof MathTaskPanes === "undefined" ||
      typeof MathTaskPanes.openPackaged !== "function") {
    return nativeFallback();
  }
  return MathTaskPanes.openPackaged({
    app: app,
    pluginBaseUrl: getPluginBaseUrl(),
    role: "writer",
    name: "function-plot",
    width: 420,
    readyTimeout: 5000,
    onFailure: nativeFallback
  }) || nativeFallback();
}

function insertText(text) {
  var app = getApplication();
  if (!app || !app.ActiveDocument) {
    alert("请先打开或新建一个 WPS 文字文档。");
    return false;
  }

  try {
    app.Selection.TypeText(text);
    return true;
  } catch (error) {
    try {
      var range = app.Selection.Range;
      range.Text = text;
      range.Collapse(0);
      range.Select();
      return true;
    } catch (fallbackError) {
      alert("插入失败：" + fallbackError.message);
      return false;
    }
  }
}

function fontNames(font) {
  var names = {};
  ["Name", "NameAscii", "NameOther", "NameFarEast", "NameBi"].forEach(function (property) {
    try {
      names[property] = font[property];
    } catch (_) {
      // Some WPS versions do not expose every font-name property.
    }
  });
  return names;
}

function setFontNames(font, names) {
  Object.keys(names).forEach(function (property) {
    if (names[property] === undefined || names[property] === null || names[property] === "") {
      return;
    }
    try {
      font[property] = names[property];
    } catch (_) {
      // Preserve insertion when a WPS build rejects a font-name property.
    }
  });
}

function insertMathSymbol(text) {
  var app = getApplication();
  var doc = app && app.ActiveDocument;
  var selection = app && app.Selection;
  if (!doc || !selection) {
    alert("请先打开或新建一个 WPS 文字文档。");
    return false;
  }

  var originalFont = fontNames(selection.Font);
  try {
    var selectedRange = selection.Range;
    var insertedRange;
    try { insertedRange = selectedRange.Duplicate; } catch (_) {}
    if (!insertedRange) { insertedRange = selectedRange; }
    var canSetRange = typeof insertedRange.SetRange === "function";
    if (!canSetRange && !(Number(selectedRange.StoryType) === 1 && typeof doc.Range === "function")) {
      throw new Error("当前 WPS 无法定位本区域的符号，请将光标移动到正文后重试。");
    }
    selection.TypeText(text);
    var end = Number(selection.Range.End);
    if (canSetRange) { insertedRange.SetRange(end - text.length, end); }
    else { insertedRange = doc.Range(end - text.length, end); }
    setFontNames(insertedRange.Font, {
      Name: "Cambria Math",
      NameAscii: "Cambria Math",
      NameOther: "Cambria Math",
      NameFarEast: "Cambria Math",
      NameBi: "Cambria Math"
    });
    selection.SetRange(end, end);
    setFontNames(selection.Font, originalFont);
    return true;
  } catch (error) {
    alert("插入数学符号失败：" + error.message);
    return false;
  }
}

function getSelection() {
  var app = getApplication();
  if (!app || !app.ActiveDocument || !app.Selection) {
    alert("请先打开或新建一个 WPS 文字文档。");
    return null;
  }
  return app.Selection;
}

function insertExamTemplate(templateId) {
  var template = EXAM_TEMPLATES[templateId];
  return template !== undefined ? insertText(template) : false;
}

var EXAM_HEADER_BOOKMARK = "HSMExamHeader";

function getExamHeaderSection(doc) {
  try {
    if (!doc || !doc.Bookmarks || !doc.Bookmarks.Exists(EXAM_HEADER_BOOKMARK)) {
      return null;
    }
    return doc.Bookmarks.Item(EXAM_HEADER_BOOKMARK).Range.Sections.Item(1);
  } catch (_) {
    return null;
  }
}

function insertExamHeader() {
  var app = getApplication();
  var doc = app && app.ActiveDocument;
  var selection = app && app.Selection;
  if (!doc || !selection) {
    alert("请先打开或新建一个 WPS 文字文档。");
    return false;
  }

  var start = Number(selection.Start) || 0;
  if (!insertText(EXAM_TEMPLATES.exam_header)) {
    return false;
  }
  var end = Number(selection.Start) || (start + EXAM_TEMPLATES.exam_header.length);
  var bookmarkEnd = Math.max(start, end - 1);
  try {
    var headerRange = doc.Range(start, bookmarkEnd);
    // Distributed alignment makes the four fields visibly span the full
    // single-column section instead of looking confined to the left column.
    headerRange.ParagraphFormat.Alignment = 4;
    doc.Bookmarks.Add(EXAM_HEADER_BOOKMARK, headerRange);
  } catch (_) {
    // The full-width section still works in builds that do not persist bookmarks.
  }

  var sectionAdded = false;
  try {
    if (doc.Sections && doc.Sections.Add) {
      doc.Sections.Add(selection.Range, 0);
      sectionAdded = true;
    }
  } catch (_) {
    sectionAdded = false;
  }
  if (!sectionAdded) {
    try {
      selection.InsertBreak(3);
      sectionAdded = true;
    } catch (_) {
      try { selection.TypeText("\r"); } catch (_) {}
    }
  }

  var headerSection = getExamHeaderSection(doc);
  if (headerSection) {
    try { headerSection.PageSetup.TextColumns.SetCount(1); } catch (_) {}
  }
  return true;
}

function setParagraphAlignment(alignment) {
  var selection = getSelection();
  if (!selection) {
    return false;
  }
  selection.ParagraphFormat.Alignment = alignment;
  return true;
}

function removeSpaces() {
  var selection = getSelection();
  var range = selection && selection.Range;
  if (!range || range.End <= range.Start) {
    alert("请先选择需要删除空格的文字。");
    return false;
  }
  var text = String(range.Text || "");
  var start = range.Start;
  var runs = [];
  var spaces = /[ \t\u3000]+/g;
  var match;
  while ((match = spaces.exec(text)) !== null) {
    runs.push({ offset: match.index, text: match[0] });
  }
  if (!runs.length) { return true; }
  var parts = [];
  for (var i = runs.length - 1; i >= 0; i -= 1) {
    var item = runs[i];
    var part = range.Duplicate;
    part.SetRange(start + item.offset, start + item.offset + item.text.length);
    if (part.Text !== item.text) {
      alert("当前选区包含特殊内容，无法准确定位空格。请缩小选区。");
      return false;
    }
    parts.push(part);
  }
  for (var j = 0; j < parts.length; j += 1) { parts[j].Delete(); }
  return true;
}

function tableToText() {
  var selection = getSelection();
  if (!selection) {
    return false;
  }

  try {
    if (!selection.Tables || selection.Tables.Count === 0) {
      throw new Error("选区中没有表格");
    }
    selection.Tables.Item(1).ConvertToText(1);
    return true;
  } catch (error) {
    alert("请将光标放入需要转换的表格中。\n" + error.message);
    return false;
  }
}

function adjustLineSpacing(delta) {
  var selection = getSelection();
  if (!selection) {
    return false;
  }

  var format = selection.ParagraphFormat;
  var current = Number(format.LineSpacing) || 12;
  format.LineSpacingRule = 4;
  format.LineSpacing = Math.max(6, current + delta);
  return true;
}

function setUnderline(enabled) {
  var selection = getSelection();
  if (!selection) {
    return false;
  }
  selection.Font.Underline = enabled ? 1 : 0;
  return true;
}

function setEmphasis(enabled) {
  var selection = getSelection();
  if (!selection) {
    return false;
  }
  selection.Font.EmphasisMark = enabled ? 1 : 0;
  return true;
}

function toggleHidden() {
  var selection = getSelection();
  if (!selection) {
    return false;
  }
  selection.Font.Hidden = selection.Font.Hidden ? 0 : 1;
  return true;
}

function setPageLayout(layout) {
  var selection = getSelection();
  if (!selection) {
    return false;
  }

  try {
    var app = getApplication();
    var doc = app && app.ActiveDocument;
    var twoColumns = layout === "a4-landscape-2col";
    var headerSection = getExamHeaderSection(doc);
    var setups = [];
    if (headerSection && doc.Sections && Number(doc.Sections.Count) > 1) {
      for (var index = 1; index <= Number(doc.Sections.Count); index += 1) {
        setups.push(doc.Sections.Item(index).PageSetup);
      }
    } else {
      setups.push(selection.Sections.Item(1).PageSetup);
    }
    setups.forEach(function (setup) {
      setup.PaperSize = 7;
      setup.Orientation = twoColumns ? 1 : 0;
      setup.TopMargin = 42;
      setup.BottomMargin = 42;
      setup.LeftMargin = 42;
      setup.RightMargin = 42;
      setup.TextColumns.SetCount(twoColumns ? 2 : 1);
    });
    if (twoColumns && headerSection) {
      headerSection.PageSetup.TextColumns.SetCount(1);
    }
    return true;
  } catch (error) {
    alert("当前 WPS 版本无法设置页面布局。\n" + error.message);
    return false;
  }
}

function addPageNumber() {
  var selection = getSelection();
  if (!selection) {
    return false;
  }

  try {
    var pageNumbers = selection.Sections.Item(1).Footers.Item(1).PageNumbers;
    var shouldAdd = true;
    try {
      shouldAdd = Number(pageNumbers.Count) === 0;
    } catch (_) {
      shouldAdd = true;
    }
    if (!shouldAdd && pageNumbers.Item) {
      try {
        pageNumbers.Item(1);
        return true;
      } catch (_) {
        shouldAdd = true;
      }
    }
    if (shouldAdd) {
      pageNumbers.Add();
    }
    return true;
  } catch (error) {
    try {
      selection.Sections.Item(1).Footers.Item(1).PageNumbers.Add();
      return true;
    } catch (retryError) {
      alert("当前 WPS 版本无法添加页码。\n" + retryError.message);
      return false;
    }
  }
}

function OnGetEnabled(control) {
  return !!(getApplication() && getApplication().ActiveDocument);
}

function OnGetVisible(control) {
  return true;
}

function OnGetLabel(control) {
  return "";
}

function GetImage(control) {
  return "";
}

function OnAddinUnload() {
  return true;
}

function OnRibbonLoad() {
  return true;
}

function RefreshRibbon() {
  var app = getApplication();
  if (app && app.ribbonUI) {
    app.ribbonUI.Invalidate();
  }
}
