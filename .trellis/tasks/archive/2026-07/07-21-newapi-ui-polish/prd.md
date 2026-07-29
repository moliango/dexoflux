# NewAPI check-in redesign and plugin chrome polish

## Goal

1. Redesign the NewAPI check-in page (NewAPICheckInViewController) with the app's
   card aesthetic: summary header card (stats + prominent 全部签到 button +
   auto-relogin switch), cleaner platform cells (gradient monogram tile, host +
   relative time, prominent balance, colored status pill), nicer empty state.
2. New feature toggle 自动重新登录 (default ON, UserDefaults-backed via
   NewAPICheckInRuntime): when a sign-in attempt (single or batch) ends in
   authenticationExpired, automatically push NewAPICheckInLoginViewController for
   that platform (existingPlatform mode, persistent WKWebsiteDataStore usually
   still holds the site session so the probe re-captures a fresh cookie within
   seconds and pops back), then re-run that platform's sign-in. Batch produces a
   sequential queue; a manual back-out (pop without save) cancels the rest.
3. Beautify the plugin dock menu (PluginDockViewController.makeMenuButton):
   pre-rendered gradient icon tiles + title/subtitle rows instead of the tinted
   wash buttons.
4. Beautify the plugin window chrome (PluginWindowContainerViewController):
   proper title bar with plugin icon + name, minimize/close kept, remove the
   double border, hairline under the bar.

## Non-goals

- No changes to NewAPICheckInService request/classification logic.
- No redesign of the detail/history pages or PluginCenterViewController.
- No background scheduling changes.

## Acceptance

- [ ] Check-in page shows summary card with working 全部签到 + switch.
- [ ] Expired platform triggers auto web relogin then re-sign-in when toggle ON.
- [ ] Dock menu rows and plugin window title bar match the new style.
- [ ] Simulator build succeeds (make generate not needed unless files added).
