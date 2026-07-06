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

(To be filled by the team)
