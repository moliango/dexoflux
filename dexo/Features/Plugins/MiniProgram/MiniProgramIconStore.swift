import UIKit

final class MiniProgramIconStore {
    static let shared = MiniProgramIconStore()

    private let baseDirectory: URL
    private let fileManager: FileManager

    init(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.baseDirectory = appSupport ?? fileManager.temporaryDirectory
        }
    }

    func saveIconData(_ data: Data, programID: String) throws -> String {
        let directory = baseDirectory.appendingPathComponent("MiniProgramIcons", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = sanitizedFileName(programID) + ".png"
        let fileURL = directory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        return "MiniProgramIcons/\(fileName)"
    }

    func image(relativePath: String) -> UIImage? {
        let url = baseDirectory.appendingPathComponent(relativePath)
        return UIImage(contentsOfFile: url.path)
    }

    /// Raw file bytes for export packages. Returns nil when the logo file is missing.
    func data(relativePath: String) -> Data? {
        let url = baseDirectory.appendingPathComponent(relativePath)
        return try? Data(contentsOf: url)
    }

    private func sanitizedFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-")).isEmpty
            ? UUID().uuidString.lowercased()
            : String(scalars)
    }
}
