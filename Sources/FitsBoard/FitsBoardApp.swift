import SwiftUI
import FitsCore

@main
struct FitsBoardApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            BoardView()
                .environmentObject(model)
                .frame(minWidth: 1320, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Task") {
                    model.presentTaskSheet()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}
