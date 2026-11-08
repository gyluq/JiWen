# 记问 JiWen

<p align="center">
  <img src="design/icon/app_icon.png" width="96" alt="JiWen icon">
</p>

<p align="center">A fully offline Android notebook for personal knowledge — fast capture, Markdown editing, tags, Chinese full-text search, and local backups.</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.47.9-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.13.7-0175C2?logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white" alt="Android">
  <img src="https://img.shields.io/badge/Data-offline%20%C2%B7%20SQLite-8A5A3B" alt="Offline SQLite">
  <img src="https://img.shields.io/github/v/release/gyluq/JiWen?display_name=tag" alt="Release">
</p>

## Overview

JiWen is a single-user, local-first notebook for Android. It combines quick capture, Markdown editing and preview, tag-based organization, instant Chinese full-text search with highlighted hits, three list densities, a note outline, a recycle bin, statistics, and JSON / ZIP backup and export. Notes, images, and backups live in the app's private storage, and the app declares no network permission.

## Screenshots

| Note list | Full-text search |
| --- | --- |
| <img src="docs/screenshots/note-list.png" width="260" alt="Note list"> | <img src="docs/screenshots/search.png" width="260" alt="Full-text search"> |
| Titles, summaries, tags, update time, and pending / answered status at a glance. Compact, standard, and relaxed densities. | Chinese substring search with highlighted hits, combined with tag, status, and time-range filters. |

| Note detail | Markdown editor |
| --- | --- |
| <img src="docs/screenshots/detail.png" width="260" alt="Note detail"> | <img src="docs/screenshots/editor.png" width="260" alt="Markdown editor"> |
| One rendering pipeline for reading, export, and preview. Long notes load lazily and an H1–H3 outline jumps between sections. | Toolbar for headings, lists, code blocks, bold, italic, images, and links, with undo / redo and an edit / preview toggle. |

<p align="center">
  <img src="docs/screenshots/note-list-dark.png" width="260" alt="Dark mode">
  <br>
  Dark mode
</p>

## Features

| Area | What it does |
| --- | --- |
| Capture | Save a note in seconds; autosave and draft recovery; pending / answered status; pin and favorite notes |
| Markdown | H1–H3, ordered and unordered lists, code blocks (monospace, horizontal scroll, one-tap copy), bold, italic, links, image insertion and full-screen preview |
| Images | Pick from the gallery or camera; images wider than 1600 px are compressed; unreferenced files are cleaned up when notes are deleted |
| Tags | Create, rename, and delete tags; attach multiple tags to a note; tag list shows note counts; deleting a tag keeps its notes |
| Search | Full-text search across titles, bodies, and tag names; Chinese substrings match even from the middle of a word; highlighted hits; opening a note jumps to the first hit; last 20 search terms are kept |
| Filter and sort | Combine tag, status, and time range; sort by last modified, creation time, or title |
| Reading | Three list densities; note outline with H1–H3 navigation and current-section highlight; dark mode; body font size levels |
| Data safety | Recycle bin with 30-day retention; automatic backup on the first launch of a day or after 50 edits, keeping the latest 5; manual backup and restore |
| Import and export | Export a note as Markdown; export all notes as a ZIP with an `assets/` folder; full JSON backup and restore; split pasted text into multiple notes by delimiter; import `.txt` / `.md` files |
| Privacy | 4–6 digit PIN lock with optional fingerprint / face unlock; auto-lock timeout; screenshots and recent-task thumbnails blocked while locked |
| Extras | Share a note as Markdown; `[[title]]` internal links; statistics for note count, pending notes, and tag distribution |

## Tech stack

| Layer | Choice |
| --- | --- |
| Framework | Flutter 3.47.9 / Dart 3.13.7 |
| Storage | `sqlite3` local database plus app-private file storage |
| Images | `image_picker`, `path_provider` |
| Import / export | `archive` (ZIP), `file_picker`, `share_plus` |
| Security | `local_auth` (biometrics), `crypto` |
| Other | `url_launcher`, `scrollable_positioned_list` |

Markdown parsing, rendering, and editing are implemented in this repository under `lib/util/` and `lib/widgets/`.

## Project layout

```text
lib/
├── data/          # database, settings, attachments, backup, import/export, app lock
├── models/        # note and tag models
├── screens/       # list, detail, editor, search, tags, trash, statistics, settings
├── util/          # Markdown parsing and editing, search highlighting, text import, time formatting
├── widgets/       # list tiles, tag chips, Markdown view, action sheets
└── theme.dart     # shared palette and theme
test/              # unit tests for Markdown, search highlighting, and data tools
design/            # app icon and HTML interaction prototype
docs/screenshots/  # README screenshots
```

## Build and run

Requirements: Flutter 3.47.9 (stable), Dart 3.13.7, Android SDK 36, JDK 17 or newer.

```bash
flutter pub get
flutter run                 # debug build on a device or emulator
flutter test                # unit tests
flutter build apk --release # output: build/app/outputs/flutter-apk/app-release.apk
```

Installable builds are available on the [Releases](https://github.com/gyluq/JiWen/releases) page. Current release builds use the Flutter template's debug signing config, which is fine for personal side-loading; configure your own keystore before publishing to an app store.

## Data and privacy

- The database, images, and backups live in the app's private storage. Uninstalling the app removes them, so export a backup before upgrading or uninstalling.
- The app declares no `INTERNET` permission and contains no accounts, cloud sync, or online services.
- A forgotten PIN cannot be recovered; reinstall the app and restore from a backup instead.
