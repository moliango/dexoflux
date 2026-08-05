import Foundation
import SDWebImage

/// Ensures standard sandboxed directories exist *as directories* before any
/// disk cache / database / WebKit code runs.
///
/// The classic failure mode is:
/// `NSCocoaErrorDomain Code=512 "The file “Caches” couldn’t be saved in the folder “Library”."`
/// with underlying `NSPOSIXErrorDomain Code=20 (ENOTDIR)` — a path component that
/// should be a folder is a regular file (or missing parents after a partial wipe).
enum AppStorageBootstrap {
    /// Call once at process start, before `SDImageCache.shared` or GRDB open.
    static func prepareAtLaunch() {
        repairHomeLibraryTreeIfNeeded()
        _ = cachesDirectoryURL()
        _ = applicationSupportDirectoryURL()
        _ = documentsDirectoryURL()
        pinSDWebImageDiskCacheRoot()
    }

    /// Sandboxed Caches root (`…/Library/Caches`). Creates / repairs as needed.
    static func cachesDirectoryURL() -> URL {
        ensuredSearchPathDirectory(.cachesDirectory, fallbackName: "Caches")
    }

    /// Sandboxed Application Support root.
    static func applicationSupportDirectoryURL() -> URL {
        ensuredSearchPathDirectory(.applicationSupportDirectory, fallbackName: "Application Support")
    }

    static func documentsDirectoryURL() -> URL {
        ensuredSearchPathDirectory(.documentDirectory, fallbackName: "Documents")
    }

    // MARK: - Private

    /// If `NSHomeDirectory()/Library` (or `…/Library/Caches`) exists as a *file*,
    /// remove it and recreate as a directory so subsequent system creates succeed.
    private static func repairHomeLibraryTreeIfNeeded() {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let library = home.appendingPathComponent("Library", isDirectory: true)
        ensureIsDirectory(library, fileManager: fm)

        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        ensureIsDirectory(caches, fileManager: fm)

        let appSupport = library.appendingPathComponent("Application Support", isDirectory: true)
        ensureIsDirectory(appSupport, fileManager: fm)
    }

    private static func ensuredSearchPathDirectory(
        _ directory: FileManager.SearchPathDirectory,
        fallbackName: String
    ) -> URL {
        let fm = FileManager.default
        do {
            let url = try fm.url(
                for: directory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            ensureIsDirectory(url, fileManager: fm)
            return url
        } catch {
            // Fall back to an explicit path under NSHomeDirectory and force-create.
            #if DEBUG
            print("[AppStorage] url(for: \(directory)) failed: \(error). Falling back under home.")
            #endif
            let fallback = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent(fallbackName, isDirectory: true)
            ensureIsDirectory(
                URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                    .appendingPathComponent("Library", isDirectory: true),
                fileManager: fm
            )
            ensureIsDirectory(fallback, fileManager: fm)
            return fallback
        }
    }

    /// If `url` is a file, delete it; always end with a real directory.
    @discardableResult
    private static func ensureIsDirectory(_ url: URL, fileManager fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                return true
            }
            // ENOTDIR root cause: a regular file occupies the directory path.
            do {
                try fm.removeItem(at: url)
            } catch {
                #if DEBUG
                print("[AppStorage] failed to remove non-directory at \(url.path): \(error)")
                #endif
                return false
            }
        }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            #if DEBUG
            print("[AppStorage] createDirectory failed at \(url.path): \(error)")
            #endif
            return false
        }
    }

    /// Must run before the first `SDImageCache.shared` touch so the singleton
    /// picks up a verified disk root instead of a broken intermediate path.
    private static func pinSDWebImageDiskCacheRoot() {
        let root = cachesDirectoryURL()
            .appendingPathComponent("com.hackemist.SDImageCache", isDirectory: true)
        ensureIsDirectory(root, fileManager: .default)
        SDImageCache.defaultDiskCacheDirectory = root.path
    }
}
