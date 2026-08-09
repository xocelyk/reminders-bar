import SwiftUI

@main
struct RemindersBarApp: App {
    @StateObject private var store = RemindersStore()

    var body: some Scene {
        MenuBarExtra("Reminders", systemImage: "checklist") {
            ContentView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

enum Theme {
    // design-language canonical accents
    static let teal = Color(red: 0x38 / 255.0, green: 0x87 / 255.0, blue: 0x9B / 255.0)
    static let vermillion = Color(red: 0xB8 / 255.0, green: 0x44 / 255.0, blue: 0x2B / 255.0)
}
