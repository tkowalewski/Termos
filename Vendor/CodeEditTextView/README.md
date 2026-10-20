# CodeEditTextView (patched)

A copy of [CodeEditTextView](https://github.com/CodeEditApp/CodeEditTextView) 0.12.1 (MIT, see `LICENSE.md`). Termos's `Package.swift` points to this directory, and it replaces the version that CodeEditSourceEditor would otherwise fetch.

## Changes

- `TextLayoutManager+Layout.swift`, `layoutLine(...)`: removed the local `var maxFoundLineWidth = maxFoundLineWidth`, which shadowed the `inout` parameter. Because of it, the widest line was never reported, the text view stayed as wide as the window, and long lines could not be scrolled horizontally. The bug came in with upstream PR #118 (0.12.0).

Remove this directory once an upstream release fixes it.

SwiftPM warns about a "conflicting identity for codeedittextview" when it resolves packages. The warning is expected: the local copy takes the place of the remote package. The warning says future SwiftPM versions may turn this into an error. If that happens, depend on a fork of CodeEditSourceEditor that points to this copy, or on a fixed upstream release.
