import Dependencies
import SwiftUI
import SwiftComponent
import Combine

@main
struct StandupsApp: App {

    let eventSubscription: AnyCancellable

    init() {
        eventSubscription = EventStore.shared.eventPublisher.sink { event in
            print("Component \(event.description)")
        }
    }

    var body: some Scene {
        WindowGroup {
            // NB: This conditional is here only to facilitate UI testing so that we can mock out certain
            //     dependencies for the duration of the test (e.g. the data manager). We do not really
            //     recommend performing UI tests in general, but we do want to demonstrate how it can be
            //     done.
            if ProcessInfo.processInfo.environment["UITesting"] == "true" {
                UITestingView()
            } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                // Unit test
                EmptyView()
            } else {
                // feature list
//                withDependencies {
//                    $0.context = .preview
//                } operation: {
//                    FeatureListView(features: features)
//                }
                StandupsList(model: .init(state: .init()))
            }
        }
    }
}

struct UITestingView: View {
    var body: some View {
        // TODO: use view dependency injection
        // StandupsList(model: .init(state: .init()))
        //    .dependency(\.dataManager, .mock)
        withDependencies {
            $0.dataManager = .mock()
        } operation: {
            StandupsList(model: .init(state: .init()))
        }
    }
}
