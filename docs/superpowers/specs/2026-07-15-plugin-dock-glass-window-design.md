# Plugin Dock Glass Window Design

## Goal

Replace the visually heavy plugin Dock handle and window chrome with a compact glass-card treatment that matches DexoFlux while preserving all current plugin behavior.

## Visual Direction

- Use the approved B direction: a partially edge-attached circular shortcut and a floating glass workspace card.
- The shortcut uses the active theme accent, an ultra-thin material surface, a restrained border, and a soft directional shadow.
- The window keeps visible margins around every edge and uses a continuous 28-point corner radius.
- The header presents the plugin icon, title, localized workspace subtitle, and two quiet circular controls.
- Plugin content sits inside a separate rounded container so web and native pages do not visually merge into the window chrome.
- Semantic colors and system materials provide intentional light and dark appearances.

## Interaction

- Existing tap, drag, edge-pan, minimize, restore, and close behavior remains unchanged.
- Opening and restoring use a short spring-like scale and fade transition.
- Reduce Motion removes decorative scale animation.
- Icon controls retain at least a 44-point hit target and receive accessibility labels.

## Scope

- Modify only `PluginDockViewController.swift` and required localization entries.
- Do not change plugin state, browser state, tab registration, or window caching behavior.

## Acceptance Criteria

- Dock handle looks lightweight on both sides and reflects the selected theme accent.
- Plugin windows no longer look full-screen or use a flat utility-bar header.
- NewAPI and LD Store display their own icon in the window header.
- Light mode, dark mode, Dynamic Type, VoiceOver, and Reduce Motion remain usable.
- The app builds for the generic iOS Simulator destination.
