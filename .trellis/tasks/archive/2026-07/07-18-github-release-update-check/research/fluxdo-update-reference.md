# FluxDo Update Reference

## Files Reviewed

- `/Users/naine/Documents/AndroidWorkspace/fluxdo/lib/services/update_service.dart`
- `/Users/naine/Documents/AndroidWorkspace/fluxdo/lib/services/update_checker_helper.dart`
- `/Users/naine/Documents/AndroidWorkspace/fluxdo/lib/widgets/update_dialog.dart`
- `/Users/naine/Documents/AndroidWorkspace/fluxdo/lib/pages/about_page.dart`
- `/Users/naine/Documents/AndroidWorkspace/fluxdo/lib/main.dart`

## Reusable Product Behavior

- Query GitHub `releases/latest` with a stable User-Agent and GitHub JSON Accept header.
- Cache update results for one hour and store ETag for conditional requests.
- Use cached data after 304 and as a fallback for 403/429 rate limiting.
- Automatic checks are enabled by default, run during startup UI tasks, and fail silently.
- Manual checks bypass the normal cache and show loading, latest-version, update, or error UI.
- Update UI shows current/remote versions, release notes, “update now”, “details”, “later”, and an optional ignore action.
- Non-Android platforms open the Release page rather than attempting in-app installation.

## Behavior Not To Copy

- FluxDo parses tags by removing every `v` and splitting only on dots, then calls `int.parse`. This does not support DexoFlux tags such as `v1.2-build.7`.
- FluxDo's “do not remind” disables all automatic checks instead of ignoring one release. DexoFlux should make this a deliberate product decision.
- FluxDo's APK architecture selection, background APK download, notification channel, SHA sidecar, and installer flow are Android-specific.
- DexoFlux should not attempt to install an unsigned IPA from inside the app.

## DexoFlux Release Contract

- Source: `moliango/dexoflux` public GitHub repository.
- Tag: `v{marketingVersion}-build.{buildNumber}`.
- Current asset: `dexoflux-unsigned.ipa`.
- Compare marketing versions numerically by components, then compare build numbers when marketing versions are equal.
- Read the installed values from `CFBundleShortVersionString` and `CFBundleVersion`, not from hard-coded constants.
