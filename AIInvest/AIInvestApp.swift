import SwiftUI

@main
struct AIInvestApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("AI Invest") {
            RootView()
                .environmentObject(appModel)
                .tint(AppTheme.accent)
        }
        .defaultSize(width: 1_320, height: 820)
        .commands {
            CommandGroup(after: .sidebar) {
                Divider()
                ForEach(AppSection.allCases) { section in
                    Button("打开\(section.rawValue)") {
                        appModel.selectedSection = section
                    }
                    .keyboardShortcut(shortcut(for: section), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
                .tint(AppTheme.accent)
        }
    }

    private func shortcut(for section: AppSection) -> KeyEquivalent {
        switch section {
        case .holdings: "1"
        case .strategy: "2"
        case .advice: "3"
        case .research: "4"
        case .learning: "5"
        }
    }
}
