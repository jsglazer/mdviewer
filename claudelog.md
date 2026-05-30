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

---

---

# 2026-05-22

## Interaction 14 — About panel opening as tab instead of popup — v1.0.4

**Root cause:** `AppDelegate.windowDidBecomeKey` sets `tabbingMode = .preferred` on every new titled window that becomes key — including the About panel — then the async task merges it into the existing document tab group.

**Fix:**
- `mdviewApp.swift`: After `NSApp.orderFrontStandardAboutPanel(...)`, immediately set `NSApp.keyWindow?.tabbingMode = .disallowed`. This runs synchronously before the `DispatchQueue.main.async` merge task fires (since both are on the main queue). When the async task runs, the about window already has `tabbingMode = .disallowed`.
- `AppDelegate.swift`: Added `window.tabbingMode != .disallowed` to the async guard in `windowDidBecomeKey`, so any window explicitly marked `.disallowed` is skipped by the merge logic entirely.

**Version:** bumped to `1.0.4`.

## Interaction 13 — Image rendering still broken (sandbox was blocking reads) — v1.0.3

**Root cause:** The app has `ENABLE_APP_SANDBOX = YES` in the project build settings. In a sandboxed app, `Data(contentsOf:)` is restricted to files the user explicitly opened — not sibling files in the same directory. So `inlineImages()` in `ContentView` was silently `continue`-ing on every image (the `guard let data = try? Data(contentsOf: imageURL) else { continue }` always failed), and no base64 substitution happened.

**Fix:** Changed `ENABLE_APP_SANDBOX = YES` → `ENABLE_APP_SANDBOX = NO` in both Debug and Release build configs in `project.pbxproj`. This is appropriate for a personal non-App-Store viewer tool. With the sandbox off, `Data(contentsOf:)` can read image files adjacent to the opened markdown file, and the base64 inline approach works as intended.

**Version:** bumped to `1.0.3`.

## Interaction 12 — Crash fix (follow-up to Interaction 11)

**Root cause of crash:** Two issues introduced in Interaction 11:

1. `allowingReadAccessTo: URL(fileURLWithPath: "/")` — macOS 26 (Darwin 25) rejects this overly-broad access URL in WKWebView, causing an exception/crash when opening a file.

2. `applicationShouldTerminateAfterLastWindowClosed` returning `true` — the File > Open dialog is an `NSPanel`/window; when the user selects a file, the dialog closes before the document window appears. During that brief gap, `applicationShouldTerminateAfterLastWindowClosed` fires and the app quits, appearing as a "crash".

**Fixes:**

- **Image rendering** (`MarkdownView.swift` reverted, `ContentView.swift` updated): Removed `fileURL` and `allowingReadAccessTo` change from `MarkdownView`; `allowingReadAccessTo` restored to `resourcesURL`. Instead, `ContentView.process()` calls `inlineImages(in:baseDir:)` which uses `NSRegularExpression` to find `![alt](relative_path)` patterns, reads each image from disk as `Data`, base64-encodes it, and replaces the path with a `data:image/...;base64,...` URI before the markdown string is passed to the WebView. No WebKit file access permissions needed.

- **Quit on last window** (`AppDelegate.swift`): Replaced `applicationShouldTerminateAfterLastWindowClosed` with a `NSWindow.willCloseNotification` observer (`windowWillClose`). Guards against `NSPanel` (file open dialogs). Waits 0.5s after each real document window closes, then checks if any non-panel titled windows remain (visible or minimized). If none remain, calls `NSApp.terminate(nil)`. The 0.5s delay absorbs the open-dialog→document-window transition so the app doesn't quit prematurely.

- `render-template.html` reverted to original single-argument `render`/`setMarkdown`.

## Interaction 11 — Three bug fixes

**Image rendering (`![Source](text_source.png)`):**
- Root cause: `MarkdownView` loaded `render-template.html` via `loadFileURL(_:allowingReadAccessTo: resourcesURL)` — WebKit was sandboxed to the app bundle's Resources folder, so images referenced by relative paths in markdown files (located elsewhere on disk) were blocked.
- Fix in `MarkdownView.swift`: changed `allowingReadAccessTo` to `URL(fileURLWithPath: "/")` (non-sandboxed app, viewer use case); added `fileURL: URL?` parameter; `Coordinator` now stores `fileURL` and passes the file's parent directory as a second argument to `window.setMarkdown(markdown, baseDir)`.
- Fix in `render-template.html`: updated `render(markdown, baseDir)` to post-process `<img>` tags after markdown-it renders — any `src` that isn't already absolute (`http:`, `data:`, `/`, `file:`) is prefixed with `baseDir` (a `file:///` URL string), making relative images resolve correctly.

**New window instead of tab on "Open With":**
- Root cause: `windowDidBecomeKey` tab-merge logic ran synchronously; if window state hadn't fully settled (timing with `NSApplication` window list / tab group state), `addTabbedWindow` either found no target or merged into an already-tabbed group incorrectly.
- Fix in `AppDelegate.swift`: wrapped merge body in `DispatchQueue.main.async` to defer until after the current run loop cycle; added guard to skip if window is already in a tab group (`tabbedWindows == nil || count <= 1`); added `!($0.tabbedWindows ?? []).contains(where: { $0 === window })` to the candidate filter.

**App stays open after last tab is closed:**
- Fix in `AppDelegate.swift`: implemented `applicationShouldTerminateAfterLastWindowClosed(_:)` returning `true`.

# 2026-05-28

## Interaction 18 — Window resize fix, Find, FileWatcher fix, Settings updates — v1.0.8

### Window resize on settings close
**Root cause:** `.sheet(isPresented:)` on macOS resizes the parent window to fit the sheet, then shrinks it on dismiss.  
**Fix:** Replaced sheet with a SwiftUI `Settings` scene in `mdviewApp.swift`. Settings now open in their own standard Preferences window (CMD-, / mdview menu), with no effect on document window size.

### Settings button removed from ribbon
Removed the `gearshape` ribbon button and the `.sheet` modifier from `ContentView`. Settings are now accessed via CMD-, or mdview menu → Settings…, which is standard macOS convention.

### Settings: Recent Files count
Added a `Stepper` in SettingsView ("Show N recent files", range 5–50, step 5) backed by `@AppStorage("maxRecentFiles")`. Also restructured SettingsView to use SwiftUI `Form` with `.formStyle(.grouped)` and a "Revert" button alongside Save/Clear.

### FileWatcher auto-refresh fix
Two bugs fixed in `FileWatcher.swift`:
1. **Silent stop on missing file:** When `open()` returns -1 (file temporarily absent after a delete/rename rotation), the old code returned without retrying. Fix: schedule a retry at +0.5s with `[weak self]` so the chain stops automatically on dealloc.
2. **Stale source after restart:** Cancelling the existing source before creating a new one (`source?.cancel(); source = nil`) before each `open()` prevents multiple live sources from co-existing if events fire rapidly.
Also added `.extend` to the event mask (some editors truncate-and-rewrite, which appears as an extend event rather than write).

### Find feature (CMD-F)
New `FindResultsView.swift` panel shown on the LEFT side of the content area.

**Access:** CMD-F, or Edit menu → Find…. Escape (in the search field or while webview has focus) closes find and clears highlights.

**Ribbon:** Search field appears centred between "Tail" and "Contents" buttons via ZStack overlay when Find is active.

**Results panel (210px):** Lists all matches. Each row shows "…2-word-before **match** 2-word-after…". Clicking a row smooth-scrolls the webview to that highlight.

**JS (`render-template.html`):**
- `window.findText(query)` — walks all text nodes in `#content` via `TreeWalker`, wraps each match in `<mark class="find-result" id="find-N">`, returns JSON array of `{index, before, match, after}`.
- `window.clearFind()` — replaces each `<mark>` with its plain text and normalises adjacent nodes.
- `window.scrollToMatch(index)` — `scrollIntoView` on `#find-N`.
- CSS: `mark.find-result` styled with a yellow/amber background (dark-mode variant included).

**Swift (`MarkdownView.swift`):** `FindResult` struct added. `MarkdownController` gains `findText`, `clearFind`, `scrollToMatch`. Coordinator implements the corresponding `do*` methods with JSON round-tripping.

**`MarkdownWebView.keyDown`:** Now also intercepts Escape (keyCode 53) to post `mdviewCloseFind` notification, and CMD-F to post `mdviewOpenFind` (preventing WebKit's built-in find panel).

**`mdviewApp.swift`:** `Notification.Name.mdviewOpenFind` extension defined here. Edit menu group adds "Find…" with CMD-F shortcut.

**Version:** bumped to `1.0.8`.

---

## Interaction 17 — Keyboard shortcut navigation — v1.0.7

CMD+Arrow shortcuts for document navigation:
- **CMD+Up** → scroll to top of file
- **CMD+Down** → scroll to bottom of file
- **CMD+Left** → page up (scroll up 90% of viewport height)
- **CMD+Right** → page down (scroll down 90% of viewport height)

**Implementation:** `MarkdownWebView` private subclass of `WKWebView` added to `MarkdownView.swift`. Overrides `keyDown(with:)` — when `.command` modifier is present, intercepts the four arrow `specialKey` values, calls the corresponding JS function, and returns without calling `super`. All other key events fall through to `super`. `makeNSView` now instantiates `MarkdownWebView` instead of `WKWebView`.

**Why subclass:** Without interception, WebKit handles CMD+Left/Right as browser back/forward history navigation (wrong in a viewer). CMD+Up/Down may already scroll to top/bottom in WebKit but overriding ensures our JS functions are used consistently.

Four new JS functions added to `render-template.html`: `scrollToTop`, `scrollToEnd`, `scrollPageUp`, `scrollPageDown`. These are separate from the existing tail-mode `scrollToBottom` (which centers the last element) — `scrollToEnd` goes to `document.body.scrollHeight` for a hard bottom.

**Version:** bumped to `1.0.7`.

---

## Interaction 16 — TOC button order + Settings panel with custom CSS — v1.0.6

### TOC header button order change
Collapse button icon changed from `chevron.right` → `chevron.up` and moved to the left of the expand button (`chevron.down`). Order is now: collapse (↑) then expand (↓).

### Settings panel
- New `SettingsView.swift` — modal sheet with a monospaced `TextEditor` for custom CSS and Save/Cancel buttons. "Clear CSS" button appears when CSS is non-empty.
- CSS persisted via `@AppStorage("customCSS")`.
- New `gearshape` ribbon button on the right (after Contents) opens the sheet.
- `MarkdownView` gains a `customCSS: String` parameter. The `Coordinator` tracks `lastAppliedCSS` and calls `window.setCustomCSS(css)` (a new JS function) whenever the CSS changes or the webview reloads.
- `render-template.html` addition: `window.setCustomCSS(css)` creates/updates a `<style id="user-css">` element in `<head>`. Since this is in `<head>` (not `#content`), it survives markdown re-renders.

**Version:** bumped to `1.0.6`.

---

## Interaction 15 — Ribbon bar with three navigation buttons — v1.0.5

### Features added

**Ribbon bar** — horizontal toolbar below the title bar, above the markdown content:
- "Jump to New" button (icon: `arrow.up.to.line`) — toggle mode; after each file update, auto-scrolls to the first line where content diverged from the previous version. Uses line-by-line prefix comparison to find the first changed/added line, then calls `window.scrollToNewContent(line)` in JS.
- "Tail" button (icon: `arrow.down.to.line`) — toggle mode; after each file update, centers the last block element in the viewport via `window.scrollToBottom()`. Mutually exclusive with "Jump to New". Activating tail mode immediately scrolls to bottom even if the file hasn't changed.
- "Contents" button (icon: `sidebar.right`) — toggles a 220px TOC panel on the right.

**Table of Contents panel** (`TOCView.swift`, new file) — right-side panel listing H1–H5 headings:
- Parses headings from the rendered DOM via `window.getHeadings()` after each render
- Chevron toggle buttons (▼/▶) per heading that has children; clicking collapses/expands sub-headings
- "Expand all" (chevron.down) and "Collapse all" (chevron.right) header buttons
- Indentation by level (12px per level); H1 labels bold, H2–H5 caption weight
- Clicking a heading calls `window.scrollToHeading(id)` to smooth-scroll the webview

### Architecture changes

**`render-template.html`** additions:
- `source_map` markdown-it core rule — stamps `data-md-line` (0-based source line) on top-level block tokens
- Custom `heading_open` renderer — generates unique `id` attributes per heading (de-duplicated with counter), used by TOC jump
- `window.getHeadings()` — returns `JSON.stringify([{level, text, id}])` for all h1–h5 in `#content`
- `window.scrollToNewContent(line)` — scrolls to first `[data-md-line]` element at or after the given source line
- `window.scrollToBottom()` — smooth-scrolls last child of `#content` into center of viewport
- `window.scrollToHeading(id)` — smooth-scrolls heading element into view

**`MarkdownView.swift`** additions:
- `TOCItem` struct (id, level, text) — shared with TOCView and ContentView
- `AutoScrollMode` enum — `.none`, `.firstNew`, `.tail`
- `MarkdownController` class — plain reference type (not ObservableObject) used as command bus; ContentView holds it as `@State`, passes it to MarkdownView which registers its coordinator as the handler
- `Coordinator` extended with `lastRenderedMarkdown` tracking, `fetchHeadings()` post-render, `doScrollToNewContent/Bottom/Heading()`, and `firstDivergingLine()` static helper

**`ContentView.swift`** restructured:
- `RibbonButton` private view — Label + active highlight styling
- Layout: VStack(ribbonBar, HStack(MarkdownView, optional TOCView))
- `autoScrollMode`, `showTOC`, `tocItems` state vars

**Version:** bumped to `1.0.5`.

---

## Interaction 10 — Three polish tweaks

**Auto-refresh on file change:**
- New `FileWatcher.swift` — wraps `DispatchSource.makeFileSystemObjectSource` watching `.write`, `.rename`, `.delete` events
- Handles editors (vim, etc.) that save via rename by cancelling and restarting the watcher on the new inode
- 50ms read delay ensures write is fully flushed before content is read
- `ContentView.swift` updated to accept `fileURL: URL?`, owns a `@State var watcher: FileWatcher?`, initializes text from document on appear and starts watcher; cleans up on disappear
- `mdviewApp.swift` updated to pass `config.fileURL` to ContentView

**Top padding reduced:**
- `render-template.html` — `#content` top padding changed from `32px` to `16px`

**About panel icon:**
- Added `CommandGroup(replacing: .appInfo)` in `mdviewApp.swift` that calls `NSApp.orderFrontStandardAboutPanel` with explicit `.applicationIcon` key to ensure the custom teal icon appears

---

# 2026-05-28

## Session resumed from compact

## Interaction — Line numbers, Show CSS, Settings modal, Outline rename

### User request
- Add **Line Numbers** ribbon button + View menu item: toggles source line numbers in the gutter
- Add **Show CSS** ribbon button + View menu item: pop-up panel showing all inline CSS (selectable text)
- Make **Settings** a pop-up modal (gear button in ribbon, doesn't resize main window)
- Rename "Contents" → "Outline"; default to collapsed when first opened

### Changes — v1.0.9

**`render-template.html`**
- Added `.line-num` CSS: `display:inline-block`, gutter via negative `margin-left`, hidden from selection via `user-select:none`
- Added `body.line-numbers #content { padding-left: 4em }` to create gutter space
- Added `_lineNumbers` state, `_applyLineNumbers()`, called from `window.setMarkdown` so numbers survive re-renders
- Added `window.setLineNumbers(enabled)` callable from Swift
- Added `window.getDocumentCSS()` — returns only inline stylesheets (skips highlight.js/katex to avoid overwhelming output)

**`MarkdownView.swift`**
- Added `showLineNumbers: Bool` property to `MarkdownView`
- Added `lastLineNumbers: Bool` tracking to `Coordinator`; `doSetLineNumbers()` method
- Updated `updateNSView` to call `doSetLineNumbers` when value changes
- Added `doGetDocumentCSS(completion:)` to `Coordinator`
- Added `setLineNumbers()` and `getDocumentCSS(completion:)` to `MarkdownController`

**`ContentView.swift`**
- Added `@State private var showLineNumbers: Bool = false`
- Added `@Environment(\.openSettings) private var openSettings`
- Ribbon left: added Line Numbers button (`list.number` icon)
- Ribbon right: added Show CSS button (`doc.plaintext` icon), renamed Contents→Outline, added gear button (`gearshape`) calling `openSettings()`
- Added `showDocumentCSS()` helper that calls `getDocumentCSS` then `CSSPanelController.shared.show(css:)`
- Added `onReceive` handlers for `.mdviewToggleLineNumbers` and `.mdviewShowCSS` notifications

**`mdviewApp.swift`**
- Added `.mdviewToggleLineNumbers` and `.mdviewShowCSS` notification names
- Added `CommandMenu("View")` with Line Numbers (⇧⌘L) and Show Document CSS items

**`TOCView.swift`**
- Header label changed from "Contents" to "Outline"
- Added `.onAppear { collapsed = Set(items.filter { hasChildren($0) }.map(\.id)) }` — defaults all parent headings to collapsed each time the panel opens

**New: `ShowCSSView.swift`**
- SwiftUI view: monospaced text with `.textSelection(.enabled)`, line count shown in header

**New: `CSSPanelController.swift`**
- Singleton `NSWindow`-based panel, 620×520 initial size, resizable, `isReleasedWhenClosed = false` to survive repeated opens

### Build result
`** BUILD SUCCEEDED **` at v1.0.9

---

## Interaction — Find result row: full-width click + selection highlight

### User request
- Click anywhere in a result row (not just the text) should jump to that result
- Clicked row highlights in `#FFFFE0`; stays highlighted until another row is selected

### Changes — v1.0.10

**`FindResultsView.swift`**
- Added `@State private var selectedIndex: Int?` to `FindResultsView`
- `FindRow` now receives `isSelected: Bool` and `highlightColor: Color`; applies `#FFFFE0` background when selected
- Added `.contentShape(Rectangle())` to `FindRow`'s button so the full row width is the hit target (not just the text)
- `onSelect` in `ForEach` sets `selectedIndex = result.id` before calling the parent callback
- `.onChange(of: results)` resets `selectedIndex = nil` on each new search

### Build result
`** BUILD SUCCEEDED **` at v1.0.10

---

## Interaction — Three bug fixes

### User report
- Settings window still resizes main window
- Search result rows: whitespace not clickable (only text area works)
- Text wraps to a narrow column instead of spanning the window width

### Changes — v1.0.11

**Fix 1: Settings as true standalone window**
- Created `SettingsPanelController.swift` — singleton `NSWindow` (titled + closable only, no resize), `isReleasedWhenClosed = false`, `NSHostingController(rootView: SettingsView())` created once and reused; centers on first open
- Removed `Settings { SettingsView() }` scene from `mdviewApp.swift` (the SwiftUI Settings scene was interfering with main window sizing)
- Added `CommandGroup(after: .appInfo)` with Settings… (⌘,) to keep the standard keyboard shortcut
- `ContentView.swift`: removed `@Environment(\.openSettings)`, gear button now calls `SettingsPanelController.shared.show()` directly

**Fix 2: Full-row hit area in search results**
- `FindResultsView.swift`: replaced `Button` wrapping the snippet with plain view + `.contentShape(Rectangle())` + `.onTapGesture` — `.contentShape` on a plain view reliably extends hit area to whitespace; the `Button`+`.contentShape` approach was not working on macOS
- Used `Color(NSColor.controlBackgroundColor).opacity(0.001)` as non-selected background (effectively invisible but gives the view a hittable surface)

**Fix 3: Full-width text**
- `render-template.html`: removed `max-width: 860px` and `margin: 0 auto` from `#content`; changed side padding from 40px to 24px so text flows edge-to-edge with breathing room

### Build result
`** BUILD SUCCEEDED **` at v1.0.11

---

## Interaction — Settings fix, keyboard shortcuts, shortcuts window

### User report
- Settings window collapses to just the title bar on open
- Click in white space of search result rows still not working
- (New) Add keyboard shortcuts for all major features
- (New) View menu item that opens a keyboard shortcuts reference window

### Changes — v1.0.12

**Fix: Settings window collapsing to title bar**
- Root cause: `NSHostingController` set as `contentViewController` hands window-sizing control to SwiftUI, which collapses the frame before the first layout pass completes
- Fix in `SettingsPanelController.swift`: replaced `w.contentViewController = NSHostingController(...)` with `w.contentView = NSHostingView(...)` — window retains its own frame, SwiftUI just fills it
- Added `.resizable` to styleMask and `minSize` as a safety floor

**New keyboard shortcuts (all added to View menu)**
- ⌘J: Jump to New Content
- ⌘⇧T: Tail Mode
- ⌘⇧L: Line Numbers (existing)
- ⌘⇧O: Toggle Outline
- ⌘⇧C: Show Document CSS
- ⌘⇧K: Keyboard Shortcuts window
- ⌘F: Find (existing, in Edit menu)
- ⌘,: Settings (existing, in app menu)
- ⌘↑↓←→: Navigation (in keyDown handler)

**New: `KeyboardShortcutsView.swift`**
- Sectioned table (Navigation, Scroll Mode, View, Find, App) with monospaced key labels
- `ShortcutsPanelController` singleton in same file, uses `NSHostingView` pattern

**`mdviewApp.swift`**
- Added 4 new notification names: `.mdviewToggleJumpToNew`, `.mdviewToggleTail`, `.mdviewToggleOutline`, `.mdviewShowKeyboardShortcuts`
- Filled out View menu with all shortcuts and "Keyboard Shortcuts" item

**`ContentView.swift`**
- Added 4 new `.onReceive` handlers for the new notifications

### Build result
`** BUILD SUCCEEDED **` at v1.0.12

---

## Interaction — Window frame persistence + Settings tab fix

### User report
- Settings, CSS, and Shortcuts windows open as tabs in the document window instead of as standalone popups
- Window size and position should be remembered across launches

### Changes — v1.0.13

**Fix: Popup windows appearing as tabs**
- Root cause: macOS automatic tabbing groups new `NSWindow` instances into the document's tab bar when "Prefer Tabs" is set to Always in System Settings
- Fix: switched all three panel controllers (`SettingsPanelController`, `CSSPanelController`, `ShortcutsPanelController`) from `NSWindow` to `NSPanel`; `NSPanel` is AppKit's type for accessory/utility windows and sets `tabbingMode = .disallowed` by default; also explicitly set `tabbingMode = .disallowed` on each panel
- Also fixed `CSSPanelController` which still used `contentViewController = NSHostingController(...)` (same collapse risk as Settings); changed to `contentView = NSHostingView(...)` pattern

**Feature: Window size and position persistence**
- Added `WindowFrameSaver: NSViewRepresentable` to `ContentView.swift`
- Calls `window?.setFrameAutosaveName("mdviewDocumentWindow")` on the underlying `NSWindow` via `DispatchQueue.main.async` (window is nil synchronously during makeNSView)
- macOS automatically saves and restores the frame to UserDefaults under that key
- Added as `.background(WindowFrameSaver())` on the main VStack — zero visual impact, out of layout flow

### Build result
`** BUILD SUCCEEDED **` at v1.0.13

---

## Interaction — Settings tab root-cause fix

### User report
Settings (and other popup windows) still appearing as tabs despite NSPanel + tabbingMode = .disallowed.

### Root cause found
`AppDelegate.windowDidBecomeKey` was the culprit. It runs on EVERY window becoming key, and:
1. Explicitly sets `window.tabbingMode = .preferred` — overwriting our `.disallowed`
2. Calls `target.addTabbedWindow(window, ordered: .above)` to group it into a tab

`windowWillClose` already had `!(window is NSPanel)` to exclude panels, but `windowDidBecomeKey` was missing that guard.

### Fix — v1.0.14
`AppDelegate.swift` line 40: added `!(window is NSPanel)` to the guard in `windowDidBecomeKey` — panels (Settings, CSS, Shortcuts) are now completely skipped by the auto-tabbing logic.

### Build result
`** BUILD SUCCEEDED **` at v1.0.14

---

# 2026-05-30

## Interaction 1 — Arrow key navigation in Find mode

### Request
When the find bar is open and a search query is active, pressing up/down arrows should navigate through search results.

### Changes — v1.0.15

**`FindResultsView.swift`**
- Changed `@State private var selectedIndex` to `@Binding var selectedIndex` so the parent (`ContentView`) controls the selection
- Wrapped `ScrollView` in `ScrollViewReader`; added `.onChange(of: selectedIndex)` to auto-scroll the sidebar list to the active result

**`ContentView.swift`**
- Added `@State private var currentFindIndex: Int? = nil`
- Passed `$currentFindIndex` to `FindResultsView`
- Added `navigateFind(delta:)` — wraps around with modulo, jumps to first (delta=1) or last (delta=-1) when nothing is selected
- Wired `.onKeyPress(.downArrow)` → `navigateFind(delta: 1)` and `.onKeyPress(.upArrow)` → `navigateFind(delta: -1)` on the find TextField
- Changed `onSubmit` to call `navigateFind(delta: 1)` (Enter/Return advances to next match)
- Reset `currentFindIndex` in `closeFind()` and in the `onChange(of: text)` handler

## Interaction 4 — Outline panel active-heading highlight (v1.0.18)

**`render-template.html`**
- Added `_getActiveHeadingIds(referenceEl)`: finds the nearest heading preceding a DOM element (or scroll position when `null`) and collects all ancestor headings up the level hierarchy
- Added debounced scroll listener (80 ms) that posts heading IDs to Swift via `window.webkit.messageHandlers.activeHeadings`
- `scrollToMatch` now calls `_postActiveHeadings(el)` immediately using DOM position (not scroll position) so the TOC updates instantly
- `setMarkdown` triggers `_scheduleHeadingNotify()` after each render

**`MarkdownView.swift`**
- Added `WeakScriptHandler` proxy to avoid WKUserContentController retain cycle
- `makeNSView` creates `WKWebViewConfiguration` with the `activeHeadings` message handler
- Added `onActiveHeadingsChanged: ([String]) -> Void` to `MarkdownView` struct and `Coordinator`
- `Coordinator.handleScriptMessage` decodes the JSON array and calls the callback on main thread

**`ContentView.swift`**
- Added `@State private var activeHeadingIDs: Set<String> = []`
- Passes `onActiveHeadingsChanged` to `MarkdownView` and `activeIDs` to `TOCView`

**`TOCView.swift`**
- Added `activeIDs: Set<String>` parameter to `TOCView`
- `TOCRow` gains `isActive: Bool`; active rows get `#bdffd9` background (`Color(red:189/255, green:1.0, blue:217/255)`)

## Interaction 2 — Cyan highlight for selected result (sidebar only)

**`FindResultsView.swift`** — changed `highlightColor` from light yellow to `Color.cyan.opacity(0.35)` (v1.0.16)

## Interaction 3 — Cyan highlight for active match in reading pane (v1.0.17)

**`render-template.html`**
- Added `mark.find-result.active` CSS rule: `rgba(0, 220, 220, 0.65)` background + thin cyan outline; dark-mode variant also added
- Added `_activeMarkIndex` tracking variable; `_clearFind` resets it to -1
- `scrollToMatch` now removes `.active` from the previous mark and adds it to the newly scrolled-to mark
