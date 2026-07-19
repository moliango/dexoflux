# GitHub Release 自动检查更新 - Implementation Plan

## 1. Core Models And Versioning

- Add version/build and GitHub Release value models.
- Add strict DexoFlux tag parsing with graceful rejection of unsupported tags.
- Add numeric marketing-version and build comparison.
- Add unit tests for older/equal/newer marketing and build combinations.

## 2. GitHub Release Service

- Add an injected `URLSession`-based service for `/releases/latest`.
- Decode Release Notes, `html_url`, ETag, published date, and IPA asset metadata.
- Add one-hour cache, conditional request, 304 handling, and stale fallback for 403/429/transient failures.
- Ensure automatic mode can use fresh cache while manual mode performs a conditional request.

## 3. Preference And Backup

- Add enabled-by-default `AppSettings.autoCheckForUpdates`.
- Export/import the preference through `PreferencesBackupPayload`.
- Add default, notification, and backup round-trip tests.

## 4. Settings UI

- Add an `About & Updates` category to the Settings root.
- Add a native updates page with installed version/build, automatic-check switch, manual check, and GitHub Releases link.
- Show latest/update/error outcomes without blocking navigation.
- Add four-language localization and accessibility labels.

## 5. Update Prompt And Startup Coordination

- Add a native update prompt with version transition, release notes, asset size, Update Now, and Later.
- Add a process-level coordinator that schedules once after scene activation and respects existing presented controllers.
- Wire `SceneDelegate.sceneDidBecomeActive` without delaying window/root creation.
- Open Release pages externally through `UIApplication.open`.

## 6. Verification

- Run focused update/version/cache tests.
- Run localization JSON validation and coverage checks.
- Run `git diff --check`.
- Generate the Tuist project if new test files are added.
- Build the generic iOS Simulator target with signing disabled.

## Risk And Rollback

- Risk: startup modal conflicts with login/Cloudflare/update overlays. Roll back by disabling the SceneDelegate coordinator call; manual Settings check remains usable.
- Risk: GitHub API rate limiting. ETag and stale cache prevent repeated failures; no token is shipped.
- Risk: tag format drift. Unsupported tags fail closed and surface only in manual-check diagnostics.
