# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Snap guide modes aligned with layout types (quadrants/manual, halves for row/wide and vertical layouts).
- Manual layout implementation.
- Glass-style HUD and snap guides using visual effect views.
- HUD fade in/out animations.

### Changed
- Layout geometry calculations precomputed per reflow in paned layouts.
- Reflow coalescing to prefer structural changes and reduce storms.
- Layout HUD typography updated to rounded system fonts.
- Snap guide rendering updated to Tahoe-style rounding and glass material.

### Fixed
- Window frames clamped to screen bounds after padding and minimum size adjustments.
- Guarded against zero-dimension ratio math in paned layouts.
- Reduced redundant AX frame sets and disabled implicit animations during frame application.
- Snap guide padding alignment corrected for top/bottom padding.
- Tiling mode now skips manual snap sizing and immediately reflows.
- Layout warnings and deprecated API usage cleaned up (status item, transformers, graphics context).

### Security
- No changes.
