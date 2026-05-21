# 2026-05-21

## Interaction 1 — What Claude files are you using?

I'm using two CLAUDE.md files:

1. **`/Users/josh/CLAUDE.md`** (global) — restricts work to `/Users/josh/VaultSchar/HAL/`
2. **`/Users/josh/Dev/llm/mdview/CLAUDE.md`** (project) — restricts work to this folder, instructs me to save terminal output to `claudelog.md`, always ask questions, and notes your email and today's date

The project-level file takes precedence for this session. Note there's a conflict: the global file says I can only work in `VaultSchar/HAL/`, but the project file says I can only work in this folder (`/Users/josh/Dev/llm/mdview/`). I'm treating the project file as the active constraint since it's the one scoped to this working directory.

---

## Interaction 2 — @Prompt-01-Design.md design overview

### Approach: Native Swift Document-Based App

**Technology stack:**
- **SwiftUI + AppKit** — native macOS app (Apple Silicon binary), clear path to iOS via SwiftUI reuse
- **WKWebView** — for markdown rendering; lets us use battle-tested JavaScript libraries
- **markdown-it.js** — bundled; handles full CommonMark + Obsidian extensions (tables, strikethrough, footnotes, task lists)
- **MathJax 3 or KaTeX** — bundled, for `$...$` and `$$...$$` math
- **Xcode Document-Based App template** — gives tabs, window management, and Finder integration almost for free

### Key pieces

| Piece | What it does |
|---|---|
| `mdviewDocument.swift` | `FileDocument` that reads `.md`/`.markdown` files |
| `ContentView.swift` | Hosts a `WKWebView`, watches doc content for changes |
| `render-template.html` | Static HTML shell with markdown-it + math loaded from app bundle |
| `Info.plist` | Declares `CFBundleDocumentTypes` for `.md`/`.markdown`, `LSHandlerRank = Alternate` |

### Token estimate

| Task | Est. output tokens |
|---|---|
| Swift files (~600 lines) | ~4,000 |
| HTML/JS render template | ~500 |
| Info.plist + entitlements | ~300 |
| Explanation | ~1,000 |
| **Total** | **~6,000** |

---

## Interaction 3 — Why wasn't output saved to claudelog.md?

Failed to follow the instruction — answers were given without writing to `claudelog.md`. Backfilled all missed content and committed to appending going forward.

---

## Interaction 4 — Build the app in chunks

Proposed chunk breakdown confirmed by user:

- **Chunk 1** — Xcode project scaffold + Info.plist for .md/.markdown
- **Chunk 2** — MarkdownDocument model (FileDocument)
- **Chunk 3** — Render template (HTML + markdown-it + KaTeX + highlight.js, all bundled)
- **Chunk 4** — WKWebView integration (MarkdownView.swift + ContentView.swift)
- **Chunk 5** — Polish (tabs, window title, scroll preservation, right-click verification)

Project location: `/Users/josh/Dev/llm/mdview/`. Git repo initialized locally, no remote yet.

---

## Interaction 5 — Chunk 1: Xcode scaffold + Info.plist

User created Xcode Document-Based App project at `/Users/josh/Dev/llm/mdview/mdview/`. Generated files: `mdviewApp.swift`, `ContentView.swift`, `mdviewDocument.swift`, `Info.plist`, `Assets.xcassets`.

Changes made:
- **`Info.plist`** — replaced placeholder `com.example.plain-text` UTType with `public.markdown` and `net.daringfireball.markdown`; set `CFBundleTypeRole` to `Viewer`, `LSHandlerRank` to `Alternate`
- **`mdviewDocument.swift`** — changed `readableContentTypes` to use `[.markdown]` (later fixed, see Interaction 6)

---

## Interaction 6 — Chunk 2: MarkdownDocument model + build fix

Changes to `mdviewDocument.swift`:
- Changed default text from `"Hello, world!"` to `""` (viewer, not editor)
- First attempt used `[.markdown]` static member → **build failed**: "Type 'UTType' has no member 'markdown'" — `UTType.markdown` is not a built-in static property
- **Fix:** replaced with `UTType(filenameExtension: "md") ?? .plainText` and `UTType(filenameExtension: "markdown") ?? .plainText`
- Build succeeded after fix

Final `mdviewDocument.swift` state:
```swift
static let readableContentTypes: [UTType] = [
    UTType(filenameExtension: "md") ?? .plainText,
    UTType(filenameExtension: "markdown") ?? .plainText
]
```

---

## Interaction 7 — Chunk 3: Render template

User chose **KaTeX** over MathJax (smaller, faster; covers most LaTeX).

Libraries downloaded and placed in `/Users/josh/Dev/llm/mdview/mdview/mdview/Resources/`:
- `markdown-it.min.js` — via npm
- `katex.min.js`, `katex.min.css`, `fonts/` — via npm
- `highlight.min.js`, `highlight-github.min.css` — via curl from cdnjs

`render-template.html` written with:
- GitHub-style CSS, dark/light mode via `prefers-color-scheme`
- markdown-it with task list support (inline checkbox plugin)
- KaTeX for `$...$` (inline) and `$$...$$` (block) math
- highlight.js for syntax-highlighted code blocks
- `window.setMarkdown(markdown)` — Swift-to-JS bridge function

User added `Resources` folder to Xcode as a **folder reference** (blue folder) to preserve `fonts/` subdirectory structure needed by KaTeX CSS.

---

## Interaction 8 — Chunk 4: WKWebView integration

Two files written:

**`MarkdownView.swift`** (new) — `NSViewRepresentable` wrapping `WKWebView`:
- Loads `Resources/render-template.html` via `loadFileURL(_:allowingReadAccessTo:)` so relative JS/CSS/font paths resolve correctly
- Uses a `Coordinator` as `WKNavigationDelegate` to track page load completion before calling JS
- Passes markdown to JS via `window.setMarkdown(json)` using `JSONEncoder` for safe escaping (handles backslashes, backticks, Unicode, `${` sequences)
- Stores `pendingMarkdown` so content set before page load is rendered immediately on `didFinish`

**`ContentView.swift`** (replaced) — reduced to:
```swift
var body: some View {
    MarkdownView(markdown: document.text)
}
```

User instructed to add `MarkdownView.swift` to Xcode project, then build.

**Issues encountered and fixed:**
- Xcode showed the mdview folder as blue (folder reference), so "Add Files" was greyed out. Fix: used File > New > File > Swift File, replaced content with MarkdownView code.
- App ran but showed blank white screen.
- Debug revealed `htmlURL: nil` — Xcode flattened the Resources folder contents into the bundle root instead of keeping them in a `Resources/` subdirectory.
- Fix 1: Changed `Bundle.main.url(forResource:subdirectory:)` to root-level lookup; used `Bundle.main.resourceURL` for base access URL.
- Fix 2: KaTeX CSS referenced fonts as `fonts/KaTeX_xxx.woff2` but fonts were flattened to root — fixed with `sed -i '' 's|url(fonts/|url(|g'` on `katex.min.css`.
- **App now renders markdown correctly.** Remaining console noise (WebContent sandbox XPC errors) is harmless — WKWebView's subprocess always emits these in sandboxed apps.
- Debug prints removed from final `MarkdownView.swift`.

---

## Interaction 9 — Chunk 5: Polish

**"New" menu item:** `DocumentGroup(viewing:)` alone did not suppress it. Fixed by adding `.commands { CommandGroup(replacing: .newItem) { } }` to the scene in `mdviewApp.swift`.

**Window tabs:** Added `AppDelegate.swift` with an `NSApplicationDelegateAdaptor`. Observes `NSWindow.didBecomeKeyNotification`; on each new titled window at normal level, sets `tabbingMode = .preferred` and calls `target.addTabbedWindow(window, ordered: .above)` if there's already a visible window. New files now open as tabs in the existing window.

**Window title:** Automatic via `DocumentGroup` — shows filename correctly, no code needed.

**Math rendering broken:** All other markdown rendered correctly but math was blank. Root cause: `markdown-it` was configured with `html: false`, which caused it to escape the HTML that KaTeX generates during the pre-processing step. Fix: changed `html: false` to `html: true` in `render-template.html` markdown-it config. Math now renders correctly.

**Final state:** App renders full markdown (headings, tables, task lists, code blocks with syntax highlighting, inline and block math) in tabs, with correct window titles, no "New" menu item, and right-click "Open With" available in Finder.
