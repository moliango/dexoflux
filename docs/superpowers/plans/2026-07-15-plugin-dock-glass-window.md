# Plugin Dock Glass Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved glass-card visual direction to the plugin Dock handle and cached plugin windows.

**Architecture:** Keep the existing controller hierarchy and interaction state. Limit the change to view construction, semantic styling, icon metadata, accessibility, and presentation animation in the existing Dock file.

**Tech Stack:** UIKit, Auto Layout, `UIVisualEffectView`, semantic `UIColor`, SF Symbols, XCTest build validation.

---

### Task 1: Restyle Dock Handle And Menu

**Files:**
- Modify: `dexo/Features/Plugins/PluginDockViewController.swift`

- [ ] Replace the opaque rectangular handle with an ultra-thin-material container and compact circular visual core.
- [ ] Update left/right constraints and transforms so the shortcut remains partially attached to the selected edge.
- [ ] Align the menu material, corner radius, border, and shadow with the approved glass direction.
- [ ] Preserve the existing 44-point minimum interaction area and drag gesture.

### Task 2: Restyle Plugin Workspace Window

**Files:**
- Modify: `dexo/Features/Plugins/PluginDockViewController.swift`
- Modify: `dexo/Localizable.xcstrings`

- [ ] Pass each plugin icon into `PluginWindowContainerViewController`.
- [ ] Replace the flat header with a glass header containing icon, title, workspace subtitle, minimize, and close controls.
- [ ] Place plugin content inside a rounded semantic-color container with visible outer margins.
- [ ] Add localized workspace and accessibility strings in all supported languages.
- [ ] Use spring presentation when Reduce Motion is disabled and fade-only presentation otherwise.

### Task 3: Verify

**Files:**
- Verify: `dexo/Features/Plugins/PluginDockViewController.swift`
- Verify: `dexo/Localizable.xcstrings`

- [ ] Run `jq empty dexo/Localizable.xcstrings` and expect exit code 0.
- [ ] Run `git diff --check` and expect no whitespace errors.
- [ ] Run the generic iOS Simulator `xcodebuild` with signing disabled and expect exit code 0.
