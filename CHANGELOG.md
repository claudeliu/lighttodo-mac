# Changelog

## Unreleased

- Added confirmed JSON data import with validation, automatic pre-import backup, and safe handling of background images that are unavailable on the destination Mac.

## 0.3.1

- Added per-item local reminders with one-shot scheduling and overdue delivery after reopening.
- Added per-item HTTP/HTTPS and local-file links with add, open, edit, choose-file, and remove actions.
- Kept reminders idle when none are scheduled and cancel them when an item is completed.
- Extended native self-tests for reminder persistence, one-time delivery, completion cancellation, and link validation.
- Added standard macOS menus, keyboard shortcuts, undo/redo, row context menus, text copy, confirmed history management, and JSON export.
- Hardened malformed-data detection, preserved damaged originals, and kept legacy files backward compatible.
- Added an MIT license, public installation/build/privacy documentation, and a 30-day CI artifact.
- Updated GitHub Actions to current, commit-pinned action releases.

## 0.2.0

- Initial universal macOS release with checklist editing, completion history, restore, appearance controls, local persistence, and backup recovery.
