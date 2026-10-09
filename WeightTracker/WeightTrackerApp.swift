import SwiftUI

@main
struct WeightTrackerApp: App {
    @StateObject private var store = WeightStore.live()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
