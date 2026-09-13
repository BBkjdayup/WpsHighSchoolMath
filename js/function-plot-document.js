(function (root, factory) {
  var api = factory(root);
  root.MathFunctionDocument = api;
  if (typeof globalThis !== "undefined") {
    globalThis.MathFunctionDocument = api;
  }
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
})(typeof window !== "undefined" ? window : globalThis, function (root) {
  var METADATA_PREFIX = "HSM_FUNCTION_PLOT_V1:";
  var DEFAULT_CONFIG = {
    expressions: ["x^2"],
    bounds: { xMin: -10, xMax: 10, yMin: -10, yMax: 10 },
    options: { showTickLabels: true, showGrid: true, showBorder: true, showLegend: true }
  };

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function finite(value) {
    var number = Number(value);
    return isFinite(number) ? number : null;
  }

  function normalizeConfig(input) {
    var source = input || {};
    var expressions = Array.isArray(source.expressions) ? source.expressions : [];
    expressions = expressions.map(function (value) {
      return String(value === undefined || value === null ? "" : value).trim();
    }).filter(function (value) { return value.length > 0; }).slice(0, 12);
    if (!expressions.length) {
      throw new Error("请至少输入一个函数表达式。");
    }

    var bounds = source.bounds || {};
    var xMin = finite(bounds.xMin);
    var xMax = finite(bounds.xMax);
    var yMin = finite(bounds.yMin);
    var yMax = finite(bounds.yMax);
    if (xMin === null || xMax === null || xMin >= xMax) {
      throw new Error("横坐标范围无效。");
    }
    if (yMin === null || yMax === null || yMin >= yMax) {
      throw new Error("纵坐标范围无效。");
    }

    var options = source.options || {};
    return {
      expressions: expressions,
      bounds: { xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax },
      options: {
        showTickLabels: options.showTickLabels !== false,
        showGrid: options.showGrid !== false,
        showBorder: options.showBorder !== false,
        showLegend: options.showLegend !== false
      }
    };
  }

  function humanLabel(config) {
    return "函数图像：" + config.expressions.join("；");
  }

  function serializeMetadata(input) {
    var config = normalizeConfig(input);
    return humanLabel(config) + "\n" + METADATA_PREFIX + encodeURIComponent(JSON.stringify(config));
  }

  function parseMetadata(value) {
    var text = String(value || "");
    var prefixIndex = text.indexOf(METADATA_PREFIX);
    if (prefixIndex < 0) {
      return null;
    }
    var encoded = text.substring(prefixIndex + METADATA_PREFIX.length).split(/[\r\n]/)[0].trim();
    if (!encoded) {
      return null;
    }
    try {
      return normalizeConfig(JSON.parse(decodeURIComponent(encoded)));
    } catch (_) {
      return null;
    }
  }

  function shapeMetadata(shape) {
    try {
      return parseMetadata(shape.AlternativeText);
    } catch (_) {
      return null;
    }
  }

  function applyMetadata(shape, input) {
    var config = normalizeConfig(input);
    try { shape.AlternativeText = serializeMetadata(config); } catch (_) {}
    try { shape.Title = config.expressions.join("；"); } catch (_) {}
    return config;
  }

  function selectedWriterShape(app) {
    var selection = null;
    var doc = null;
    try { selection = app && app.Selection; } catch (_) { selection = null; }
    try { doc = app && app.ActiveDocument; } catch (_) { doc = null; }
    if (!selection || !doc) {
      return null;
    }

    var collections = [];
    try { if (selection.InlineShapes) { collections.push(selection.InlineShapes); } } catch (_) {}
    try { if (selection.Range && selection.Range.InlineShapes) { collections.push(selection.Range.InlineShapes); } } catch (_) {}
    for (var collectionIndex = 0; collectionIndex < collections.length; collectionIndex += 1) {
      try {
        if (Number(collections[collectionIndex].Count) > 0) {
          var selected = collections[collectionIndex].Item(1);
          var selectedConfig = shapeMetadata(selected);
          if (selectedConfig) {
            return { host: "writer", shape: selected, config: selectedConfig };
          }
        }
      } catch (_) {}
    }

    var start = null;
    var end = null;
    try {
      start = Number(selection.Range.Start);
      end = Number(selection.Range.End);
    } catch (_) {}
    if (start === null || !isFinite(start)) {
      return null;
    }
    try {
      var count = Number(doc.InlineShapes.Count) || 0;
      for (var index = 1; index <= count; index += 1) {
        var shape = doc.InlineShapes.Item(index);
        var shapeStart = Number(shape.Range.Start);
        var shapeEnd = Number(shape.Range.End);
        var touchesSelection = start === shapeStart || (end !== null && start <= shapeEnd && end >= shapeStart);
        if (touchesSelection) {
          var config = shapeMetadata(shape);
          if (config) {
            return { host: "writer", shape: shape, config: config };
          }
        }
      }
    } catch (_) {}
    return null;
  }

  function selectedPresentationShape(app) {
    try {
      var selection = app.ActiveWindow.Selection;
      var range = selection && selection.ShapeRange;
      if (!range || Number(range.Count) !== 1) {
        return null;
      }
      var shape = range.Item(1);
      var config = shapeMetadata(shape);
      return config ? { host: "presentation", shape: shape, config: config } : null;
    } catch (_) {
      return null;
    }
  }

  function getSelectedPlot(app) {
    var writer = selectedWriterShape(app);
    return writer || selectedPresentationShape(app);
  }

  function rangeStart(shape, fallback) {
    try {
      var start = Number(shape.Range.Start);
      return isFinite(start) ? start : fallback;
    } catch (_) {
      return fallback;
    }
  }

  function shapeGeometry(shape) {
    var geometry = {};
    ["Left", "Top", "Width", "Height"].forEach(function (property) {
      try {
        var value = Number(shape[property]);
        if (isFinite(value) && value > (property === "Width" || property === "Height" ? 0 : -100000)) {
          geometry[property.toLowerCase()] = value;
        }
      } catch (_) {}
    });
    return geometry;
  }

  function insertIntoWriter(app, path, plot, config) {
    var doc = app && app.ActiveDocument;
    var selection = app && app.Selection;
    if (!doc || !selection || !doc.InlineShapes) {
      throw new Error("请先打开一个 WPS 文字文档。");
    }
    var selected = selectedWriterShape(app);
    var update = Boolean(selected);
    var preserved = selected ? shapeGeometry(selected.shape) : {};
    var insertionRange = selection.Range;

    if (selected) {
      var start = rangeStart(selected.shape, Number(selection.Range.Start) || 0);
      try { selected.shape.Delete(); } catch (error) { throw new Error("无法替换所选函数图像：" + error.message); }
      insertionRange = doc.Range(start, start);
    } else if (insertionRange && insertionRange.Start !== insertionRange.End) {
      insertionRange.Text = "";
    }

    var shape = doc.InlineShapes.AddPicture(path, false, true, insertionRange);
    applyMetadata(shape, config);
    try {
      shape.LockAspectRatio = -1;
      shape.Width = preserved.width || 420;
      if (preserved.height) {
        shape.Height = preserved.height;
      } else if (!Number(shape.Height) || Number(shape.Height) < 10) {
        shape.Height = Math.round(Number(shape.Width) * plot.height / plot.width);
      }
    } catch (_) {}
    try { selection.SetRange(shape.Range.End, shape.Range.End); } catch (_) {}
    return {
      host: "writer",
      updated: update,
      shape: shape,
      message: update ? "所选函数图像已更新。" : "函数图像已插入到 WPS 文字。"
    };
  }

  function activePresentation(app) {
    try {
      if (root.WpsPptApi) {
        return root.WpsPptApi.getActivePresentation(app);
      }
    } catch (_) {}
    try { return app.ActivePresentation; } catch (_) { return null; }
  }

  function activeSlide(app, presentation) {
    try {
      if (root.WpsPptApi) {
        return root.WpsPptApi.getActiveSlide(app);
      }
    } catch (_) {}
    try { return app.ActiveWindow.View.Slide; } catch (_) {}
    try { return app.ActiveWindow.Selection.SlideRange.Item(1); } catch (_) {}
    try { return presentation.Slides.Item(1); } catch (_) { return null; }
  }

  function presentationSize(presentation) {
    if (root.WpsPptApi && root.WpsPptApi.getPresentationSize) {
      return root.WpsPptApi.getPresentationSize(presentation);
    }
    try {
      return {
        width: Number(presentation.PageSetup.SlideWidth) || 720,
        height: Number(presentation.PageSetup.SlideHeight) || 540
      };
    } catch (_) {
      return { width: 720, height: 540 };
    }
  }

  function newPresentationGeometry(slide, presentation, plot) {
    var size = presentationSize(presentation);
    var width = Math.min(460, size.width - 48);
    var height = Math.round(width * plot.height / plot.width);
    if (height > size.height - 48) {
      height = size.height - 48;
      width = Math.round(height * plot.width / plot.height);
    }
    if (root.WpsPptApi && root.WpsPptApi.findBestPlacement) {
      return root.WpsPptApi.findBestPlacement(slide, presentation, width, height, {
        margin: 24,
        padding: 10
      });
    }
    return {
      left: Math.max(24, (size.width - width) / 2),
      top: Math.max(24, (size.height - height) / 2),
      width: width,
      height: height,
      overlapArea: 0,
      overlapCount: 0,
      scale: 1
    };
  }

  function insertIntoPresentation(app, path, plot, config) {
    var presentation = activePresentation(app);
    var slide = activeSlide(app, presentation);
    if (!presentation || !slide || !slide.Shapes) {
      throw new Error("请先打开一个 WPS 演示文稿并选中幻灯片。");
    }
    var selected = selectedPresentationShape(app);
    var update = Boolean(selected);
    var geometry = selected ? shapeGeometry(selected.shape) : newPresentationGeometry(slide, presentation, plot);
    if (selected) {
      try { selected.shape.Delete(); } catch (error) { throw new Error("无法替换所选函数图像：" + error.message); }
    }
    var shape = slide.Shapes.AddPicture(
      path,
      false,
      true,
      geometry.left,
      geometry.top,
      geometry.width,
      geometry.height
    );
    applyMetadata(shape, config);
    try { shape.Name = "高中数学函数图像"; } catch (_) {}
    try { shape.Select(); } catch (_) {}
    return {
      host: "presentation",
      updated: update,
      shape: shape,
      placement: geometry,
      message: update ? "所选函数图像已更新。" : "函数图像已插入到当前幻灯片。"
    };
  }

  function insertOrUpdate(app, path, plot, input) {
    var config = normalizeConfig(input);
    try {
      if (app && app.ActiveDocument) {
        return insertIntoWriter(app, path, plot, config);
      }
    } catch (_) {}
    if (activePresentation(app)) {
      return insertIntoPresentation(app, path, plot, config);
    }
    throw new Error("当前不是可插入图像的 WPS 文字或演示窗口。");
  }

  return {
    METADATA_PREFIX: METADATA_PREFIX,
    getDefaultConfig: function () { return clone(DEFAULT_CONFIG); },
    normalizeConfig: normalizeConfig,
    serializeMetadata: serializeMetadata,
    parseMetadata: parseMetadata,
    applyMetadata: applyMetadata,
    getSelectedPlot: getSelectedPlot,
    getSelectedPlotConfig: function (app) {
      var selected = getSelectedPlot(app);
      return selected ? clone(selected.config) : null;
    },
    insertOrUpdate: insertOrUpdate,
    _private: {
      shapeMetadata: shapeMetadata,
      selectedWriterShape: selectedWriterShape,
      selectedPresentationShape: selectedPresentationShape,
      shapeGeometry: shapeGeometry,
      newPresentationGeometry: newPresentationGeometry,
      insertIntoWriter: insertIntoWriter,
      insertIntoPresentation: insertIntoPresentation
    }
  };
});
