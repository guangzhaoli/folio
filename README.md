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

Saves are always UTF-8 without a BOM. Files larger than 50 MB are refused.

## License

MIT. See [LICENSE](LICENSE).

## Status

v1 is under construction via stacked pull requests. This tree opens and saves a single Markdown file in an unhighlighted text view.
