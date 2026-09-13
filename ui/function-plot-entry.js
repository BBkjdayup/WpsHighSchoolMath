(function (root) {
  function panelMarkup() {
    return [
      '<main id="functionPlotApp" class="function-shell">',
      '  <header class="editor-header">',
      '    <div><h1>函数绘图</h1><p>输入函数，预览后插入或更新所选图像</p></div>',
      '    <span id="editModeBadge" class="mode-badge">新建图像</span>',
      '  </header>',
      '  <section class="editor-card expression-card" aria-labelledby="expressionTitle">',
      '    <div class="expression-heading">',
      '      <div><h2 id="expressionTitle">函数表达式</h2><p>支持添加多条曲线</p></div>',
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
      '      </fieldset>',
      '    </div>',
      '  </details>',
      '  <section class="preview-card" aria-labelledby="previewTitle">',
      '    <div class="preview-heading"><h2 id="previewTitle">图像预览</h2><span>范围默认 −10 到 10</span></div>',
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
