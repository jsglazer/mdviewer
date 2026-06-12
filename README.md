# mdview

[![GitHub release](https://img.shields.io/github/v/release/jsglazer/mdviewer?logo=github)](https://github.com/jsglazer/mdviewer/releases)
[![GitHub license](https://img.shields.io/github/license/jsglazer/mdviewer)](https://github.com/jsglazer/mdviewer/blob/main/LICENSE)
[![Made with Claude](https://img.shields.io/badge/Made_with-Claude-D97756?logo=anthropic)](https://claude.ai)
[![CI](https://github.com/jsglazer/mdviewer/actions/workflows/ci.yml/badge.svg)](https://github.com/jsglazer/mdviewer/actions/workflows/ci.yml)
[![CodeQL](https://github.com/jsglazer/mdviewer/actions/workflows/codeql.yml/badge.svg)](https://github.com/jsglazer/mdviewer/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/jsglazer/mdviewer/badge)](https://securityscorecards.dev/viewer/?uri=github.com/jsglazer/mdviewer)

A lightweight macOS app for viewing Markdown files. Open a file and it renders instantly; the view updates automatically whenever the file changes on disk.

## Features

### Rendering
- Full GitHub-flavoured Markdown: headings, tables, task lists, fenced code blocks, blockquotes, inline HTML
- Syntax highlighting via [highlight.js](https://highlightjs.org)
- Math typesetting via [KaTeX](https://katex.org) — inline (`$…$`) and display (`$$…$$`)
- Relative image paths resolved automatically so local images display correctly
- Light and dark mode, following the system appearance

### Live Reload
- Watches the open file for changes and re-renders in place — no manual refresh needed
- **Jump to New** mode scrolls to the first changed line on each reload
- **Tail** mode keeps the bottom of the document in view (useful for logs)

### Find
- `⌘F` opens the find bar; results appear in a sidebar panel
- Up / Down arrows (or Return) step through matches
- Active match is highlighted **cyan** in the reading pane; all other matches are yellow
- Escape clears and closes find

### Outline (Table of Contents)
- Sidebar panel listing all headings (h1–h5) with collapse/expand controls
- Clicking a heading scrolls the reading pane to that section
- The current heading and all its ancestors are highlighted as you read or navigate, so you always know where you are in the document structure

### Display Options
- **Line Numbers** — toggle gutter line numbers keyed to Markdown source lines
- **Show CSS** — inspect the full stylesheet applied to the current document
- **Custom CSS** — inject your own styles via Settings

### Keyboard Shortcuts
- `⌘F` — Find
- `⌘↑` / `⌘↓` — Jump to top / bottom
- `⌘←` / `⌘→` — Page up / page down
- `↑` / `↓` (in find bar) — previous / next match
- `Escape` — close find

A full shortcut reference is available from the Settings panel.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ to build from source

## Building

Open `mdview/mdview.xcodeproj` in Xcode and press `⌘R`.

## License

MIT — see [LICENSE](LICENSE).
