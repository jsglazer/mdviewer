# mdview

[![GitHub release](https://img.shields.io/github/v/release/jsglazer/mdviewer?logo=github)](https://github.com/jsglazer/mdviewer/releases) [![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org) [![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/jsglazer/mdviewer/blob/main/LICENSE) [![Made with Claude](https://img.shields.io/badge/Made_with-Claude-D97756?logo=anthropic)](https://claude.ai) [![Gemini Flash Antigravity](https://img.shields.io/badge/Gemini%20Flash-Antigravity-4f86f7?logo=google-gemini&logoColor=white)](https://github.com/google-gemini) [![CI](https://github.com/jsglazer/mdviewer/actions/workflows/ci.yml/badge.svg)](https://github.com/jsglazer/mdviewer/actions/workflows/ci.yml) [![CodeQL](https://github.com/jsglazer/mdviewer/actions/workflows/codeql.yml/badge.svg)](https://github.com/jsglazer/mdviewer/actions/workflows/codeql.yml) [![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/jsglazer/mdviewer/badge)](https://securityscorecards.dev/viewer/?uri=github.com/jsglazer/mdviewer)

A lightweight macOS app for viewing Markdown files. Open a file and it renders instantly; the view updates automatically whenever the file changes on disk.

## Features

### Rendering
- Full GitHub-flavoured Markdown: headings, tables, task lists, fenced code blocks, blockquotes, inline HTML
- Syntax highlighting via [highlight.js](https://highlightjs.org)
- Math typesetting via [KaTeX](https://katex.org) — inline (`$…$`) and display (`$$…$$`)
- Relative image paths resolved automatically so local images display correctly
- Light and dark mode, following the system appearance
- YAML frontmatter (a `---`/`key: value`/`---` block at the top of a file) is rendered as a distinct metadata block rather than as Markdown prose

### Live Reload
- Watches the open file for changes and re-renders in place — no manual refresh needed
- **Reload** button re-reads the current file from disk on demand
- **Jump to New** mode scrolls to the first changed line on each reload
- **Tail** mode keeps the bottom of the document in view (useful for logs)

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
- **Line Numbers** — toggle gutter line numbers keyed to Markdown source lines
- **Show CSS** — inspect the full stylesheet applied to the current document
- **Custom CSS** — inject your own styles via Settings
- The app version is shown at the top-right of the toolbar

### Keyboard Shortcuts
- `⌘P` — Print… (opens Print Preview)
- `⇧⌘E` — Export as PDF…
- `⌘F` — Find
- `⌘↑` / `⌘↓` — Jump to top / bottom
- `⌘←` / `⌘→` — Page up / page down
- `↑` / `↓` (in find bar) — previous / next match
- `↑` / `↓` (in Outline) — previous / next heading
- `←` / `→` (in Outline) — collapse / expand grouped heading
- `Escape` — close find

A full shortcut reference is available from the Settings panel.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ to build from source

## Building

Open `mdview/mdview.xcodeproj` in Xcode and press `⌘R`.

## License

MIT — see [LICENSE](LICENSE).
