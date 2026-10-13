# LightTodo for macOS / 轻量待办

A lightweight, offline macOS checklist built with native AppKit. It has no account, advertising, analytics, background service, or network dependency.

轻量、离线的 macOS 原生待办工具：无需账号，没有广告、统计、后台服务或联网依赖。

## Features / 功能

- Editable checklist with completion history and one-click restore
- Enter splits or creates the next item; Shift+Enter inserts a line break
- Empty-item deletion with Backspace/Delete
- Per-item local reminders; overdue reminders are shown when the app is reopened
- Optional HTTP/HTTPS or local-file links for each item
- Window pinning, opacity, colors, and a local background image
- Undo/redo, standard macOS menus, and keyboard shortcuts
- Row context menus for completing, restoring, deleting, and copying text
- Confirmed history deletion and local JSON data export
- Atomic JSON persistence, previous-save backup, and damaged-file preservation
- Universal build for Apple Silicon and Intel, targeting macOS 12+

## Shortcuts / 快捷键

| Shortcut | Action |
| --- | --- |
| `⌘N` | Add a todo / 新增待办 |
| `⌘1` / `⌘2` | Show active/history / 切换待办与完成记录 |
| `⌘⇧P` | Toggle always-on-top / 切换置顶 |
| `Enter` | Split at the caret / 从光标处拆分 |
| `⇧Enter` | Insert a line break / 同条内换行 |
| `⌘Z` / `⌘⇧Z` | Undo/redo / 撤销与重做 |

## Install / 安装

1. Open [Releases](https://github.com/claudeliu/lighttodo-mac/releases) and download `LightTodo-mac-universal.zip`.
2. Unzip it and move `LightTodo.app` to Applications.
3. This free build is ad-hoc signed rather than Apple-notarized. If macOS says the developer cannot be verified, open **System Settings → Privacy & Security** and choose **Open Anyway** for LightTodo. Do not disable system-wide security protections.

If macOS reports that the app is damaged or contains malware, stop and report the exact message instead of bypassing it.

## Usage notes / 使用说明

- Click the clock beside an item to set or cancel a reminder. The app must be running to alert at the exact time; after shutdown or sleep, overdue reminders appear when the app is opened again.
- Click the link icon to add, open, change, or remove an HTTP/HTTPS link or a local file. Local-file links work only while that file remains at the same path on that Mac.
- Completing an item cancels its reminder. Restoring an item does not restore an old reminder.
- Right-click a row to copy its text or manage it. Deleting is separate from completing and requires confirmation for non-empty items and history.
- Use **Todo → Export Todo Data…** to save a local JSON copy.
- The app does not sync between devices.

## Privacy and data / 隐私与数据

All user content remains under:

```text
~/Library/Application Support/LightTodoNativeMac/
```

`tasks.json` contains current items, history, reminders, and link targets. `tasks.backup.json` is the previous saved copy. Imported background images are stored in the same directory. The repository and release package do not include user data.

Back up that directory while the app is closed. Deleting the app does not delete this data directory.

## Build from source / 从源码构建

Requirements: macOS 12 or newer with Xcode Command Line Tools.

```bash
git clone https://github.com/claudeliu/lighttodo-mac.git
cd lighttodo-mac
bash build.sh
```

The universal app and ZIP are written to `out/`. The build script runs the native smoke/data test before packaging.

## Verification scope / 验证范围

The automated test covers launch, editing, Enter/Shift+Enter behavior, delayed completion, history and restore, reminders, links, appearance, image handling, persistence, and backup recovery. Passing CI does not guarantee compatibility with every macOS version, input method, display, or full-screen game.

## License

[MIT](LICENSE)
