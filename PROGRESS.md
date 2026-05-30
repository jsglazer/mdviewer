# mdview Progress

## Current version: 1.0.4

## Session: 2026-05-22

### What was fixed

| Issue | Root cause | Fix |
|---|---|---|
| Images not rendering (`![alt](file.png)`) | App is sandboxed (`ENABLE_APP_SANDBOX = YES`); `Data(contentsOf:)` blocked for sibling files | Disabled sandbox; `ContentView.inlineImages()` reads images from disk, base64-encodes them, and substitutes data URIs into the markdown string before WebKit sees it |
| "Open With" opens new window instead of tab | Tab-merge in `windowDidBecomeKey` had a timing race; ran before window state settled | Wrapped merge in `DispatchQueue.main.async`; tightened guard conditions |
| App stays open after last tab is closed | Missing quit-on-last-window logic | Added `windowWillClose` observer in `AppDelegate` that checks after 0.5s delay; excludes `NSPanel` and counts both visible and minimized windows before calling `NSApp.terminate` |
| Crash on file open | (1) `allowingReadAccessTo: URL(fileURLWithPath: "/")` rejected by macOS 26; (2) `applicationShouldTerminateAfterLastWindowClosed` returning `true` quit the app during the open-dialog → doc-window gap | Reverted WKWebView access to `resourcesURL`; replaced delegate method with `windowWillClose` observer with delay |
| About panel opening as tab | `windowDidBecomeKey` applied `tabbingMode = .preferred` to every titled window including the About panel | Set `NSApp.keyWindow?.tabbingMode = .disallowed` after `orderFrontStandardAboutPanel`; added `tabbingMode != .disallowed` guard to the async merge task |

### Key architectural decisions
- **Image rendering**: base64 inline approach (Swift-side preprocessing) chosen over WKWebView file access expansion — cleaner, no security model changes, works inside or outside sandbox
- **Sandbox off**: appropriate for a personal non-App-Store tool; simplifies file access for image loading and future features
- **Quit logic**: `windowWillClose` observer with 0.5s delay is safer than `applicationShouldTerminateAfterLastWindowClosed` for `DocumentGroup` apps where file-open dialogs briefly leave zero windows

### Next steps / known issues
- Images are re-encoded from disk on every file-watcher update; acceptable for now but could cache if large images are common
- "Open With" tab merging relies on timing (0.5s async); could be made more reliable with explicit document-open hooks
