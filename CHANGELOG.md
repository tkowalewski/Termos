# Changelog

All notable changes to Termos are listed here, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Syntax highlighting for `Gemfile` and `*.gemspec` files (Ruby) and `*.html.erb` templates (HTML).

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

[Unreleased]: https://github.com/tkowalewski/Termos/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/tkowalewski/Termos/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/tkowalewski/Termos/releases/tag/v0.1.0
