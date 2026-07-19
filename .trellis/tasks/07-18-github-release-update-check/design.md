# GitHub Release 自动检查更新 - Technical Design

## Architecture

The feature is split into three boundaries:

1. `AppUpdateService` owns GitHub transport, response decoding, tag parsing, version comparison, ETag handling, and cached fallback.
2. `AppUpdateCoordinator` owns automatic-check policy, process-level presentation deduplication, startup delay, and presentation routing.
3. UIKit settings/prompt controllers own user interaction and localization. They receive value models and do not parse GitHub payloads.

The GitHub repository and API URL are host constants. The installed version is always read from `Bundle.main` using `CFBundleShortVersionString` and `CFBundleVersion`.

## Release Contract

- Stable endpoint: `GET https://api.github.com/repos/moliango/dexoflux/releases/latest`.
- Required headers: `Accept: application/vnd.github+json`, `User-Agent: DexoFlux-iOS`, optional `If-None-Match`.
- Expected tag: `v{marketingVersion}-build.{buildNumber}`.
- Marketing versions are compared as arbitrary-length numeric components with missing components treated as zero.
- If marketing versions are equal, build numbers determine freshness.
- The preferred asset is named `dexoflux-unsigned.ipa`; absence does not invalidate the Release because the Release page remains usable.

## Cache And Failure Policy

- Persist the decoded latest Release, ETag, and fetch date in `UserDefaults` under versioned keys.
- Automatic checks may reuse a cache younger than one hour.
- Manual checks always issue a conditional network request.
- HTTP 304 refreshes cache time and returns the cached Release.
- HTTP 403/429 and transient network failures may use stale cached data if present.
- Automatic failures are silent. Manual failures produce a localized recoverable alert.
- Malformed tags are ignored as unsupported Releases rather than treated as updates.

## Automatic Check Lifecycle

- The primary `ForumContainerViewController` (`showsDismissButton == false`) asks the shared coordinator to schedule an automatic check after its first appearance.
- The coordinator executes at most once per process launch and delays briefly so startup data work can proceed without blocking.
- The primary container presents a pending result only after its startup overlay is removed, the scene is active, and no login, Cloudflare, composer, or other modal is already presented.
- `UIApplication.didBecomeActiveNotification` retries presentation of an already-fetched pending result without issuing another network request.
- The coordinator checks `AppSettings.autoCheckForUpdates`, then requests cached update data.
- A prompt appears only when the remote release is newer and no other modal is being presented. If the UI is busy, presentation is retried once when the scene is active rather than replacing an existing modal.

## UI

- Settings gains a final `About & Updates` category.
- The page shows app icon/name, installed version and build, an enabled-by-default automatic-check switch, a manual “Check for Updates” row, and a GitHub Releases row.
- Manual check states: checking, update available, latest version, and error.
- The update prompt is a native compact sheet/card showing current → remote version, release notes, asset size when present, “Update Now”, and “Later”.
- “Update Now” opens the Release `html_url` with `UIApplication.open`.

## Settings And Backup

- `AppSettings.autoCheckForUpdates` is a local user preference and participates in preferences export/import.
- Cache payload, ETag, last-check time, and last presented Release are operational state and are not included in preference backup.

## Compatibility

- iOS 15+ UIKit only.
- No authenticated GitHub API token is embedded.
- No app installation, signing, TestFlight, or App Store behavior is implied.
- Existing app startup, forum selection, login, and Cloudflare flows remain authoritative over update presentation.

## Tests

- Tag parsing and version/build comparison matrix.
- Release decoding and asset selection.
- ETag 304 and cache fallback behavior using injected URL loading.
- Automatic preference default and backup round-trip.
- Coordinator deduplication/presentation policy as pure state where possible.
