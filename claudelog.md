# 2026-05-21

## Interaction 1 — What Claude files are you using?

I'm using two CLAUDE.md files:

1. **`/Users/josh/CLAUDE.md`** (global) — restricts work to `/Users/josh/VaultSchar/HAL/`
2. **`/Users/josh/Dev/llm/mdview/CLAUDE.md`** (project) — restricts work to this folder, instructs me to save terminal output to `claudelog.md`, always ask questions, and notes your email and today's date

The project-level file takes precedence for this session. Note there's a conflict: the global file says I can only work in `VaultSchar/HAL/`, but the project file says I can only work in this folder (`/Users/josh/Dev/llm/mdview/`). I'm treating the project file as the active constraint since it's the one scoped to this working directory.

---

## Interaction 2 — @Prompt-01-Design.md design overview

Here's how I'd approach it, plus a token estimate.

### Approach: Native Swift Document-Based App

**Technology stack:**
- **SwiftUI + AppKit** — native macOS app (Apple Silicon binary), gives you the real Mac feel and a clear path to iOS via SwiftUI reuse
- **WKWebView** — for markdown rendering; lets us use battle-tested JavaScript libraries
- **markdown-it.js** — bundled in the app resources; handles full CommonMark + many Obsidian extensions (tables, strikethrough, footnotes, task lists)
- **MathJax 3** (or KaTeX as a lighter alternative) — bundled, injected into the render template for `$...$` and `$$...$$` math
- **Xcode Document-Based App template** — gives you tabs, window management, and Finder integration almost for free

---

### Key pieces

| Piece | What it does |
|---|---|
| `MarkdownDocument.swift` | `FileDocument` that reads `.md`/`.markdown` files |
| `ContentView.swift` | Hosts a `WKWebView`, watches doc content for changes |
| `render-template.html` | Static HTML shell with markdown-it + MathJax loaded from app bundle |
| `MarkdownRenderer.swift` | Injects raw markdown into the WebView via `evaluateJavaScript` |
| `Info.plist` | Declares `CFBundleDocumentTypes` for `.md` and `.markdown`, `LSHandlerRank = Alternate` → enables right-click "Open With" in Finder |

---

### Tab support

macOS native window tabbing is automatic for Document-Based Apps — each opened file gets a tab at no extra cost. I'd enable `NSWindow.allowsAutomaticWindowTabbing = true` and we're done.

---

### Obsidian rendering fidelity

markdown-it supports plugins for:
- Tables, task lists, strikethrough (GFM extensions)
- Footnotes, definition lists
- Syntax-highlighted code blocks (via highlight.js, also bundled)
- MathJax handles `$inline$` and `$$block$$` math

The one Obsidian feature we won't get: `[[wikilinks]]` — that would require a custom markdown-it plugin, which is doable later.

---

### iOS path

Since the app is SwiftUI-first, porting later means: swap `WKWebView` for a `WKWebView` (it exists on iOS too), adjust the document picker, and drop the `Info.plist` Finder integration. The core rendering logic is identical.

---

### Token estimate

| Task | Est. output tokens |
|---|---|
| Project structure + Swift files (~600 lines) | ~4,000 |
| HTML/JS render template | ~500 |
| Info.plist + entitlements | ~300 |
| Explanation between steps | ~1,000 |
| **Total** | **~6,000** |

This is comfortably within a single session window (Claude's context is 200K tokens). The full implementation is completable in one go, though I'd suggest we do it in logical chunks so you can review each piece. Ready to build when you say so.

---

## Interaction 3 — Why wasn't output saved to claudelog.md?

I simply failed to follow the instruction. I answered your questions without writing anything to `claudelog.md`. That was my mistake — I should have been appending my output there after each response. I've now backfilled all missed content above.
