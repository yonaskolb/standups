import Foundation
import SwiftComponent
import SwiftUI
import Dependencies

struct MainModel: ComponentModel {

    static let standupList = Scope<StandupsListModel> { $0.scope(state: \.standupList) }

    struct State {
        var standupList: StandupsListModel.State = .init()
    }
}

struct MainView: ComponentView {
    @ObservedObject var model: ViewModel<MainModel>

    var view: some View {
        NavigationView {
            StandupsList(model: model.scope(Model.standupList))
        }
    }
}

struct MainComponent: Component, PreviewProvider {
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

        Test("app walkthrough", state: .init(), assertions: []) {
            Step.dependency(\.dataManager, .mockStandups([]))
            Step.dependency(\.uuid, .incrementing)
            Step.appear()
            Step.scope(Model.standupList) {
                Step.appear()
                Step.action(.addStandup)
                    .expectRoute(/StandupsListModel.Route.add, state: .init(standup: Standup(id: "0")))
                Step.route(/StandupsListModel.Route.add) {
                    Step.binding(\.standup.title, "Engineering")
                }
                let createdStandup = Standup(id: "0", title: "Engineering")
                Step.action(.confirmAddStandup(createdStandup))
                Step.action(.selectStandup(createdStandup))
                    .expectRoute(/StandupsListModel.Route.detail, state: .init(standup: createdStandup))
                Step.route(/StandupsListModel.Route.detail) {
                    Step.action(.edit)
                    Step.route(/StandupDetailModel.Route.edit) {
                        Step.binding(\.standup.theme, .buttercup)
                    }
                    let editedStandup = Standup(id: "0", theme: .buttercup, title: "Engineering")
                    Step.action(.completeEdit(editedStandup))
                    Step.action(.startMeeting)
                    Step.route(/StandupDetailModel.Route.record) {
                        Step.appear(await: false)
                        Step.binding(\.transcript, "Hello")
                        Step.action(.endMeeting)
                        Step.action(.alertButton(.confirmSave))
                        Step.disappear()
                    }
                    Step.action(.selectMeeting(.mock))
                    Step.dismissRoute()
                }
            }
        }
    }
}
