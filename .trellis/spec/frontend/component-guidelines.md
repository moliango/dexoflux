# Component Guidelines

> How components are built in this project.

---

## Overview

<!--
Document your project's component conventions here.

Questions to answer:
- What component patterns do you use?
- How are props defined?
- How do you handle composition?
- What accessibility standards apply?
-->

(To be filled by the team)

---

## Component Structure

<!-- Standard structure of a component file -->

### Topic Detail Timeline

- `TopicDetail` progress and timeline controls must use Discourse `post_stream.stream` as the source of truth for ordering.
- Displayed progress is the 1-based stream index over `stream.count`, matching FluxDo's `TopicProgress` behavior.
- Timeline selection should return the selected post id from `stream`; the view controller may map that id back to the existing native floor-jump loader.
- Do not derive timeline position from visible table rows, loaded batch size, or filtered post arrays except as a temporary fallback for finding the current visible stream index.
- The progress entry should remain a compact centered capsule (`current / total`) that opens the timeline on tap and keeps gesture actions attached to the same control.

---

## Props Conventions

<!-- How props should be defined and typed -->

(To be filled by the team)

---

## Styling Patterns

<!-- How styles are applied (CSS modules, styled-components, Tailwind, etc.) -->

(To be filled by the team)

---

## Accessibility

<!-- A11y requirements and patterns -->

(To be filled by the team)

---

## Common Mistakes

<!-- Component-related mistakes your team has made -->

### UIKit Card Controls

- Purely decorative subviews inside a tappable `UIControl` card must set `isUserInteractionEnabled = false`.
- Custom preview `UIView`s are especially easy to miss because they participate in hit-testing by default and can swallow taps before the parent control receives `.touchUpInside`.
- Apply this to visual-only preview layers, icon/title stacks, overlays, and selection badges unless those subviews intentionally handle their own gestures.
- Appearance settings app-icon and font option cards should be real controls backed by `AppSettings`, not static previews. If an option requires a system capability or imported resource, the tap path must either perform the action or show a localized error.
- Any subview constrained manually inside UIKit setting cards must set `translatesAutoresizingMaskIntoConstraints = false`. Missing this on labels or preview views can make arranged card content collapse or render off-screen inside `UIStackView`.

### Home Dynamic Header And Card Grid

- Home table geometry must be owned by a single inset update path that accounts for header height, incoming-topic banner space, bottom tab chrome, and the active card layout.
- Refresh actions that intentionally return Home to the top must first reveal the collapsed search/header row, then recompute table insets, then set `contentOffset` to `-tableView.contentInset.top`.
- Xiaohongshu two-column card layout needs a larger top content spacing than the standard list so the first grid row does not visually tuck under the filter chip row after refresh or header collapse changes.
- Theme changes that switch between standard list and Xiaohongshu grid must call the snapshot rebuild path and recompute table insets; `tableView.reloadData()` alone is not enough.
