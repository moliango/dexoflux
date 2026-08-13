# Build & Dependency Integration (Tuist)

> Executable conventions for building this app and wiring dependencies.
> Learned from real failures on 2026-07-21 (SwiftSoup integration, new-file
> compile errors).

---

## Convention: Regenerate the project after adding/removing source files

**What**: Run `make generate` whenever a Swift file is created or deleted —
not only after editing `Project.swift`. Entitlements files and extra `sources`
entries also require regeneration.

**Why**: Target sources use `.glob("Doer/**")` which Tuist resolves **at
generation time**. A file created after the last generation is not part of the
`.xcodeproj`, so the build fails with `cannot find 'NewType' in scope` even
though the file exists on disk.

**Symptom → Fix matrix**:

| Symptom | Cause | Fix |
|---------|-------|-----|
| `error: cannot find 'X' in scope` for a type that exists in a new file | file not in generated project | `make generate`, rebuild |
| Build settings/deps changes not picked up | stale project | `make generate` |

---

## Convention: Add packages that CookedHTML already depends on via SPM, never `.external`

**What**: To expose a package to the app target when the local
`Packages/CookedHTML` already pulls it transitively (e.g. SwiftSoup), declare
it in `Project.swift` `packages:` as `.remote(...)` with the **identical URL**
CookedHTML uses, and depend via `.package(product:)`.

```swift
// Correct (Project.swift)
packages: [
    .local(path: "Packages/CookedHTML"),
    .remote(
        url: "https://github.com/scinfu/SwiftSoup.git",   // must match CookedHTML/Package.swift exactly
        requirement: .upToNextMajor(from: "2.7.0")
    ),
],
// target deps
.package(product: "SwiftSoup"),
```

```swift
// Wrong — duplicates the package
.external(name: "SwiftSoup"),
```

**Why**: `.external` builds a second SwiftSoup target through Tuist's
Dependencies project while workspace SPM builds another for CookedHTML. Two
same-named targets write the same DerivedData outputs → Xcode fails with
`Multiple commands produce '...SwiftSoup.build/.../*.stringsdata'`. Same-URL
SPM references are deduplicated into one package instance.

**Validation**: after `make generate`, `grep SwiftSoup dexoflux.xcodeproj/project.pbxproj`
must show one `XCRemoteSwiftPackageReference` and no Tuist-external SwiftSoup
target.

---

## Convention: Verification is compile-only (no simulator launch)

**What**: After changes, verify with a **build only** — do not boot or launch
the Simulator, do not install/run the app, do not run the test suite unless
explicitly asked.

```bash
# only when files were added/removed (or Project.swift changed)
make generate

# Compile only. Prefer generic destination so xcodebuild does not boot a
# specific simulator runtime.
xcodebuild build -workspace dexoflux.xcworkspace -scheme dexoflux \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

**Why**: The owner iterates on-device / in Xcode manually. Booting Simulator or
running `xcodebuild test` is slow, flaky (device UUID / connection errors), and
unnecessary for catching compile/scope errors.

**Don't** (unless the user explicitly asks):

- `xcodebuild test` / boot Simulator / `open -a Simulator`
- `-destination 'platform=iOS Simulator,name=…'` or `id=…` when a generic
  destination works (named destinations may force a runtime boot)
- deploy to a physical device or launch the app
- run the full test suite

`swiftc -parse` alone is still NOT sufficient — it misses scope/type errors and
the new-file-not-in-project failure above. Use `xcodebuild build`.

---

## Convention: Tuist `resources` before `entitlements`

**What**: `Project.swift` `Target.target(...)` labeled arguments must follow
the ProjectDescription parameter order. `resources:` must appear before
`entitlements:`.

**Why**: Tuist dumps `Project.swift` with `-suppress-warnings` and Swift
enforces this order. Putting entitlements above resources fails generate:

`argument 'resources' must precede argument 'entitlements'`

```swift
// Correct
sources: [...],
resources: .resources([...]),
entitlements: .file(path: "Doer/Doer.entitlements"),
dependencies: [...],
```

---

## Convention: Share Codable snapshots with WidgetKit via App Group

**What**: Compile `Shared/TrustLevelWidgetSnapshot.swift` into both `Doer` and
`DoerWidget`. Do not import app models into the widget. See
[App Extensions](./app-extensions.md).

**Why**: WidgetKit cannot link the app target. A tiny Codable snapshot plus
`group.com.naine.doer` is the boundary.
