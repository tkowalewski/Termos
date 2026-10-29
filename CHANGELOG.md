# Changelog

All notable changes to Termos are listed here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Context menu in the file browser: create a new file or folder (inside the clicked folder, next to the clicked file, or in the root when clicking empty space) and move files or folders to the Trash. A new file opens in the editor.
- Split the terminal into an upper and a lower pane with <kbd>⌘H</kbd>, each running its own shell, started in the working directory of the current one. Click a pane or use <kbd>⌥⌘[</kbd> / <kbd>⌥⌘]</kbd> to focus it; the file browser, go to file and search in files follow the focused pane. <kbd>⌘W</kbd> or `exit` closes the focused pane. Hide Termos is no longer on <kbd>⌘H</kbd>; it stays in the Termos menu.

### Changed
- The editor wraps long lines to the width of the view instead of scrolling horizontally.

## [0.5.0] - 2026-10-26

### Added
- Search in files (<kbd>⌘E</kbd>): searches the contents of the files in the active terminal's working directory, like `ag` or `rg`, and lists the matching lines grouped by file (up to 50 per file and 500 in total). In a git repository `.gitignore` is respected; binary files and files larger than 10 MB are skipped. The search ignores case unless the query has an uppercase letter. It starts with the text selected in the editor, otherwise with the last query. The chosen line opens in the editor with the match selected.

## [0.4.0] - 2026-10-25

### Added
- Review mode (<kbd>⌘R</kbd>): the git changes of the active terminal's repository. Changed, new and deleted files are listed in place of the file browser, staged and unstaged separately, and the selected file's diff is shown in place of the terminal or editor.
- Stage, unstage or discard selected lines or whole hunks from the diff's context menu, and whole files with the buttons above the diff or from the file list.

## [0.3.0] - 2026-10-23

### Added
- Syntax highlighting for `Gemfile` and `*.gemspec` files (Ruby) and `*.html.erb` templates (HTML).
- Drag terminals in the sidebar to reorder them. <kbd>⌘1</kbd>…<kbd>⌘9</kbd> follow the new order.

### Changed
- The status bar below the editor is as tall as the file tabs and has the same background as the sidebar.
- Quick open (<kbd>⌘P</kbd>) outside a git repository skips hidden folders, app bundles, `~/Library`, `DerivedData` and `Pods`, and lists up to 20,000 files. It no longer scans the whole home folder or triggers macOS privacy prompts there.
- Quick open keeps file lists of only the 4 most recently searched folders in memory.

## [0.2.0] - 2026-10-22

### Added
- New file (<kbd>⌘N</kbd>) opens an empty, untitled tab in the editor. The first save asks where to put it, starting in the terminal's working directory.
- A status bar below the editor shows the path of the file, relative to the terminal's working directory. Click the file icon next to it to copy the path.

### Changed
- Each terminal shows or hides its own file browser. <kbd>⌘B</kbd> toggles it for the active terminal only, and switching terminals brings back that terminal's choice.

## [0.1.0] - 2026-10-21

First release.

### Added
- Multiple terminals in a sidebar, each running your login shell and kept alive in the background with 10,000 lines of scrollback.
- A new terminal opens in the working directory of the current one.
- Rename terminals inline in the sidebar.
- <kbd>⌥</kbd> types characters from your keyboard layout instead of acting as Meta.
- File browser (<kbd>⌘B</kbd>) showing the active terminal's working directory. It follows `cd`, updates live and remembers expanded folders.
- Code editor in place of the terminal: tabs, syntax highlighting, two-space indentation, horizontal scrolling of long lines, reloading of files changed on disk.
- Trailing whitespace is trimmed on save, except in Markdown.
- VS Code style multiple cursors.
- Go to file (<kbd>⌘P</kbd>), from the terminal and the editor.
- Universal (Apple silicon and Intel), signed and notarized builds, published as a GitHub release for each version tag.

[Unreleased]: https://github.com/tkowalewski/Termos/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/tkowalewski/Termos/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/tkowalewski/Termos/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/tkowalewski/Termos/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/tkowalewski/Termos/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/tkowalewski/Termos/releases/tag/v0.1.0
