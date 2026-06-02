# Flint — Accessibility

A long-form reading/writing tool lives or dies on accessibility. These are requirements, not nice-to-haves. Several map directly to Phase 1 tasks.

## Contrast

- Body and UI text meet **WCAG AA** (4.5:1 normal, 3:1 large/UI). Proofs are in [COLOR.md](./COLOR.md); re-verify any new pair.
- **The amber-on-light trap:** `#EF9F27` fails AA on white. Amber text/links in light mode must use `accent-text` (`spark.800`). Amber is fine for non-text fills/icons. (ADR-D02.)
- Never convey meaning by color alone — pair the amber spark with position, weight, or an icon (e.g. the selected-row amber bar is also the selected row).

## Dynamic Type

- **Native chrome uses iOS text styles** (`.body`, `.headline`, …) so it scales with the user's setting — don't hard-code chrome sizes. The numeric scale in [TYPOGRAPHY.md](./TYPOGRAPHY.md) is the default these resolve to.
- **The editor** respects a user base reading size; the reading scale is a default, not a ceiling. The CodeMirror side must scale from the same base so both engines grow together. **Never disable zoom** in the webview.
- Layouts reflow at large sizes — no clipping, no fixed-height text rows.

## Hit targets & input

- Minimum **44×44pt** for every interactive element, even when the glyph is smaller (icon buttons, tree disclosure, tag chips).
- ≥ 8pt spacing between adjacent targets.
- Don't rely on hover; the primary platform is touch + Pencil. Provide loading/saved feedback for actions (a quiet `text-muted` indicator, not a blocking spinner for local saves).

## VoiceOver

- Every control has a meaningful label; icon-only buttons get an accessibility label (never ship a nameless glyph button).
- Logical reading/focus order: navigation → content. The editor exposes its text to assistive tech (CodeMirror's accessibility must not be suppressed by theming).
- Ink: the canvas and its embed thumbnail carry labels (e.g. "Handwritten sketch, double-tap to edit"); the embed is reachable and actionable via VoiceOver.

## Motion

- Honor **Reduce Motion** (`UIAccessibility.isReduceMotionEnabled`) and `prefers-reduced-motion` in the webview. The thumbnail→canvas transition and panel slides degrade to a cross-fade or instant change.
- No motion that is purely decorative (§9), so there is little to disable in the first place.

## Color-scheme & contrast settings

- Respect system Dark/Light (dark-first, but the OS wins the choice).
- Respect **Increase Contrast** where feasible — provide higher-contrast border/text variants if the warm hairlines prove too subtle for some users.

## Checklist for any new surface

- [ ] Text pairs pass AA (verified, not assumed)
- [ ] Chrome uses Dynamic Type styles; layout reflows large
- [ ] All targets ≥ 44pt; labeled for VoiceOver
- [ ] Meaning never carried by color alone
- [ ] Motion respects Reduce Motion
- [ ] Native and webview render identical tokens (no seam mismatch)
