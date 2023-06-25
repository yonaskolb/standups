import Dependencies
import SwiftUI
import SwiftComponent
import Combine
import Foundation

@main
struct StandupsApp: App {

    @StateObject var model: ViewModel<MainModel> = .init(state: .init()).logEvents()

    init() {}

    var body: some Scene {
        WindowGroup {
            // NB: This conditional is here only to facilitate UI testing so that we can mock out certain
            //     dependencies for the duration of the test (e.g. the data manager). We do not really
            //     recommend performing UI tests in general, but we do want to demonstrate how it can be
            //     done.
            if ProcessInfo.processInfo.environment["UITesting"] == "true" {
                // TODO: use view dependency injection
                // StandupsList(model: .init(state: .init()))
                //    .dependency(\.dataManager, .mock)
                withDependencies {
                    $0.dataManager = .mock()
                } operation: {
                    main
                }
            } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                // Unit test
                EmptyView()
            } else if ProcessInfo.processInfo.arguments.contains("component-list") {
                // component list
                withDependencies {
                    $0.context = .preview
                } operation: {
//                    MainComponent.componentPreview
//                    StandupsListComponent.componentPreview
                    ComponentListView(components: components)
                }
            } else {
                main
            }
        }
    }

    var main: some View {
        MainView(model: model)
    }
}

struct AppComponents_Previews: PreviewProvider {
    static var previews: some View {
        ComponentListView(components: components)
    }
}
