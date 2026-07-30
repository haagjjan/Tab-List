import CoreGraphics
import Darwin
import Foundation
import TabListCore
@testable import TabList

enum AppTestFixtures {
    static func key(_ value: UInt32, pid: Int32 = 100) -> WindowKey {
        WindowKey(pid: pid, windowID: value)
    }

    static func window(
        _ value: UInt32,
        pid: Int32 = 100,
        bundleIdentifier: String? = "com.example.App",
        applicationName: String = "Example",
        title: String = "Window",
        bounds: CGRect = CGRect(
            x: 10,
            y: 20,
            width: 800,
            height: 600
        ),
        spaceIDs: [UInt64] = [1],
        displayID: CGDirectDisplayID? = 10,
        isMinimized: Bool = false,
        isHidden: Bool = false,
        isFullscreen: Bool = false,
        isStandardWindow: Bool = true,
        isClosable: Bool = true,
        focusSequence: UInt64 = 0
    ) -> WindowRecord {
        WindowRecord(
            id: key(value, pid: pid),
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            bundleURL: URL(
                fileURLWithPath: "/Applications/\(applicationName).app"
            ),
            windowTitle: title,
            bounds: bounds,
            spaceIDs: spaceIDs,
            displayID: displayID,
            isMinimized: isMinimized,
            isHidden: isHidden,
            isFullscreen: isFullscreen,
            isStandardWindow: isStandardWindow,
            isClosable: isClosable,
            lastFocusSequence: focusSequence
        )
    }

    static func candidate(
        for window: WindowRecord,
        isOnScreen: Bool
    ) -> PublicWindowCandidate {
        PublicWindowCandidate(
            key: window.id,
            ownerName: window.applicationName,
            title: window.windowTitle,
            bounds: window.bounds,
            layer: 0,
            alpha: 1,
            isOnScreen: isOnScreen
        )
    }
}
