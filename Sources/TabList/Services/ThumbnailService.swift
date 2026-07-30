@preconcurrency import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit
import TabListCore

public protocol ThumbnailProviding: Sendable {
    func cachedThumbnail(for window: WindowRecord) async -> CGImage?
    func refresh(
        _ windows: [WindowRecord],
        priority: [WindowKey],
        targetSize: CGSize
    ) async
    func cancelPending() async
    func purge() async
}

private final class ThumbnailImageBox: @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

private struct ThumbnailCacheEntry: Sendable {
    let image: ThumbnailImageBox
    let cost: Int
    var lastAccess: UInt64
}

private struct ThumbnailIdentity: Hashable, Sendable {
    let key: WindowKey
    let incarnation: UInt64

    init(_ window: WindowRecord) {
        key = window.id
        incarnation = window.incarnation
    }
}

private struct ThumbnailCaptureFlight: Sendable {
    let token: UUID
    let task: Task<ThumbnailImageBox?, Never>
}

private final class ShareableWindowBox: @unchecked Sendable {
    let window: SCWindow

    init(_ window: SCWindow) {
        self.window = window
    }
}

/// A process-wide permit pool for actual ScreenCaptureKit calls. Refresh actor
/// reentrancy can never raise capture concurrency above this limit.
private actor ThumbnailCaptureLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func run(
        _ operation: @escaping @Sendable () async -> ThumbnailImageBox?
    ) async -> ThumbnailImageBox? {
        await acquire()
        defer { release() }
        guard !Task.isCancelled else { return nil }
        return await operation()
    }

    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// ScreenCaptureKit-backed, memory-only window previews. It is intentionally
/// lazy: constructing this service does not query shareable content or request
/// Screen Recording.
public actor ThumbnailService: ThumbnailProviding {
    public static let maximumMemoryCost = 128 * 1_024 * 1_024
    public static let maximumCount = 120
    public static let maximumConcurrentCaptures = 3

    private var cache: [ThumbnailIdentity: ThumbnailCacheEntry] = [:]
    private var cacheCost = 0
    private var cacheAccessSequence: UInt64 = 0
    private var requestGeneration: UInt64 = 0
    private var inFlight: [ThumbnailIdentity: ThumbnailCaptureFlight] = [:]
    private let captureLimiter = ThumbnailCaptureLimiter(
        limit: maximumConcurrentCaptures
    )

    public init() {}

    public func cachedThumbnail(for window: WindowRecord) -> CGImage? {
        let identity = ThumbnailIdentity(window)
        guard var entry = cache[identity] else { return nil }
        cacheAccessSequence &+= 1
        entry.lastAccess = cacheAccessSequence
        cache[identity] = entry
        return entry.image.image
    }

    public func refresh(
        _ windows: [WindowRecord],
        priority: [WindowKey],
        targetSize: CGSize = CGSize(width: 640, height: 400)
    ) async {
        guard CGPreflightScreenCaptureAccess(), !windows.isEmpty else {
            return
        }

        let generation = requestGeneration
        let windowsByKey = windows.reduce(
            into: [WindowKey: WindowRecord]()
        ) { result, window in
            result[window.id] = window
        }
        let ordered = unique(priority + windows.map(\.id))
            .compactMap { windowsByKey[$0] }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            return
        }
        guard generation == requestGeneration, !Task.isCancelled else {
            return
        }

        let requestedIDs = Set(ordered.map(\.id.windowID))
        let windowsByID = content.windows.reduce(
            into: [CGWindowID: ShareableWindowBox]()
        ) { result, window in
            if requestedIDs.contains(window.windowID) {
                result[window.windowID] = ShareableWindowBox(window)
            }
        }

        var scheduled: [
            (
                identity: ThumbnailIdentity,
                flight: ThumbnailCaptureFlight
            )
        ] = []
        scheduled.reserveCapacity(ordered.count)

        for record in ordered {
            let identity = ThumbnailIdentity(record)
            if let existing = inFlight[identity] {
                scheduled.append((identity, existing))
                continue
            }
            guard let window = windowsByID[record.id.windowID] else {
                continue
            }

            let token = UUID()
            let limiter = captureLimiter
            let task = Task.detached(priority: .userInitiated) {
                await limiter.run {
                    guard !Task.isCancelled,
                          let image = await Self.capture(
                              window: window,
                              targetSize: targetSize
                          ) else {
                        return nil
                    }
                    return ThumbnailImageBox(image)
                }
            }
            let flight = ThumbnailCaptureFlight(
                token: token,
                task: task
            )
            inFlight[identity] = flight
            scheduled.append((identity, flight))
        }

        for scheduledCapture in scheduled {
            let image = await scheduledCapture.flight.task.value
            if inFlight[scheduledCapture.identity]?.token
                == scheduledCapture.flight.token {
                inFlight[scheduledCapture.identity] = nil
            }
            guard generation == requestGeneration,
                  !Task.isCancelled,
                  let image else {
                continue
            }
            let (cost, overflow) = image.image.bytesPerRow
                .multipliedReportingOverflow(by: image.image.height)
            guard !overflow else { continue }
            store(
                image.image,
                for: scheduledCapture.identity,
                cost: cost
            )
        }
    }

    public func cancelPending() async {
        requestGeneration &+= 1
        let flights = Array(inFlight)
        for (_, flight) in flights {
            flight.task.cancel()
        }
        for (identity, flight) in flights {
            _ = await flight.task.value
            if inFlight[identity]?.token == flight.token {
                inFlight[identity] = nil
            }
        }
    }

    public func purge() async {
        cache.removeAll(keepingCapacity: false)
        cacheCost = 0
        await cancelPending()
    }

    private static func capture(
        window: ShareableWindowBox,
        targetSize: CGSize
    ) async -> CGImage? {
        let frame = window.window.frame
        let requestedWidth = max(1, targetSize.width)
        let requestedHeight = max(1, targetSize.height)
        let sourceAspect = max(frame.width, 1) / max(frame.height, 1)
        let targetAspect = requestedWidth / requestedHeight

        let outputSize: CGSize
        if sourceAspect > targetAspect {
            outputSize = CGSize(
                width: requestedWidth,
                height: requestedWidth / sourceAspect
            )
        } else {
            outputSize = CGSize(
                width: requestedHeight * sourceAspect,
                height: requestedHeight
            )
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(max(1, outputSize.width.rounded(.up)))
        configuration.height = Int(max(1, outputSize.height.rounded(.up)))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = false

        let filter = SCContentFilter(
            desktopIndependentWindow: window.window
        )
        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private func unique(_ keys: [WindowKey]) -> [WindowKey] {
        var seen: Set<WindowKey> = []
        return keys.filter { seen.insert($0).inserted }
    }

    private func store(
        _ image: CGImage,
        for identity: ThumbnailIdentity,
        cost: Int
    ) {
        guard cost > 0, cost <= Self.maximumMemoryCost else {
            return
        }

        if let previous = cache.removeValue(forKey: identity) {
            cacheCost -= previous.cost
        }
        while !cache.isEmpty,
              cache.count >= Self.maximumCount
                || cacheCost + cost > Self.maximumMemoryCost {
            guard let oldestKey = cache.min(
                by: { $0.value.lastAccess < $1.value.lastAccess }
            )?.key,
                  let removed = cache.removeValue(forKey: oldestKey)
            else {
                break
            }
            cacheCost -= removed.cost
        }

        cacheAccessSequence &+= 1
        cache[identity] = ThumbnailCacheEntry(
            image: ThumbnailImageBox(image),
            cost: cost,
            lastAccess: cacheAccessSequence
        )
        cacheCost += cost
    }
}
