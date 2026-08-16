# Folio

**Preview.app for local Markdown.** Folio is a native macOS reader (editing is second-class). It is not Electron, not a notes app, and not a vault.

Files stay ordinary `.md` on disk. Folders are a library, not a second brain.

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later (macOS 14 SDK)

## Building

Open `Folio.xcodeproj` in Xcode and run the **Folio** scheme.

## Opening files

Double-click a `.md` file to open it in Folio. Folio registers as the default handler for Markdown (`.md`, `.markdown`, `.mdown`, `.mkd`, `.mdwn`). To restore another app, select a file in Finder, choose **File → Get Info**, and change **Open with**.

**File → Open Folder…** (⌥⌘O) or drop a folder on the Dock icon to show a library sidebar. Click a `.md` file to replace the document in the same window. Hidden files, `.git`, `node_modules`, and other vendor directories are skipped.

Relative links and images resolve from the file’s directory. Clicking a `.md` link opens it in Folio; `http(s)` and `mailto` use the system. Remote images are not downloaded.

**Edit → Find** (⌘F) searches the focused pane. Matches are highlighted like Notes: every hit in yellow, the current hit stronger. Reading find skips table and image attachments. Replace is only available in the source pane.

Saves are always UTF-8 without a BOM. Files larger than 50 MB are refused.

## License

MIT. See [LICENSE](LICENSE).

## Status

v1 is under construction via stacked pull requests. This tree reads and edits a Markdown file, renders GFM in a native reading pane, and can open a folder as a library sidebar.
