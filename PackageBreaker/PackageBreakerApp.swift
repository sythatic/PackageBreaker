import SwiftUI

@main
struct PackageBreakerApp: App {
	var body: some Scene {
		WindowGroup {
			ContentView()
		}
		.windowStyle(.hiddenTitleBar)
		.windowResizability(.contentSize)
		.commands {
			CommandGroup(replacing: .newItem) { }
		}
	}
}
