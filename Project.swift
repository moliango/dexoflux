import ProjectDescription

let developmentTeam = Environment.developmentTeam.getString(default: "")

let project = Project(
    name: "dexoflux",
    options: .options(
        defaultKnownRegions: ["en", "zh-Hans", "zh-Hant", "zh-HK"],
        developmentRegion: "en"
    ),
    packages: [
        .local(path: "Packages/CookedHTML"),
        .remote(
            url: "https://github.com/scinfu/SwiftSoup.git",
            requirement: .upToNextMajor(from: "2.7.0")
        ),
    ],
    settings: .settings(
        base: [
            "DEVELOPMENT_TEAM": .string(developmentTeam),
        ],
        configurations: [
            .debug(name: "Debug", settings: [:], xcconfig: nil),
            .release(name: "Release", settings: [:], xcconfig: nil),
        ]
    ),
    targets: [
        .target(
            name: "dexoflux",
            destinations: .iOS,
            product: .app,
            bundleId: "com.naine.dexoflux",
            deploymentTargets: .iOS("15.0"),
            infoPlist: .file(path: "dexo/Info.plist"),
            sources: [
                .glob("dexo/**", excluding: [
                    "dexo/Info.plist",
                    "dexo/Assets.xcassets/**",
                    "dexo/AppIcon.icon/**",
                ]),
            ],
            resources: .resources([
                .glob(pattern: "dexo/Assets.xcassets/**"),
                .glob(pattern: "dexo/Localizable.xcstrings"),
                .glob(pattern: "dexo/Core/aliases.json"),
                .glob(pattern: "dexo/Resources/Fonts/**"),
            ]),
            dependencies: [
                .external(name: "Alamofire"),
                .external(name: "GRDB"),
                .external(name: "SDWebImage"),
                .external(name: "SDWebImageSVGCoder"),
                .external(name: "Lightbox"),
                .package(product: "CookedHTML"),
                .package(product: "SwiftSoup"),
            ],
            settings: .settings(
                base: [
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES": "DexoFluxOrbit DexoFluxCards DexoFluxSignal",
                    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                    "CODE_SIGN_STYLE": "Automatic",
                    "CURRENT_PROJECT_VERSION": "1",
                    "GENERATE_INFOPLIST_FILE": "YES",
                    "INFOPLIST_KEY_CFBundleDisplayName": "DexoFlux",
                    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.utilities",
                    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
                    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
                    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown",
                    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
                    "OTHER_LDFLAGS": "$(inherited) -ObjC",
                    "MARKETING_VERSION": "1.4",
                    "PRODUCT_NAME": "dexoflux",
                    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
                    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
                    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
                    "SWIFT_EMIT_LOC_STRINGS": "YES",
                    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
                    "SWIFT_VERSION": "5.0",
                    "TARGETED_DEVICE_FAMILY": "1,2",
                ]
            )
        ),
        .target(
            name: "dexofluxTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.naine.dexofluxTests",
            deploymentTargets: .iOS("15.0"),
            infoPlist: .default,
            sources: ["dexofluxTests/**"],
            dependencies: [
                .target(name: "dexoflux"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "dexofluxTests",
            shared: true,
            buildAction: .buildAction(targets: ["dexoflux", "dexofluxTests"]),
            testAction: .targets(["dexofluxTests"])
        ),
    ]
)
