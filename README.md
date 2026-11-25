# mdview

[![GitHub release](https://img.shields.io/github/v/release/jsglazer/mdviewer?logo=github)](https://github.com/jsglazer/mdviewer/releases) [![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org) [![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/jsglazer/mdviewer/blob/main/LICENSE) [![Made with Claude](https://img.shields.io/badge/Made_with-Claude-D97756?logo=anthropic)](https://claude.ai) [![Gemini Flash Antigravity](https://img.shields.io/badge/Gemini%20Flash-Antigravity-4f86f7?logo=google-gemini&logoColor=white)](https://github.com/google-gemini) [![CI](https://github.com/jsglazer/mdviewer/actions/workflows/ci.yml/badge.svg)](https://github.com/jsglazer/mdviewer/actions/workflows/ci.yml) [![CodeQL](https://github.com/jsglazer/mdviewer/actions/workflows/codeql.yml/badge.svg)](https://github.com/jsglazer/mdviewer/actions/workflows/codeql.yml) [![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/jsglazer/mdviewer/badge)](https://securityscorecards.dev/viewer/?uri=github.com/jsglazer/mdviewer)

A lightweight macOS app for viewing — and, when you want to, editing — Markdown files. Open a file and it renders instantly; the view updates automatically whenever the file changes on disk. Switch to the Edit or Split layout to change it in a CodeMirror editor with a live preview beside it.

## Features

### Rendering
- Full GitHub-flavoured Markdown: headings, tables, task lists, fenced code blocks, blockquotes, inline HTML
- Syntax highlighting via [highlight.js](https://highlightjs.org)
- Math typesetting via [KaTeX](https://katex.org) — inline (`$…$`) and display (`$$…$$`, on one line or with the delimiters on their own lines); TeX spacing and escapes such as `\,` `\;` `\{` `\_` are passed to KaTeX intact
- Relative image paths resolved automatically so local images display correctly
- Light and dark mode, following the system appearance
- YAML frontmatter (a `---`/`key: value`/`---` block at the top of a file) is rendered as a distinct metadata block rather than as Markdown prose
- Obsidian-style callouts (`> [!note] Title`, `[!tip]`, `[!warning]`, etc.) render as colored, iconed boxes matching Obsidian's callout types; `+`/`-` suffixes make a callout foldable, click its title bar to collapse/expand
- Obsidian-style highlights (`==text==`) render as highlighted text

### Live Reload
- Watches the open file for changes and re-renders in place — no manual refresh needed
- **Reload** button re-reads the current file from disk on demand
- **Jump to New** mode scrolls to the first changed line on each reload
- **Tail** mode keeps the bottom of the document in view (useful for logs), including a long list being appended to
- Live reload applies whenever the document has no unsaved edits; a document you are editing is never reloaded behind your back (see [Editing](#editing))

### Find
- `⌘F` opens the find bar; results appear in a sidebar panel
- Up / Down arrows (or Return) step through matches
- Active match is highlighted **cyan** in the reading pane; all other matches are yellow
- Escape clears and closes find

### Outline (Table of Contents)
- Sidebar panel listing all headings (h1–h5) with collapse/expand controls
- Clicking a heading scrolls the reading pane to that section and briefly highlights the target line — in the same colour the Outline uses for the current entry — so the destination is easy to spot
- Clicking an entry keeps keyboard focus on the Outline, so you can then walk the headings without the mouse: **↑ / ↓** move between entries (scrolling the document to match) and **← / →** collapse / expand grouped headings
- The current heading and all its ancestors are highlighted as you read or navigate, so you always know where you are in the document structure

### Printing and PDF Export
- **Print…** (`⌘P`) and **Export as PDF…** (`⇧⌘E`) both open a shared **Print Preview** window
- The preview is not an approximation: the document is rendered through the real print pipeline and the window displays that exact PDF, so what you see is byte-for-byte what gets printed or saved
- **Page Setup…** sets paper, orientation and margins (0.75″ by default, which suits Markdown better than the usual 1″); the choices persist between launches
- **Scale** control shrinks content down to fit wide tables or code blocks on the page, or enlarges it for readability — 50%–200% in 10% steps, persisted between launches
- **Fit to** checkbox, when enabled, picks a scale automatically to hit a chosen page count — set the number of pages wide and/or tall and the scale is solved for you; leave it unchecked to control scale manually
- Page navigation, **Save PDF…** and **Print…** are all in the preview window
- Four page extras can be toggled on and off, each re-rendering the preview live and remembered between sessions:
  - **Page numbers** — a "Page N of M" footer *(on by default)*
  - **Title header** — the file name in the page header *(on by default)*
  - **Print date** — the date printed, alongside the title *(on by default)*
  - **Link URLs** — prints each external link's target in parentheses after it, since a printed link isn't clickable *(off by default)*
- Printed output always uses the light theme, whatever appearance the app is running in
- Code blocks, tables, blockquotes and images are kept from splitting across a page break, and headings stay with the content that follows them

### Display Options
- **Line Numbers** — toggle gutter line numbers keyed to Markdown source lines (`⇧⌘L`)
- **Show CSS** — inspect the full stylesheet applied to the current document
- **Custom CSS** — inject your own styles via Settings
- The app version is shown at the top-right of the toolbar

### Keyboard Shortcuts
- `⌘P` — Print… (opens Print Preview)
- `⇧⌘E` — Export as PDF…
- `⌘F` — Find (search & replace in the editor when it has focus)
- `⌥⌘F` — Find in Preview
- `⌘1` / `⌘2` / `⌘3` — Edit / Split / Preview layout
- `⌘S` — Save; `⌘N` — New document
- `⌘B` / `⌘I` / `⌘K` / `⇧⌘H` / `⌘/` — Bold / Italic / Link / Highlight / Toggle comment (editor)
- `⇧⌘L` — Preview line numbers; `⌥⇧⌘L` — Editor line numbers
- `⌘↑` / `⌘↓` — Jump to top / bottom
- `⌘←` / `⌘→` — Page up / page down
- `↑` / `↓` (in find bar) — previous / next match
- `↑` / `↓` (in Outline) — previous / next heading
- `←` / `→` (in Outline) — collapse / expand grouped heading
- `Escape` — close find

A full shortcut reference is available from **View ▸ Keyboard Shortcuts** (`⇧⌘K`).

## Editing

mdview opens every file in the read-only **Preview** layout, exactly as a viewer. Editing is opt-in, per window:

- **Layouts:** the **Edit | Split | Preview** switch at the left of the toolbar ribbon (`⌘1` / `⌘2` / `⌘3`). Split shows the editor on the left and the live preview on the right, with a draggable divider. Each file reopens in the layout you last left it in; files you haven't opened before use the **Open documents in** setting (Preview by default). New documents (`⌘N`) open in Split.
- **The editor loads only when needed:** a window that stays in Preview never creates it, so viewing is as light as ever, and no keystroke in Preview can change the file.
- **Editor:** [CodeMirror 6](https://codemirror.net) with Markdown (GFM) syntax highlighting, multiple cursors, undo history, bracket matching, optional line numbers and soft wrap (on by default), and light/dark themes that follow the system appearance. Font, size, line numbers and wrapping are in Settings.
- **Search & replace:** `⌘F` in the editor opens a native-styled search bar (Next / Previous / All, Match Case, Regex, Whole Word, Replace / Replace All; Escape closes it). `⌥⌘F` always searches the preview.
- **Formatting:** `⌘B` bold, `⌘I` italic, `⌘K` link, `⇧⌘H` `==highlight==`, `⌘/` toggle HTML comment (also in the Format menu, which is available only while the editor is showing).
- **Preview while typing:** the preview re-renders shortly after you pause and keeps its place. In Split, scrolling either pane moves the other to the matching source line, and clicking an Outline heading moves both panes and puts the cursor on that heading.
- **Saving:** the standard macOS document system — New / Open / Save / Save As / Duplicate / Rename / Revert, autosave and Versions (File ▸ Revert To ▸ Browse All Versions). Saving, closing a window, switching apps and quitting always include the very last keystrokes. Files keep their original line endings (LF / CRLF / CR), byte-order mark and trailing newline.
- **Files changed on disk:** a document with no unsaved edits reloads automatically when another app changes the file (live reload, Tail, Jump to New all keep working), including editors like vim that save by rename-and-replace. If you have unsaved edits, the file is left alone and macOS's standard "changed by another application" choice appears when you save, so neither side is overwritten silently. The **Reload** button asks before discarding unsaved edits.
- mdview registers for Markdown files as an *alternate* editor, so it never takes over as the default app for `.md` from Obsidian or another editor unless you choose it.

## Repository layout

| Path | What it is |
|------|------------|
| `mdview/mdview/` | The app target: document type, window (ribbon, layouts, editor + preview panes), menus, live reload / external-change handling, settings panels |
| `mdview/mdview.xcodeproj` | The Xcode project, with one shared **mdview** scheme |
| `Packages/MarkdownRenderKit/` | Local Swift package the app links: the WKWebView preview (markdown-it, KaTeX, highlight.js, callouts, highlights, frontmatter, relative images), Outline and Find views, the Print Preview/PDF pipeline, and the CodeMirror editor view |
| `Packages/MarkdownRenderKit/editor-src/` | Source for the vendored CodeMirror bundle (`npm run build`, output committed, so building the app never needs Node) |
| `Fuzz/` | libFuzzer targets and a local smoke test (`make fuzz-smoke`) |

## Requirements

- macOS 26.4 or later (the app's deployment target)
- Xcode 26.4 or later to build from source

## Building

Open `mdview/mdview.xcodeproj` in Xcode, choose the **mdview** scheme and press `⌘R`. From the command line, `make check` runs format-check, lint and a Release build.

## License

MIT — see [LICENSE](LICENSE).
