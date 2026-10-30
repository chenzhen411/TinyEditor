# TinyEditor

## Product and constraints
- App name is **TinyEditor**, no spaces. Native macOS 13+, Simplified Chinese.
- Implement locally from scratch. No files from another Mac. Official open-source preview libraries permitted.
- AppKit/TextKit 1 editor, lazy WKWebView preview, stable document identity/undo across custom tabs/windows.
- Plain text is authoritative. Preserve encoding/BOM/newlines. Protect unsaved work, external conflicts and recovery drafts.
- Markdown copy uses recorded source ranges, never reconstructed DOM text. Pasteboard plain text only.
- One GUI process per user across app paths, using flock + acknowledged local IPC before creating NSApplication.
- Window state (sidebar) separate from document state. Drag moves same document object; authenticated in-process drag tokens.
- No accounts, cloud, AI, plugins, project management. No clearing user data or unknown edits.

## Build
`./scripts/build.sh` creates an arm64 Release app and ZIP under artifacts. Swift Package Manager, system frameworks only. `swift test` exercises data protection and source mapping support. Preview dependencies are vendored and locked; runtime requires no Node/network.

## Architecture
Core.swift: codec, line index, file version, preferences/recovery.
Document.swift: canonical NSTextStorage, undo, I/O and conflict protection.
Editor.swift: TextKit 1 editor, visible-line gutter and lexical highlighter.
Preview.swift + Resources/Preview: WKWebView, source-mapped Markdown, offline render/security.
Window.swift: tabs, drag/drop, sidebar, toolbar and status.
Drag.swift: authenticated native drag forwarding and the transparent registered frame region.
Application.swift / Instance.swift: menus, file lifecycle, single instance IPC.

## Validation policy
Record actual automatic, mouse/keyboard and performance results separately in docs/VALIDATION.md. Do not claim unrun checks. Use isolated `TINYEDITOR_DATA_DIR` for tests. Never clear real user preferences/recovery/recent files. One normal GUI instance; quit normally before replacement.

## Decisions and remaining work
Initial environment: macOS 27.2, arm64; Swift 6.4 CLI tools, no full Xcode required. Deployment target 13.0. Ad hoc signing if Developer ID unavailable. Initial repository empty, GitHub private chenzhen411/TinyEditor. Implementation and validation in progress.


## 1.0.0 local validation history (2026-10-29)
- Build: `./scripts/build.sh`, arm64, minos 13.0, ad hoc; no Developer ID/notarization.
- Core: 9 cases, 3,061 assertions pass. Integration: 65 checks pass, normalExit=true / exitCode=0. Distribution ZIP and extracted strict signature pass; resource links complete.
- Fresh blank launch: 785 / 291 / 273 ms observed spawn-to-ready, caches NOT purged, main RSS ~101 MiB. Markdown helper cost is separately recorded.
- 10 MB multiline: ~426 ms open-to-display, 30 MB: ~1.02 s. 10 MB single line: ~149 ms via native 32K UTF-16 projection, editing ~115 ms.
- Single-instance concurrency: eight actual child launches, plus alternate app installation path, no duplicate request handling.
- Quit fix: clean documents return terminateNow; dirty confirmation uses run-loop scheduling and approval flag. Never dispatch a reply-needed confirmation onto a serial queue currently blocked by NSApplication.terminate. Repeated Quit must not bypass unsaved protection.
- File Provider may asynchronously add FinderInfo to the generated workspace .app. Stage/sign/ZIP in /tmp, then remove only generated bundle Finder metadata after copy and strictly verify. Do not strip user quarantine or clear caches.
- Final evidence: docs/VALIDATION.md, GUI-VALIDATION.md and JSON reports. Do not upgrade “implemented” or programmatic move checks into claims that all mouse drag destinations passed.

## Remaining compatibility / verification scope
- Real cross-window combinations, all content/toolbar drop regions, drag-out/reorder and Escape passed in 1.0.2 using explicitly authorized CGEvent input. High-frame-rate fast-switch video remains unverified.
- Real Chinese IME candidate UI pending; NSTextInputClient marked-text/commit and emoji across page boundaries pass.
- macOS 13–26, Intel/Universal, multi-MB Markdown rendering, sidebar physical resize/scroll preservation require additional hardware/manual validation.
- Long-line projection limits continuous mouse selection to the visible page. Full-source copy/save/find/replace and cross-page undo are implemented.
- Mermaid tiny excludes mindmap/architecture and internal Mermaid KaTeX; document KaTeX is bundled separately. Local SVG images intentionally not served by resource handler.


## 1.0.1 interaction fixes
- Drag.swift owns window-level native drop routing. Hint views ALWAYS return nil from hitTest, even during a drag; never use an input-catching overlay to receive tabs.
- Retain the TabCell draggingSource until the end callback, including strip rebuild/source window close. Set accepted before moving a document. Reset before detach. Source/session token validation remains in-process only.
- Check NSEvent.type BEFORE keyCode; keyCode on mouse/AppKit events can throw an ObjC exception and skip Swift cleanup. Regression finish(.move) now completes.
- Active tab exposes its close button as an independent accessibility element; exact close-button geometry routes mouse hits. Sidebar layout has reentry protection and restores preferred width after split adjustment.
- 73 integration checks pass with normal process exit; 3,061 core assertions pass. 1.0.1 build 2 ZIP/signature/resources verified.
- Real CUA coordinate clicks passed close second tab, sidebar open/close, dirty close cancellation, and controls after Escape. Full native cross-window release/detach still pending; CUA sends begin but no moved/destination/end until Escape. User CGEvent authorization requested asynchronously, NOT received and NOT assumed.
- Evidence: docs/DRAG-REGRESSION-1.0.1.md and docs/evidence/1.0.1-*.

## 1.0.2 real interaction acceptance
- Preinstall DropOverlay as a registered native drag destination on the window frame before tracking starts. Window-only or ancestor-only registration did not receive WebKit body drops in real tests. Its hitTest ALWAYS returns nil, including during drag; registering a drag region does not require capturing ordinary mouse input.
- Use one forwarding implementation for registered content/frame regions and the native window. Retain private nonce/source-object validation and source-cell lifetime protection.
- Flat tabs use subtle system backgrounds, short separators, a small close symbol and medium active title. No rounded outline. Refresh tab visuals/close visibility immediately when active changes; do not rely on later hover or edits.
- 76 integration checks pass, normalExit=true/exitCode=0. Core remains 9 cases / 3,061 passing assertions. 75 recorded real-input evidence checks pass, including all four single/multi combinations, preview/editor/toolbar/sidebar/status/tabs, second/third detach, reorder, Escape inside/outside, real undo/redo, manual JSON and exact third close.
- User explicitly authorized a separate temporary InputCheck driver and broad OS permission for acceptance only. It is outside the shipped app/ZIP. Permission was disabled after acceptance; both AXIsProcessTrusted and CGPreflightPostEventAccess return false. Do not regrant without authorization.
- Driver must be built BEFORE permission grant and registered from a persistent project output location. /tmp was not resolvable by TCC; ad hoc rebuild changed the signature and required removal/re-addition of the stale grant. Never change the driver binary mid-acceptance or edit TCC databases.
- File Provider metadata settling can exceed five retries. Build allows twenty bounded retries, removing only generated app FinderInfo, then still requires strict verification.
- Current evidence and scope: docs/DRAG-REGRESSION-1.0.2.md, real-drag-results.json and evidence/1.0.2-*.

## 1.0.3 sidebar/document header alignment
- TabStrip belongs to documentArea inside the right split pane. Split occupies all content below the toolbar; the sidebar includes the document header height. Body and status share the tab strip's width.
- Collapse the hidden sidebar view to zero width, retain preferred sidebarWidth separately, invalidate split drawing and suppress hidden native divider painting/color. Hiding an arranged view alone leaves an old frame/divider on this macOS version.
- 83 isolated integration checks pass with normal exit. New checks cover open/resize/collapse alignment, full collapsed width, second-tab native hitTest, window-to-strip insertion coordinates and hidden divider geometry/color. Real CUA clicks checked first/second tab switching and second-tab close with sidebar open.
- Native drag source/token logic is unchanged. No CGEvent permission regrant or new full real drag matrix is claimed for 1.0.3. See docs/LAYOUT-1.0.3.md.

## 1.0.4 rounded tab cards
- User's reference replaces the earlier flat-tab visual decision. Use 36 pt strip, 30 pt rounded active card (8 pt radius), left document icon/title and right 24 pt close hit area. New-tab button follows the visible tabs; overflow remains horizontally scrollable.
- Preserve the right-pane sidebar alignment and existing native drag/token routing. Do not hardcode screenshot coordinates in event handlers.
- 83 isolated integration checks pass with normal exit. Real CUA screenshots and clicks verified light/dark appearance, first/second tab switching, sidebar open/collapse and exact second-tab close. See docs/TABS-1.0.4.md.
- No InputCheck permission regrant or full real drag matrix rerun in this visual update.
