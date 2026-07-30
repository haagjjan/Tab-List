@preconcurrency import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

@MainActor
public protocol AppIconProviding: AnyObject {
    func icon(
        for bundleIdentifier: String?,
        bundleURL: URL?,
        targetSize: CGFloat
    ) async -> NSImage
}

/// A small memory cache backed by normalized PNG files. The cache key includes
/// the bundle's version and modification date, so application updates naturally
/// invalidate stale icons without a filesystem watcher.
@MainActor
public final class AppIconCache: AppIconProviding {
    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheDirectory: URL
    private var placeholderIcons: [Int: NSImage] = [:]

    public init(fileManager: FileManager = .default) {
        let root = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        cacheDirectory = root
            .appendingPathComponent(
                "com.haagjjan.TabList",
                isDirectory: true
            )
            .appendingPathComponent("AppIcons", isDirectory: true)
        memoryCache.countLimit = 128
    }

    public func icon(
        for bundleIdentifier: String?,
        bundleURL: URL?,
        targetSize: CGFloat = 128
    ) async -> NSImage {
        let normalizedSize = max(16, min(targetSize.rounded(.up), 512))
        let key = fingerprint(
            bundleIdentifier: bundleIdentifier,
            bundleURL: bundleURL,
            targetSize: normalizedSize
        )
        let cacheKey = key as NSString

        if let cached = cachedIcon(
            for: bundleIdentifier,
            bundleURL: bundleURL,
            targetSize: normalizedSize
        ) {
            return cached
        }

        let diskURL = cacheDirectory
            .appendingPathComponent(key)
            .appendingPathExtension("png")
        if let data = try? await readData(at: diskURL),
           let cached = NSImage(data: data) {
            memoryCache.setObject(cached, forKey: cacheKey)
            return cached
        }

        let source: NSImage
        if let bundleURL {
            source = NSWorkspace.shared.icon(forFile: bundleURL.path)
        } else {
            source = NSWorkspace.shared.icon(for: .application)
        }
        let rendered = normalizedImage(source, size: normalizedSize)
        memoryCache.setObject(rendered, forKey: cacheKey)

        if let png = pngData(for: rendered) {
            let directory = cacheDirectory
            Task.detached(priority: .utility) {
                let fileManager = FileManager()
                try? fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try? png.write(to: diskURL, options: [.atomic])
            }
        }
        return rendered
    }

    public func cachedIcon(
        for bundleIdentifier: String?,
        bundleURL: URL?,
        targetSize: CGFloat
    ) -> NSImage? {
        let normalizedSize = max(16, min(targetSize.rounded(.up), 512))
        let key = fingerprint(
            bundleIdentifier: bundleIdentifier,
            bundleURL: bundleURL,
            targetSize: normalizedSize
        )
        return memoryCache.object(forKey: key as NSString)
    }

    public func placeholderIcon(targetSize: CGFloat) -> NSImage {
        let normalizedSize = max(16, min(targetSize.rounded(.up), 512))
        let cacheKey = Int(normalizedSize)
        if let cached = placeholderIcons[cacheKey] {
            return cached
        }
        let generic = NSWorkspace.shared.icon(for: .application)
        let rendered = normalizedImage(generic, size: normalizedSize)
        placeholderIcons[cacheKey] = rendered
        return rendered
    }

    public func purgeMemory() {
        memoryCache.removeAllObjects()
        placeholderIcons.removeAll(keepingCapacity: false)
    }

    public func removePersistentCache() async throws {
        purgeMemory()
        let directory = cacheDirectory
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager()
            guard fileManager.fileExists(atPath: directory.path) else { return }
            try fileManager.removeItem(at: directory)
        }.value
    }

    private func fingerprint(
        bundleIdentifier: String?,
        bundleURL: URL?,
        targetSize: CGFloat
    ) -> String {
        let bundle = bundleURL.flatMap(Bundle.init(url:))
        let version = bundle?.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "unknown"
        let modificationDate = try? bundleURL?
            .resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate?
            .timeIntervalSince1970
        let fingerprintParts: [String] = [
            bundleIdentifier ?? "",
            bundleURL?.standardizedFileURL.path ?? "",
            version,
            modificationDate.map { String($0) } ?? "",
            String(format: "%.0f", targetSize),
        ]
        let components = fingerprintParts.joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(components.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func normalizedImage(_ image: NSImage, size: CGFloat) -> NSImage {
        let outputSize = NSSize(width: size, height: size)
        let output = NSImage(size: outputSize)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: outputSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        output.unlockFocus()
        output.size = outputSize
        return output
    }

    private func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return representation.representation(using: .png, properties: [:])
    }

    nonisolated private func readData(at url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
    }
}
