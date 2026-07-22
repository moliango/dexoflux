# Implementation notes

## NewAPICheckInViewController.swift (rewritten UI + auto-relogin)

- Table becomes two sections. Section 概览: `NewAPISummaryCell` (stats line
  "%d 个平台 · %d 已签到 · %d 待重新登录" + accent filled 全部签到 button with
  activity indicator) and the 自动重新登录 switch row (icon + subtitle). Section
  平台: redesigned `NewAPIPlatformCell` — 44pt gradient monogram tile (stable
  per-host palette), name + "host · relative time" meta, right column with
  monospaced-digit green balance + `NewAPIStatusPill` (dot capsule; expired is
  orange now, needs-action not failure). Running state = spinner over the tile.
  Empty state is a tappable row in the platforms card. 全部签到 moved from the
  nav bar into the summary card; nav keeps only +.
- Auto-relogin queue: after any single sign-in returning authenticationExpired
  (and toggle ON) the platform ID is enqueued; batch enqueues all expired after
  the summary alert's OK. `processReloginQueueIfIdle` pushes
  `NewAPICheckInLoginViewController(existingPlatform:)` (persistent WKWebView
  store usually still holds the site session → probe auto-captures fresh cookie
  and pops). `viewDidAppear` continues the flow: saved → retry that platform once
  with `allowAutoRelogin: false` (no loops), then next in queue; manual back-out
  (no save) clears the queue.

## NewAPICheckInRuntime.swift

- `static var autoReloginEnabled` (UserDefaults `plugin.newapi.auto_relogin`,
  default true).

## PluginDockViewController.swift

- Dock menu: 插件 caption header; rows switch from `.tinted()` wash to plain
  rows with pre-rendered gradient icon tiles (`PluginIconTile`), 15pt semibold
  title + 12pt secondary subtitle, tertiary-fill highlight; width 230→250.
- `PluginWindowContainerViewController` gains a real title bar (22pt tile icon +
  14pt semibold title, hairline separator, smaller 32pt tertiary-fill control
  buttons); content container double border removed; softer shadow. `makeWindow`
  passes per-plugin title/icon.
- `PluginIconTile` renders rounded gradient tiles (newAPI: teal→green
  checkmark.seal; ldcStore: LDStoreLogo asset or orange→pink box fallback).

## Verification

- Simulator build (no device, no tests): BUILD SUCCEEDED, zero errors.
- Device-side to confirm: auto-relogin webview flow against a real expired
  platform; dock/window visuals in light+dark.
