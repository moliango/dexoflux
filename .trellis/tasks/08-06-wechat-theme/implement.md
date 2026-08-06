# WeChat Style Theme — Implementation Plan

## Decision
**B**: colors + chrome quality (locked 2026-08-06).

## Steps
1. [x] Add `ThemeStyle.weChat = 4` + localized title
2. [x] Exhaustive color/token switches + `prefersOpaqueChrome` / `chromeCornerRadius` / `chromeBackgroundColor`
3. [x] `applyAppearance` opaque navigation chrome for WeChat
4. [x] `ForumTabBarController.configureTabBarSurface` WeChat chrome gray
5. [x] Appearance preview swatches
6. [ ] Simulator visual QA light/dark
7. [ ] Commit

## Files
- `dexo/Core/Settings/AppSettings+Appearance.swift`
- `dexo/Features/ForumDetail/ForumTabBarController.swift`
- `dexo/Features/Settings/AppearanceSettingsViewController.swift`
