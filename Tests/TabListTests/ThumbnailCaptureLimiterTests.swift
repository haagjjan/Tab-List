import Foundation
@testable import TabList
import Testing

@Suite
struct ThumbnailCaptureLimiterTests {
    private actor ConcurrencyProbe {
        private var active = 0
        private var maximum = 0

        func begin() {
            active += 1
            maximum = max(maximum, active)
        }

        func end() {
            active -= 1
        }

        func maximumObserved() -> Int {
            maximum
        }
    }

    @Test
    func limitsConcurrentOperations() async {
        let limiter = ThumbnailCaptureLimiter(limit: 3)
        let probe = ConcurrencyProbe()

        await withTaskGroup(of: Int?.self) { group in
            for value in 0..<12 {
                group.addTask {
                    await limiter.run {
                        await probe.begin()
                        try? await Task.sleep(for: .milliseconds(20))
                        await probe.end()
                        return value
                    }
                }
            }

            for await result in group {
                #expect(result != nil)
            }
        }

        #expect(await probe.maximumObserved() == 3)
        let counts = await limiter.debugCounts()
        #expect(counts.active == 0)
        #expect(counts.waiting == 0)
    }

    @Test
    func cancellingQueuedOperationRemovesItsWaiter() async {
        let limiter = ThumbnailCaptureLimiter(limit: 1)

        let occupying = Task {
            await limiter.run {
                while !Task.isCancelled {
                    await Task.yield()
                }
                return 1
            }
        }
        await waitForCounts(limiter, active: 1, waiting: 0)

        let queued = Task {
            await limiter.run {
                2
            }
        }
        await waitForCounts(limiter, active: 1, waiting: 1)

        queued.cancel()
        #expect(await queued.value == nil)
        await waitForCounts(limiter, active: 1, waiting: 0)

        occupying.cancel()
        #expect(await occupying.value == nil)
        await waitForCounts(limiter, active: 0, waiting: 0)
    }

    private func waitForCounts(
        _ limiter: ThumbnailCaptureLimiter,
        active: Int,
        waiting: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<2_000 {
            let counts = await limiter.debugCounts()
            if counts.active == active, counts.waiting == waiting {
                return
            }
            await Task.yield()
        }

        let counts = await limiter.debugCounts()
        #expect(
            counts.active == active && counts.waiting == waiting,
            Comment(
                rawValue: "Expected \(active) active and \(waiting) waiting; "
                    + "got \(counts.active) active and "
                    + "\(counts.waiting) waiting"
            ),
            sourceLocation: sourceLocation
        )
    }
}
