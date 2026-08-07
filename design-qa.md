# Fake EditView Design QA

- Source visual truth: `/var/folders/kc/s80tpmys019_347h5whyxx2w0000gn/T/codex-clipboard-d2b4ba06-7ac4-40cd-892a-9f46e0f7a7c9.png`
- Implementation screenshot: `/var/folders/kc/s80tpmys019_347h5whyxx2w0000gn/T/com.openai.sky.CUAService/Seal Note Screenshot 2026-08-07 at 7.57.42 AM.jpeg`
- Combined comparison: `/tmp/sealnote-fake-edit-comparison.png`
- Source pixels: 1048 × 650; the formal EditView reference occupies the right-hand 482 × 638 window.
- Implementation pixels / viewport: 468 × 520 at native macOS capture density.
- Normalization: compared the top 520 px of the formal EditView reference against the full 468 × 520 implementation capture. The 14 px width difference is an intentional responsive-window difference; the implementation uses Seal Note's production default sticky-note width.
- State: empty, editable plain-text note with the window focused. The source window controls are inactive while the implementation capture is active; this is an expected system focus-state difference.

## Full-view comparison evidence

- The editor fills the window and samples the same transparent unified titlebar background.
- The placeholder begins at the same visual inset: approximately 20 pt from the leading edge and 60 pt below the window top.
- Preview, lock, copy, more, and pin controls use the same SF Symbols, grouping, control sizes, and native Glass treatments as the production editor.
- The close control, corner radius, white editor background, and toolbar alignment follow the same native window configuration.

## Focused-region comparison evidence

The titlebar/editor boundary was inspected separately because it contained the original mismatch. The revised view uses the production `MacTextView`, which provides the same measured titlebar inset, text-container inset, placeholder typography, line height, and background sampling. No additional focused region was needed because the remaining body is an empty, uniform editor surface without assets.

## Required fidelity surfaces

- Fonts and typography: passed. The implementation uses the production editor font and paragraph metrics instead of a standalone `TextEditor` font.
- Spacing and layout rhythm: passed. Leading and top content insets match; all toolbar controls remain visible at the production default width.
- Colors and visual tokens: passed. The implementation uses native text/background colors and the existing Glass styles. The red/gray close-button difference is only active-window state.
- Image quality and asset fidelity: passed. There are no raster assets; all controls use the same system SF Symbols as the production editor.
- Copy and content: passed. The empty-state placeholder is `随便写点什么吧`, matching the production editor.

## Findings

No actionable P0, P1, or P2 differences remain.

## Comparison history

1. Earlier P1: the fake editor used `TextEditor`, placing text at the top-left edge and omitting the production titlebar inset and placeholder. Fixed by using `MacTextView` with production font and line-height defaults. Post-fix capture shows matching leading and top offsets.
2. Earlier P1: the lock control was missing. Fixed by restoring the lock button with the production symbol and toolbar placement. Post-fix capture shows all five toolbar controls.
3. Earlier P2: a 420 pt default width caused toolbar overflow/reordering once the lock control was restored. Fixed by using `MacNoteWindowStore.defaultWindowSize.width` (468 pt). Post-fix capture shows the full toolbar without overflow.

## Interaction checks

- Editable text area is exposed as a native text entry control.
- Preview button responds.
- More menu opens and exposes rename, fit, search, encrypt, and trash actions.
- Test actions remain print-only and do not mutate vault data.

## Follow-up polish

No P3 follow-up is required for the requested visual shell.

final result: passed
