// mdedit editor — CodeMirror 6 inside a WKWebView.
//
// Swift → JS (all on window):
//   mdeditInit(text, options)      create the editor with fresh history
//   mdeditSetText(text)            replace the text from Swift (revert, external change) as one
//                                  minimal, undoable change; cursor and scroll stay put
//   mdeditSetOptions(options)      { lineNumbers, fontFamily, fontSize, lineWrapping }
//   mdeditScrollToLine(line)       scroll so 0-based (fractional) source line is at the top
//   mdeditSetCursorLine(line)      move the cursor to the start of a 0-based line
//   mdeditFormat(kind)             bold | italic | link | highlight | comment
//   mdeditUndo() / mdeditRedo()    history commands (the Edit menu routes here)
//   mdeditOpenSearch()             open the search / replace panel
//   mdeditFocus()
//
// JS → Swift (window.webkit.messageHandlers.mdedit):
//   { type: "ready" }
//   { type: "change", text }       debounced ~100 ms; never sent for mdeditSetText/mdeditInit
//   { type: "scroll", line }       fractional 0-based source line at the top of the viewport
//   { type: "cursor", line }       0-based line of the main cursor

import { EditorState, EditorSelection, Compartment, Annotation } from "@codemirror/state";
import {
  EditorView, keymap, lineNumbers, highlightActiveLine, highlightActiveLineGutter,
  drawSelection, dropCursor, rectangularSelection, crosshairCursor, highlightSpecialChars,
} from "@codemirror/view";
import { history, historyKeymap, defaultKeymap, indentWithTab, undo, redo } from "@codemirror/commands";
import { searchKeymap, highlightSelectionMatches, openSearchPanel, search } from "@codemirror/search";
import { bracketMatching, indentOnInput, syntaxHighlighting, HighlightStyle } from "@codemirror/language";
import { markdown, markdownLanguage, markdownKeymap } from "@codemirror/lang-markdown";
import { tags as t } from "@lezer/highlight";

// YAML frontmatter at the very top of the file, matching the preview's rule (the
// first line inside must look like "key: …"). Without this, "key: value" followed by
// the closing "---" parses as a setext heading.
const Frontmatter = {
  defineNodes: [{ name: "Frontmatter", block: true, style: t.meta }],
  parseBlock: [{
    name: "Frontmatter",
    before: "HorizontalRule",
    parse(cx, line) {
      if (cx.lineStart !== 0 || !/^---[ \t]*$/.test(line.text)) return false;
      const next = cx.peekLine();
      if (!/^[^\s:][^:\n]*:/.test(next)) return false;
      const from = cx.lineStart;
      let to = from + line.text.length;
      while (cx.nextLine()) {
        to = cx.lineStart + line.text.length;
        if (/^(---|\.\.\.)[ \t]*$/.test(line.text)) { cx.nextLine(); break; }
      }
      cx.addElement(cx.elt("Frontmatter", from, to));
      return true;
    },
  }],
};

const fromSwift = Annotation.define();
const CHANGE_DEBOUNCE_MS = 100;
const PROGRAMMATIC_SCROLL_QUIET_MS = 200;

function post(message) {
  try { window.webkit.messageHandlers.mdedit.postMessage(message); } catch (e) { /* not in WebKit */ }
}

// ── Appearance ──────────────────────────────────────────────────────────────
// Colours come from CSS variables in editor.html, which switch on
// prefers-color-scheme, so one highlight style serves light and dark.
const markdownHighlight = HighlightStyle.define([
  { tag: t.heading1, fontWeight: "700", fontSize: "1.3em", color: "var(--md-heading)" },
  { tag: t.heading2, fontWeight: "700", fontSize: "1.18em", color: "var(--md-heading)" },
  { tag: t.heading3, fontWeight: "700", fontSize: "1.08em", color: "var(--md-heading)" },
  { tag: [t.heading4, t.heading5, t.heading6], fontWeight: "700", color: "var(--md-heading)" },
  { tag: t.strong, fontWeight: "700" },
  { tag: t.emphasis, fontStyle: "italic" },
  { tag: t.strikethrough, textDecoration: "line-through" },
  { tag: [t.link, t.url], color: "var(--md-link)" },
  { tag: t.monospace, color: "var(--md-code)" },
  { tag: t.quote, color: "var(--md-quote)" },
  { tag: [t.processingInstruction, t.contentSeparator, t.labelName], color: "var(--md-mark)" },
  { tag: [t.meta, t.comment], color: "var(--md-meta)" },
  { tag: t.list, color: "var(--md-mark)" },
]);

const baseTheme = EditorView.theme({
  "&": { height: "100%", backgroundColor: "var(--bg)", color: "var(--fg)" },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": {
    fontFamily: "var(--editor-font)", fontSize: "var(--editor-size)", lineHeight: "1.55",
  },
  ".cm-content": { padding: "16px 0 50vh", caretColor: "var(--caret)" },
  ".cm-line": { padding: "0 20px" },
  ".cm-gutters": {
    backgroundColor: "var(--bg)", color: "var(--gutter-fg)", borderRight: "1px solid var(--border)",
  },
  ".cm-activeLine": { backgroundColor: "var(--active-line)" },
  ".cm-activeLineGutter": { backgroundColor: "var(--active-line)" },
  "&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground":
    { backgroundColor: "var(--selection) !important" },
  ".cm-cursor, .cm-dropCursor": { borderLeftColor: "var(--caret)" },
  ".cm-matchingBracket": { backgroundColor: "var(--match-bg)", outline: "none" },
  ".cm-searchMatch": { backgroundColor: "var(--search-bg)" },
  ".cm-searchMatch.cm-searchMatch-selected": { backgroundColor: "var(--search-active-bg)" },
  ".cm-panels": { backgroundColor: "var(--panel-bg)", color: "var(--fg)" },
  ".cm-panels.cm-panels-top": { borderBottom: "1px solid var(--border)" },
  ".cm-panel.cm-search input, .cm-panel.cm-search button": { fontSize: "12px" },
});

const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");
const darkCompartment = new Compartment();
const gutterCompartment = new Compartment();
const wrapCompartment = new Compartment();

function gutterExtensions(on) {
  return on ? [lineNumbers(), highlightActiveLineGutter()] : [];
}

// ── Formatting commands ─────────────────────────────────────────────────────
// Toggle a symmetric marker (**, *, ==) around each selection. An empty selection
// inserts the pair with the cursor between; text already wrapped (markers inside
// or just outside the selection) is unwrapped instead.
function toggleWrap(view, marker) {
  const { state } = view;
  const len = marker.length;
  const tr = state.changeByRange((range) => {
    const text = state.sliceDoc(range.from, range.to);
    if (text.length >= 2 * len && text.startsWith(marker) && text.endsWith(marker)) {
      return {
        changes: [
          { from: range.from, to: range.from + len },
          { from: range.to - len, to: range.to },
        ],
        range: EditorSelection.range(range.from, range.to - 2 * len),
      };
    }
    const before = state.sliceDoc(range.from - len, range.from);
    const after = state.sliceDoc(range.to, range.to + len);
    if (before === marker && after === marker) {
      return {
        changes: [
          { from: range.from - len, to: range.from },
          { from: range.to, to: range.to + len },
        ],
        range: EditorSelection.range(range.from - len, range.to - len),
      };
    }
    return {
      changes: [{ from: range.from, insert: marker }, { from: range.to, insert: marker }],
      range: EditorSelection.range(range.from + len, range.to + len),
    };
  });
  view.dispatch(state.update(tr, { scrollIntoView: true, userEvent: "input.format" }));
  return true;
}

// [selection](|) — or [](url) with an empty selection; the cursor lands where the
// user types next (the URL, or the link text when there was none).
function insertLink(view) {
  const { state } = view;
  const tr = state.changeByRange((range) => {
    const text = state.sliceDoc(range.from, range.to);
    const insert = "[" + text + "]()";
    const cursor = text ? range.from + text.length + 3 : range.from + 1;
    return {
      changes: { from: range.from, to: range.to, insert },
      range: EditorSelection.cursor(cursor),
    };
  });
  view.dispatch(state.update(tr, { scrollIntoView: true, userEvent: "input.format" }));
  return true;
}

// Wrap in / unwrap from an HTML comment. With an empty selection the whole
// line(s) under the cursor are toggled.
function toggleHtmlComment(view) {
  const { state } = view;
  const open = "<!-- ";
  const close = " -->";
  const tr = state.changeByRange((range) => {
    let from = range.from;
    let to = range.to;
    if (range.empty) {
      from = state.doc.lineAt(range.from).from;
      to = state.doc.lineAt(range.to).to;
    }
    const text = state.sliceDoc(from, to);
    const m = /^(\s*)<!--\s?([\s\S]*?)\s?-->(\s*)$/.exec(text);
    if (m) {
      const inner = m[1] + m[2] + m[3];
      return {
        changes: { from, to, insert: inner },
        range: range.empty
          ? EditorSelection.cursor(Math.min(range.head, from + inner.length))
          : EditorSelection.range(from, from + inner.length),
      };
    }
    return {
      changes: [{ from, insert: open }, { from: to, insert: close }],
      range: range.empty
        ? EditorSelection.cursor(range.head + open.length)
        : EditorSelection.range(from, to + open.length + close.length),
    };
  });
  view.dispatch(state.update(tr, { scrollIntoView: true, userEvent: "input.format" }));
  return true;
}

const formatters = {
  bold: (v) => toggleWrap(v, "**"),
  italic: (v) => toggleWrap(v, "*"),
  highlight: (v) => toggleWrap(v, "=="),
  link: insertLink,
  comment: toggleHtmlComment,
};

const formattingKeymap = [
  { key: "Mod-b", run: formatters.bold },
  { key: "Mod-i", run: formatters.italic },
  { key: "Mod-k", run: formatters.link },
  { key: "Shift-Mod-h", run: formatters.highlight },
  { key: "Mod-/", run: formatters.comment },
];

// ── Bridge to Swift ─────────────────────────────────────────────────────────
let view = null;
let changeTimer = null;
let ignoreScrollUntil = 0;
let lastCursorLine = -1;
let scrollFrame = 0;

function flushChange() {
  if (changeTimer) { clearTimeout(changeTimer); changeTimer = null; }
  if (view) post({ type: "change", text: view.state.doc.toString() });
}

function topLine() {
  const scroller = view.scrollDOM;
  const top = scroller.scrollTop;
  const block = view.lineBlockAtHeight(top);
  const line = view.state.doc.lineAt(block.from).number - 1;
  const frac = block.height > 0 ? Math.min(Math.max((top - block.top) / block.height, 0), 1) : 0;
  return line + frac;
}

function reportScroll() {
  scrollFrame = 0;
  if (!view || Date.now() < ignoreScrollUntil) return;
  post({ type: "scroll", line: topLine() });
}

const bridge = EditorView.updateListener.of((update) => {
  if (update.docChanged && !update.transactions.some((tr) => tr.annotation(fromSwift))) {
    if (changeTimer) clearTimeout(changeTimer);
    changeTimer = setTimeout(flushChange, CHANGE_DEBOUNCE_MS);
  }
  if (update.selectionSet || update.docChanged) {
    const line = update.state.doc.lineAt(update.state.selection.main.head).number - 1;
    if (line !== lastCursorLine) {
      lastCursorLine = line;
      post({ type: "cursor", line });
    }
  }
});

function extensions(options) {
  return [
    highlightSpecialChars(),
    history(),
    drawSelection(),
    dropCursor(),
    EditorState.allowMultipleSelections.of(true),
    indentOnInput(),
    bracketMatching(),
    rectangularSelection(),
    crosshairCursor(),
    highlightActiveLine(),
    highlightSelectionMatches(),
    search({ top: true }),
    markdown({ base: markdownLanguage, extensions: [Frontmatter] }),
    syntaxHighlighting(markdownHighlight),
    keymap.of([
      ...formattingKeymap,
      ...markdownKeymap,
      ...defaultKeymap,
      ...searchKeymap,
      ...historyKeymap,
      indentWithTab,
    ]),
    gutterCompartment.of(gutterExtensions(options.lineNumbers)),
    wrapCompartment.of(options.lineWrapping === false ? [] : EditorView.lineWrapping),
    darkCompartment.of(EditorView.darkTheme.of(darkQuery.matches)),
    baseTheme,
    bridge,
  ];
}

function applyFont(options) {
  const root = document.documentElement.style;
  if (options.fontFamily) root.setProperty("--editor-font", options.fontFamily);
  if (options.fontSize) root.setProperty("--editor-size", options.fontSize + "px");
}

window.mdeditInit = function (text, options) {
  options = options || {};
  applyFont(options);
  const state = EditorState.create({ doc: text, extensions: extensions(options) });
  if (view) {
    view.setState(state);
  } else {
    view = new EditorView({ state, parent: document.getElementById("editor") });
    view.scrollDOM.addEventListener("scroll", () => {
      if (!scrollFrame) scrollFrame = requestAnimationFrame(reportScroll);
    }, { passive: true });
  }
  lastCursorLine = -1;
};

// Smallest single replacement turning the current text into `text`: everything
// outside the edited middle (cursor, folds, scroll anchor) is left untouched, and
// the change is one ordinary undo step.
window.mdeditSetText = function (text) {
  if (!view) return;
  const current = view.state.doc.toString();
  if (current === text) return;
  let start = 0;
  const max = Math.min(current.length, text.length);
  while (start < max && current.charCodeAt(start) === text.charCodeAt(start)) start++;
  let endCur = current.length;
  let endNew = text.length;
  while (endCur > start && endNew > start
      && current.charCodeAt(endCur - 1) === text.charCodeAt(endNew - 1)) {
    endCur--; endNew--;
  }
  view.dispatch({
    changes: { from: start, to: endCur, insert: text.slice(start, endNew) },
    annotations: fromSwift.of(true),
  });
};

window.mdeditGetText = function () {
  return view ? view.state.doc.toString() : "";
};

window.mdeditSetOptions = function (options) {
  if (!view) return;
  applyFont(options);
  const effects = [];
  if (options.lineNumbers !== undefined) {
    effects.push(gutterCompartment.reconfigure(gutterExtensions(options.lineNumbers)));
  }
  if (options.lineWrapping !== undefined) {
    effects.push(wrapCompartment.reconfigure(options.lineWrapping ? EditorView.lineWrapping : []));
  }
  if (effects.length) view.dispatch({ effects });
  view.requestMeasure();
};

window.mdeditScrollToLine = function (line) {
  if (!view) return;
  const doc = view.state.doc;
  const whole = Math.max(0, Math.floor(line));
  const number = Math.min(whole + 1, doc.lines);
  const block = view.lineBlockAt(doc.line(number).from);
  const frac = number === whole + 1 ? line - whole : 0;
  ignoreScrollUntil = Date.now() + PROGRAMMATIC_SCROLL_QUIET_MS;
  view.scrollDOM.scrollTop = block.top + frac * block.height;
};

window.mdeditSetCursorLine = function (line) {
  if (!view) return;
  const doc = view.state.doc;
  const number = Math.min(Math.max(1, Math.floor(line) + 1), doc.lines);
  view.dispatch({ selection: EditorSelection.cursor(doc.line(number).from) });
};

window.mdeditFormat = function (kind) {
  const run = formatters[kind];
  if (view && run) { run(view); view.focus(); }
};

window.mdeditUndo = function () { if (view) undo(view); };
window.mdeditRedo = function () { if (view) redo(view); };
window.mdeditOpenSearch = function () { if (view) { openSearchPanel(view); } };
window.mdeditFocus = function () { if (view) view.focus(); };
window.mdeditFlush = flushChange;

darkQuery.addEventListener("change", (e) => {
  if (view) view.dispatch({ effects: darkCompartment.reconfigure(EditorView.darkTheme.of(e.matches)) });
});

post({ type: "ready" });
