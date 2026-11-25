const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const projectRoot = path.join(__dirname, "..");

function readProjectFile(filePath) {
  return fs.readFileSync(path.join(projectRoot, filePath), "utf8");
}

function createPptContext(hasSelectionText = true, options = {}) {
  const calls = [];
  const insertedRanges = [];
  const textboxRanges = [];
  const selectedTextRange = {
    Text: "A",
    Font: { Name: "宋体", NameFarEast: "宋体", Size: 18 },
    InsertAfter(text) {
      calls.push(["InsertAfter", text]);
      this.Text += text;
      const insertedRange = {
        Text: text,
        Font: { Name: "宋体", NameFarEast: "宋体", Size: 18 }
      };
      insertedRanges.push(insertedRange);
      return insertedRange;
    }
  };
  if (options.noInsertAfter) {
    delete selectedTextRange.InsertAfter;
  }
  const existingShapes = options.existingShapes || [];
  const shapes = {
      Count: existingShapes.length,
      Item(index) {
        return existingShapes[index - 1];
      },
      AddTextbox(orientation, left, top, width, height) {
        calls.push(["AddTextbox", orientation, left, top, width, height]);
        const textRange = {
          Text: "",
          Font: { Name: "宋体", NameFarEast: "宋体", Size: 18 }
        };
        textboxRanges.push(textRange);
        return {
          TextFrame: {
            TextRange: textRange
          },
          Select() {
            calls.push(["SelectTextbox"]);
          }
        };
      }
  };
  const slide = {
    Shapes: shapes
  };
  const panes = {};
  const storage = Object.assign({}, options.storage || {});
  const app = {
    ActivePresentation: {
      PageSetup: {
        SlideWidth: options.slideWidth || 720,
        SlideHeight: options.slideHeight || 540
      },
      Slides: {
        Count: 1,
        Item() {
          return slide;
        }
      }
    },
    ActiveWindow: {
      Selection: {
        TextRange: hasSelectionText ? selectedTextRange : null,
        SlideRange: {
          Item() {
            return slide;
          }
        },
        ShapeRange: {
          Item() {
            return null;
          }
        }
      },
      View: { Slide: slide }
    },
    PluginStorage: {
      getItem(key) {
        if (/^hsmath_(?:trial|license|machine)/.test(key)) { calls.push(["legacy-read", key]); }
        return storage[key] || "";
      },
      setItem(key, value) {
        if (/^hsmath_(?:trial|license|machine)/.test(key)) { calls.push(["legacy-write", key]); }
        storage[key] = value;
      }
    },
    CreateTaskPane(url) {
      calls.push(["CreateTaskPane", url]);
      const pane = { ID: "ppt-plot-pane", Visible: false };
      panes[pane.ID] = pane;
      return pane;
    },
    GetTaskPane(id) {
      return panes[id];
    },
    OAAssist: {
      ShellExecute(executable, parameters) {
        calls.push(["ShellExecute", executable, parameters]);
        return true;
      }
    }
  };
  const context = {
    window: {
      Application: app,
      setTimeout(callback, delay) {
        if (delay === 350) {
          callback();
        }
      }
    },
    document: { location: { toString: () => "file:///C:/plugin/index.html" } },
    alert(message) {
      calls.push(["alert", message]);
    },
    console: {
      log: console.log,
      warn(message) {
        calls.push(["warn", message]);
      }
    }
  };
  vm.createContext(context);
  vm.runInContext(readProjectFile("js/symbols.js"), context);
  vm.runInContext(readProjectFile("js/ppt-api.js"), context);
  vm.runInContext(readProjectFile("js/taskpane.js"), context);
  vm.runInContext(readProjectFile("js/ribbon-ppt.js"), context);
  return { context, calls, selectedTextRange, insertedRanges, textboxRanges, slide };
}

{
  const { context, calls, selectedTextRange, insertedRanges } = createPptContext(true);
  context.OnAction({ Id: "sym_pi" });
  assert.equal(selectedTextRange.Text, "Aπ");
  assert.deepStrictEqual(calls, [["InsertAfter", "π"]]);
  assert.equal(selectedTextRange.Font.Name, "宋体");
  assert.equal(selectedTextRange.Font.Size, 18);
  assert.equal(insertedRanges[0].Font.Name, "Cambria Math");
  assert.equal(insertedRanges[0].Font.Size, 18);
}

{
  const { context, selectedTextRange } = createPptContext(true, { noInsertAfter: true });
  context.OnAction({ Id: "sym_pi" });
  assert.equal(selectedTextRange.Text, "Aπ");
  assert.equal(selectedTextRange.Font.Name, "宋体");
  assert.equal(selectedTextRange.Font.Size, 18);
}

{
  const { context, calls, textboxRanges } = createPptContext(false);
  context.OnAction({ Id: "sym_proper_subset" });
  assert(calls.some((call) => call[0] === "AddTextbox"));
  assert(calls.some((call) => call[0] === "SelectTextbox"));
  assert.equal(textboxRanges[0].Text, "⫋");
  assert.equal(textboxRanges[0].Font.Name, "Cambria Math");
  assert.equal(textboxRanges[0].Font.Size, 18);
  assert.deepStrictEqual(calls.find((call) => call[0] === "AddTextbox"), ["AddTextbox", 1, 436, 249, 260, 42]);
}

{
  const { context, calls } = createPptContext(false, {
    existingShapes: [{ Left: 0, Top: 400, Width: 720, Height: 140 }]
  });
  context.OnAction({ Id: "sym_pi" });
  assert.deepStrictEqual(calls.find((call) => call[0] === "AddTextbox"), ["AddTextbox", 1, 436, 249, 260, 42]);
}

{
  const { context, calls } = createPptContext(true);
  context.MathTaskPanes.openPackaged = function (options) {
    calls.push(["openPackaged", options]);
    return true;
  };
  context.OnAction({ Id: "function_plot" });
  const localEditorCall = calls.find((call) => call[0] === "openPackaged");
  assert(localEditorCall);
  assert.equal(localEditorCall[1].role, "presentation");
  assert.equal(localEditorCall[1].name, "function-plot");
}

for (const storage of [
  {}, { hsmath_trial_started_v1: new Date().toISOString().slice(0, 10) },
  { hsmath_trial_started_v1: "2000-01-01" },
  { hsmath_machine_id_v1: "HSMTEST000001", hsmath_license_v1: "previously-purchased-fixture" }
]) {
  const { context, calls } = createPptContext(true, { storage });
  const commands = [];
  context.MathTaskPanes.openPackaged = options => { commands.push(options.name); return true; };
  assert.equal(context.OnAddinLoad({}), true);
  assert.equal(context.OnAction({ Id: "sym_pi" }), true);
  assert(calls.some(call => call[0] === "InsertAfter" && call[1] === "π"));

  assert.equal(context.OnAction({ Id: "function_plot" }), true);
  assert.deepStrictEqual(commands, ["function-plot"]);
  assert(!("authorization_center" in context.COMMANDS));
  assert(!calls.some(call => call[0] === "legacy-read" || call[0] === "legacy-write"));
}

{
  const { context } = createPptContext(false);
  context.window.Application.ActivePresentation = null;
  assert.equal(context.OnGetEnabled({ Id: "sym_pi" }), false);
}

{
  const { context } = createPptContext(true);
  const ribbon = readProjectFile("ppt/ribbon.xml");
  assert.equal((ribbon.match(/<tab\b/g) || []).length, 1);
  assert(ribbon.includes('<tab id="mathTeacherPptTab" label="高中数学">'));
  assert(!ribbon.includes("mathTeacherPptToolsTab"));
  const buttonIds = [...ribbon.matchAll(/<button id="([^"]+)"/g)].map((match) => match[1]);
  assert.equal(new Set(buttonIds).size, buttonIds.length);
  for (const id of buttonIds) {
    assert(id in context.SYMBOLS || id in context.COMMANDS, `missing command for ${id}`);
  }
  assert(!ribbon.includes("exam_header"));
  assert(!ribbon.includes("page_a4"));
  assert(!ribbon.includes("table_to_text"));
}

console.log("ppt symbol and function plot ribbon tests passed");
