import AppKit
import UserNotifications

final class App: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                guard granted else {
                    NSApp.terminate(nil)
                    return
                }
                let args = CommandLine.arguments
                let content = UNMutableNotificationContent()
                content.title = args.count > 1 ? args[1] : "Grok"
                content.body = args.count > 2 ? args[2] : "Finished responding"
                content.sound = UNNotificationSound.default
                let req = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                center.add(req) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
