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
Application.swift / Instance.swift: menus, file lifecycle, single instance IPC.

## Validation policy
Record actual automatic, mouse/keyboard and performance results separately in docs/VALIDATION.md. Do not claim unrun checks. Use isolated `TINYEDITOR_DATA_DIR` for tests. Never clear real user preferences/recovery/recent files. One normal GUI instance; quit normally before replacement.

## Decisions and remaining work
Initial environment: macOS 27.2, arm64; Swift 6.4 CLI tools, no full Xcode required. Deployment target 13.0. Ad hoc signing if Developer ID unavailable. Initial repository empty, GitHub private chenzhen411/TinyEditor. Implementation and validation in progress.


## Final local validation (2026-10-29)
- Build: `./scripts/build.sh`, arm64, minos 13.0, ad hoc; no Developer ID/notarization.
- Core: 9 cases, 3,061 assertions pass. Integration: 65 checks pass, normalExit=true / exitCode=0. Distribution ZIP and extracted strict signature pass; resource links complete.
- Fresh blank launch: 785 / 291 / 273 ms observed spawn-to-ready, caches NOT purged, main RSS ~101 MiB. Markdown helper cost is separately recorded.
- 10 MB multiline: ~426 ms open-to-display, 30 MB: ~1.02 s. 10 MB single line: ~149 ms via native 32K UTF-16 projection, editing ~115 ms.
- Single-instance concurrency: eight actual child launches, plus alternate app installation path, no duplicate request handling.
- Quit fix: clean documents return terminateNow; dirty confirmation uses run-loop scheduling and approval flag. Never dispatch a reply-needed confirmation onto a serial queue currently blocked by NSApplication.terminate. Repeated Quit must not bypass unsaved protection.
- File Provider may asynchronously add FinderInfo to the generated workspace .app. Stage/sign/ZIP in /tmp, then remove only generated bundle Finder metadata after copy and strictly verify. Do not strip user quarantine or clear caches.
- Final evidence: docs/VALIDATION.md, GUI-VALIDATION.md and JSON reports. Do not upgrade “implemented” or programmatic move checks into claims that all mouse drag destinations passed.

## Remaining compatibility / verification scope
- Full real mouse cross-window drop matrix, drag-out/reorder and fast switch video remain unverified due CUA destination coordinate failures. Native drag begins and Escape cancellation were observed.
- Real Chinese IME candidate UI pending; NSTextInputClient marked-text/commit and emoji across page boundaries pass.
- macOS 13–26, Intel/Universal, multi-MB Markdown rendering, sidebar physical resize/scroll preservation require additional hardware/manual validation.
- Long-line projection limits continuous mouse selection to the visible page. Full-source copy/save/find/replace and cross-page undo are implemented.
- Mermaid tiny excludes mindmap/architecture and internal Mermaid KaTeX; document KaTeX is bundled separately. Local SVG images intentionally not served by resource handler.
