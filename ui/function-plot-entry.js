(function (root) {
  function panelMarkup() {
    return [
      '<main id="functionPlotApp" class="function-shell">',
      '  <header class="editor-header">',
      '    <div><h1>函数绘图</h1><p>支持分段函数、区间端点与坐标点标注</p></div>',
      '    <span id="editModeBadge" class="mode-badge">新建图像</span>',
      '  </header>',
      '  <section class="editor-card expression-card" aria-labelledby="expressionTitle">',
      '    <div class="expression-heading">',
      '      <div><h2 id="expressionTitle">函数表达式</h2><p>最多 12 条；每行可作为函数的一段</p></div>',
      '      <div class="heading-actions"><button id="loadSelectionButton" type="button" class="compact">载入所选图像</button><button id="addExpressionButton" type="button" class="compact">增加函数</button></div>',
      '    </div>',
      '    <div id="expressionRows" class="expression-rows"></div>',
      '    <div class="presets" aria-label="常用函数预设">',
      '      <button type="button" data-preset="quadratic">二次函数</button>',
      '      <button type="button" data-preset="absolute">绝对值</button>',
      '      <button type="button" data-preset="reciprocal">反比例</button>',
      '      <button type="button" data-preset="sine">sin</button>',
      '      <button type="button" data-preset="cosine">cos</button>',
      '      <button type="button" data-preset="exponential">指数</button>',
      '      <button type="button" data-preset="logarithm">对数</button>',
      '      <button type="button" data-preset="piecewise">分段示例</button>',
      '    </div>',
      '  </section>',
      '  <details class="advanced-settings">',
      '    <summary>坐标与显示设置</summary>',
      '    <div class="advanced-content">',
      '      <fieldset>',
      '        <legend>坐标范围</legend>',
      '        <div class="range-grid">',
      '          <label>x 最小<input id="xMin" type="number" value="-10" step="any"></label>',
      '          <label>x 最大<input id="xMax" type="number" value="10" step="any"></label>',
      '          <label>y 最小<input id="yMin" type="number" value="-10" step="any"></label>',
      '          <label>y 最大<input id="yMax" type="number" value="10" step="any"></label>',
      '        </div>',
      '      </fieldset>',
      '      <fieldset class="display-options">',
      '        <legend>图像显示</legend>',
      '        <label><input id="showTickLabels" type="checkbox" checked>刻度数字</label>',
      '        <label><input id="showGrid" type="checkbox" checked>网格</label>',
      '        <label><input id="showBorder" type="checkbox" checked>边框</label>',
      '        <label><input id="showLegend" type="checkbox" checked>函数表达式</label>',
      '        <label><input id="monochrome" type="checkbox">黑白打印（线型区分）</label>',
      '      </fieldset>',
      '    </div>',
      '  </details>',
      '  <details class="advanced-settings">',
      '    <summary>坐标点标注</summary>',
      '    <div class="advanced-content">',
      '      <label for="pointAnnotations">每行一个点：名称,横坐标,纵坐标</label>',
      '      <textarea id="pointAnnotations" rows="3" placeholder="A,1,2&#10;B,-2,3" aria-describedby="pointHelp"></textarea>',
      '      <p id="pointHelp" class="field-help">最多 30 个点，坐标须为数值。超出当前坐标范围的点保留设置但不显示。</p>',
      '    </div>',
      '  </details>',
      '  <section class="preview-card" aria-labelledby="previewTitle">',
      '    <div class="preview-heading"><h2 id="previewTitle">图像预览</h2><span>矢量图 · 放大清晰</span></div>',
      '    <div id="preview" class="preview" aria-live="polite"></div>',
      '  </section>',
      '  <p id="status" class="status" role="status" aria-live="polite">支持：+ − × ÷ ^、sin、cos、tan、cot、sec、csc、sqrt、abs、ln、log、exp、π。</p>',
      '  <div class="actions">',
      '    <button id="previewButton" type="button">更新预览</button>',
      '    <button id="insertButton" type="button" class="primary">插入新图像</button>',
      '  </div>',
      '</main>'
    ].join("");
  }

  function render(target) {
    var mount = target || document.getElementById("functionPlotRoot") || document.body;
    mount.innerHTML = panelMarkup();
    return document.getElementById("functionPlotApp");
  }

  root.MathFunctionPlotPanel = {
    render: render
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () { render(); });
  } else {
    render();
  }
})(window);
