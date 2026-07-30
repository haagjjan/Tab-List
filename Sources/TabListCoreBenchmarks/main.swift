import CoreGraphics
import Foundation
import TabListCore

private struct BenchmarkResult: Codable {
    let name: String
    let windowCount: Int
    let samples: Int
    let iterationsPerSample: Int
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let verificationBudgetMilliseconds: Double

    var passed: Bool {
        p95Milliseconds <= verificationBudgetMilliseconds
    }
}

@inline(never)
private func consume<T>(_ value: T) {
    withExtendedLifetime(value) {}
}

private func benchmark(
    name: String,
    windowCount: Int,
    samples: Int,
    iterationsPerSample: Int,
    budgetMilliseconds: Double,
    operation: () -> Void
) -> BenchmarkResult {
    var durations: [Double] = []
    durations.reserveCapacity(samples)

    for _ in 0..<samples {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterationsPerSample {
            operation()
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        durations.append(
            Double(elapsed) / 1_000_000 / Double(iterationsPerSample)
        )
    }

    durations.sort()
    let median = durations[durations.count / 2]
    let p95Index = min(
        durations.count - 1,
        Int((Double(durations.count) * 0.95).rounded(.up)) - 1
    )
    return BenchmarkResult(
        name: name,
        windowCount: windowCount,
        samples: samples,
        iterationsPerSample: iterationsPerSample,
        medianMilliseconds: median,
        p95Milliseconds: durations[p95Index],
        verificationBudgetMilliseconds: budgetMilliseconds
    )
}

private func makeWindows(count: Int) -> [WindowRecord] {
    var result: [WindowRecord] = []
    result.reserveCapacity(count)
    for index in 0..<count {
        let key = WindowKey(
            pid: pid_t(1_000 + index % 12),
            windowID: CGWindowID(index + 1)
        )
        let bounds = CGRect(
            x: index * 3,
            y: index * 2,
            width: 1_000,
            height: 700
        )
        result.append(
            WindowRecord(
                id: key,
                bundleIdentifier: "com.example.App\(index % 12)",
                applicationName: "Application \(index % 12)",
                bundleURL: nil,
                windowTitle: "Synthetic window \(index)",
                bounds: bounds,
                spaceIDs: [UInt64(index % 5 + 1)],
                displayID: CGDirectDisplayID(index % 2 + 1),
                isMinimized: index.isMultiple(of: 10),
                isHidden: index.isMultiple(of: 17),
                isFullscreen: index.isMultiple(of: 19),
                isStandardWindow: true,
                isClosable: true,
                lastFocusSequence: UInt64(count - index),
                incarnation: UInt64(index + 1)
            )
        )
    }
    return result
}

private let windows = makeWindows(count: 100)
private let snapshot = WindowSnapshot(
    generation: 1,
    windows: windows,
    visibleSpaceIDs: [1, 2, 3, 4, 5]
)

private var reducerState: SwitcherSessionState = {
    var state = SwitcherSessionState()
    _ = SwitcherSessionReducer.reduce(
        state: &state,
        action: .begin(
            originalFocus: FocusSnapshot(
                applicationPID: windows[0].id.pid,
                windowKey: windows[0].id
            ),
            initialDirection: .forward
        )
    )
    _ = SwitcherSessionReducer.reduce(
        state: &state,
        action: .prepared(
            snapshotGeneration: 1,
            orderedItems: windows
        )
    )
    return state
}()

private let results = [
    benchmark(
        name: "candidate-pipeline",
        windowCount: windows.count,
        samples: 40,
        iterationsPerSample: 500,
        budgetMilliseconds: 16
    ) {
        consume(
            WindowSelectionPipeline.candidates(
                from: snapshot,
                settings: .default,
                pointerDisplayID: 1
            )
        )
    },
    benchmark(
        name: "selection-reducer",
        windowCount: windows.count,
        samples: 40,
        iterationsPerSample: 5_000,
        budgetMilliseconds: 16
    ) {
        consume(
            SwitcherSessionReducer.reduce(
                state: &reducerState,
                action: .cycle(.forward)
            )
        )
    },
    benchmark(
        name: "layout-calculation",
        windowCount: windows.count,
        samples: 40,
        iterationsPerSample: 5_000,
        budgetMilliseconds: 16
    ) {
        consume(
            LayoutCalculator.metrics(
                preset: .auto,
                presentation: .thumbnails,
                displayVisibleFrame: CGRect(
                    x: 0,
                    y: 0,
                    width: 1_440,
                    height: 900
                ),
                itemCount: windows.count
            )
        )
    },
    benchmark(
        name: "thumbnail-capture-plan",
        windowCount: windows.count,
        samples: 40,
        iterationsPerSample: 2_000,
        budgetMilliseconds: 16
    ) {
        consume(
            ThumbnailCapturePlan(
                allKeys: windows.map(\.id),
                priorityKeys: [
                    windows[50].id,
                    windows[49].id,
                    windows[51].id,
                ],
                visibleKeys: windows.prefix(24).map(\.id)
            )
        )
    },
]

private let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let output = try encoder.encode(results)
FileHandle.standardOutput.write(output)
FileHandle.standardOutput.write(Data("\n".utf8))

if CommandLine.arguments.contains("--verify"),
   results.contains(where: { !$0.passed }) {
    exit(EXIT_FAILURE)
}
