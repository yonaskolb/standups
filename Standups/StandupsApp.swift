import Dependencies
import SwiftUI
import SwiftComponent
import Combine
import Foundation

@main
struct StandupsApp: App {

    let eventSubscription: AnyCancellable

    init() {
        eventSubscription = EventStore.shared.eventPublisher.sink { event in

            let valueSuffix: String
            switch event.type {
                case .mutation, .binding:
                    let value = event.type.value
                    let valueString = dumpToString(value, maxDepth: 2)
                    if valueString == "\"\"" {
                        valueSuffix = ""
                    } else if valueString.contains("\n") {
                        valueSuffix = "\n\t" + valueString.replacingOccurrences(of: "\n", with: "\n\t")
                    } else {
                        valueSuffix = " = \(valueString)"
                    }

                default:
                    valueSuffix = ""
            }
            print("\(event.type.emoji) \(event.description)\(valueSuffix)")
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
            } else if ProcessInfo.processInfo.arguments.contains("component-list") {
                // component list
                withDependencies {
                    $0.context = .preview
                } operation: {
                    ComponentListView(components: components)
                }
            } else {
                NavigationView {
                    StandupsList(model: .init(state: .init()))
                }
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
            NavigationView {
                StandupsList(model: .init(state: .init()))
            }
        }
    }
}

struct AppComponents_Previews: PreviewProvider {
    static var previews: some View {
        ComponentListView(components: components)
    }
}

struct AppComponent: PreviewProvider, Component {
    typealias Model = StandupsListModel

    static func view(model: ViewModel<Model>) -> some View {
        NavigationView {
            StandupsList(model: model)
        }
    }

    static var states: States {
        State("app") {
            .init()
        }
        State(
            "deeplink",
            route: .detail(
                .init(
                    state: .init(standup: .mock),
                    route: .record(
                        .init(
                            state: .init(standup: .mock)
                        )
                    )
                )
            )
        ) {
            .init(standups: [.mock])
        }
    }

    static var tests: Tests {
        let standup = Standup(id: "0")

        Test("app walkthrough", state: .init()) {
            Step.setDependency(\.uuid, .incrementing)
            Step.setDependency(\.dataManager.load, { _ in try! JSONEncoder().encode([] as [Standup]) })
            Step.appear()
            Step.action(.addStandup)
                .expectRoute(/Model.Route.add, state: .init(standup: standup))
            Step.route(/Model.Route.add) {
                TestStep<StandupFormModel>.setBinding(\.standup.title, "Engineering")
            }
            let createdStandup = Standup(id: "0", title: "Engineering")
            Step.action(.confirmAddStandup(createdStandup))
            Step.action(.standupTapped(createdStandup))
                .expectRoute(/Model.Route.detail, state: .init(standup: createdStandup))
            Step.route(/Model.Route.detail) {
                TestStep<StandupDetailModel>.action(.edit)
                TestStep<StandupDetailModel>.route(/StandupDetailModel.Route.edit) {
                    TestStep<StandupFormModel>.setBinding(\.standup.theme, .buttercup)
                }
                let editedStandup = Standup(id: "0", theme: .buttercup, title: "Engineering")
                TestStep<StandupDetailModel>.action(.doneEditing(editedStandup))
                TestStep<StandupDetailModel>.action(.startMeeting)
                TestStep<StandupDetailModel>.route(/StandupDetailModel.Route.record) {
                    TestStep<RecordMeetingModel>.appear(await: false)
                    TestStep<RecordMeetingModel>.setBinding(\.transcript, "Hello")
                    TestStep<RecordMeetingModel>.action(.endMeeting)
                    TestStep<RecordMeetingModel>.action(.alertButton(.confirmSave))
                }
            }
        }
    }
}
