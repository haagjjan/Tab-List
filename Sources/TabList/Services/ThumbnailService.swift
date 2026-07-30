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
    ) async -> Set<WindowKey>
    func cancelPending() async
    func purge() async
}

private final class ThumbnailImageBox: @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
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
actor ThumbnailCaptureLimiter {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var active = 0
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async -> Value?
    ) async -> Value? {
        guard await acquire() else { return nil }
        defer { release() }
        guard !Task.isCancelled else { return nil }
        let result = await operation()
        guard !Task.isCancelled else { return nil }
        return result
    }

#if DEBUG
    func debugCounts() -> (active: Int, waiting: Int) {
        (active, waiters.count)
    }
#endif

    private func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if active < limit {
            active += 1
            return true
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters.append(
                        Waiter(id: id, continuation: continuation)
                    )
                }
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id)
            }
        }
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        waiters.remove(at: index).continuation.resume(returning: false)
    }
}

/// ScreenCaptureKit-backed, memory-only window previews. It is intentionally
/// lazy: constructing this service does not query shareable content or request
/// Screen Recording.
public actor ThumbnailService: ThumbnailProviding {
    public static let maximumMemoryCost = 128 * 1_024 * 1_024
    public static let maximumCount = 120
    public static let maximumConcurrentCaptures = 3

    private var cache: [ThumbnailIdentity: ThumbnailImageBox] = [:]
    private var cacheBudget = BoundedCostLRU<ThumbnailIdentity>(
        totalCostLimit: maximumMemoryCost,
        countLimit: maximumCount
    )
    private var requestGeneration: UInt64 = 0
    private var inFlight: [ThumbnailIdentity: ThumbnailCaptureFlight] = [:]
    private let captureLimiter = ThumbnailCaptureLimiter(
        limit: maximumConcurrentCaptures
    )

    public init() {}

    public func cachedThumbnail(for window: WindowRecord) -> CGImage? {
        let identity = ThumbnailIdentity(window)
        guard let image = cache[identity] else { return nil }
        cacheBudget.touch(identity)
        return image.image
    }

    public func refresh(
        _ windows: [WindowRecord],
        priority: [WindowKey],
        targetSize: CGSize = CGSize(width: 640, height: 400)
    ) async -> Set<WindowKey> {
        guard CGPreflightScreenCaptureAccess(), !windows.isEmpty else {
            return []
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
            TabListLog.thumbnails.error(
                "ScreenCaptureKit shareable-content enumeration failed"
            )
            return []
        }
        guard generation == requestGeneration, !Task.isCancelled else {
            return []
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
                () -> ThumbnailImageBox? in
                await limiter.run {
                    () -> ThumbnailImageBox? in
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

        var capturedKeys: Set<WindowKey> = []
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
            if store(
                image.image,
                for: scheduledCapture.identity,
                cost: cost
            ) {
                capturedKeys.insert(scheduledCapture.identity.key)
            }
        }
        return capturedKeys
    }

    public func cancelPending() async {
        requestGeneration &+= 1
        let flights = Array(inFlight.values)
        inFlight.removeAll(keepingCapacity: true)
        for flight in flights {
            flight.task.cancel()
        }
        // Do not await ScreenCaptureKit here. Dismissal and permission
        // revocation must return immediately even if an OS capture call is
        // slow to observe cancellation. Generation checks prevent any late
        // result from entering the cache.
    }

    public func purge() async {
        cache.removeAll(keepingCapacity: false)
        cacheBudget.removeAll()
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
    ) -> Bool {
        let insertion = cacheBudget.insert(identity, cost: cost)
        guard insertion.accepted else { return false }
        for evicted in insertion.evicted {
            cache[evicted] = nil
        }
        cache[identity] = ThumbnailImageBox(image)
        return true
    }
}
