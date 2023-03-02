import Foundation
import SwiftComponent
import SwiftUI


struct MainModel: ComponentModel {

    static let standups = Scope<StandupsListModel> { $0.scope(statePath: \.standups) }

    struct State {
        var standups: StandupsListModel.State = .init()
    }
}

struct MainView: ComponentView {
    @ObservedObject var model: ViewModel<MainModel>

    var view: some View {
        NavigationView {
            StandupsList(model: model.scope(Model.standups))
        }
    }
}

struct MainComponent: PreviewProvider, Component {
    typealias Model = MainModel

    static func view(model: ViewModel<Model>) -> some View {
        MainView(model: model)
    }

    static var states: States {
        State("Main") {
            .init()
        }
    }

    static var tests: Tests {

        Test("app walkthrough", state: .init()) {
            let standup = Standup(id: "0")
            Step.dependency(\.dataManager.load, { _ in try! JSONEncoder().encode([] as [Standup]) })
            Step.scope(Model.standups) {
                TestStep<StandupsListModel>.appear()
                TestStep<StandupsListModel>.action(.addStandup)
                    .expectRoute(/StandupsListModel.Route.add, state: .init(standup: standup))
                TestStep<StandupsListModel>.route(/StandupsListModel.Route.add) {
                    TestStep<StandupFormModel>.binding(\.standup.title, "Engineering")
                }
                let createdStandup = Standup(id: "0", title: "Engineering")
                TestStep<StandupsListModel>.action(.confirmAddStandup(createdStandup))
                TestStep<StandupsListModel>.action(.standupTapped(createdStandup))
                    .expectRoute(/StandupsListModel.Route.detail, state: .init(standup: createdStandup))
                TestStep<StandupsListModel>.route(/StandupsListModel.Route.detail) {
                    TestStep<StandupDetailModel>.action(.edit)
                    TestStep<StandupDetailModel>.route(/StandupDetailModel.Route.edit) {
                        TestStep<StandupFormModel>.binding(\.standup.theme, .buttercup)
                    }
                    let editedStandup = Standup(id: "0", theme: .buttercup, title: "Engineering")
                    TestStep<StandupDetailModel>.action(.doneEditing(editedStandup))
                    TestStep<StandupDetailModel>.action(.startMeeting)
                    TestStep<StandupDetailModel>.route(/StandupDetailModel.Route.record) {
                        TestStep<RecordMeetingModel>.appear(await: false)
                        TestStep<RecordMeetingModel>.binding(\.transcript, "Hello")
                        TestStep<RecordMeetingModel>.action(.endMeeting)
                        TestStep<RecordMeetingModel>.action(.alertButton(.confirmSave))
                    }
                }
            }
        }
    }
}
