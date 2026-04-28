//
//  Report_TemplateApp.swift
//  Report Template
//
//  Created by Karl Garcia on 2/6/26.
//

import SwiftUI
import SwiftData

final class AppCommandBridge: ObservableObject {
    var onPrint: (() -> Void)?

    func triggerPrint() {
        onPrint?()
    }
}

@main
struct Report_TemplateApp: App {
    @StateObject private var appUpdateService = AppUpdateService()
    @StateObject private var appCommandBridge = AppCommandBridge()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(appUpdateService: appUpdateService, appCommandBridge: appCommandBridge)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .printItem) {
                Button("Print Report...") {
                    appCommandBridge.triggerPrint()
                }
                .keyboardShortcut("p", modifiers: .command)
            }
        }
    }
}
