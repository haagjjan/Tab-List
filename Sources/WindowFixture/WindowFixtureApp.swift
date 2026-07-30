import AppKit

@main
@MainActor
final class WindowFixtureApp: NSObject, NSApplicationDelegate {
    private var fixtureController: FixtureController?

    static func main() {
        let application = NSApplication.shared
        let delegate = WindowFixtureApp()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fixtureController = FixtureController()
        self.fixtureController = fixtureController
        fixtureController.start()
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
