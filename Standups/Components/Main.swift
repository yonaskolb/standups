import Foundation
import SwiftComponent
import SwiftUI


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

        Test("app walkthrough", state: .init(), assertions: []) {
            Step.dependency(\.dataManager, .mockStandups([]))
            Step.dependency(\.uuid, .incrementing)
            Step.appear()
            Step.scope(Model.standupList) {
                $0.appear()
                $0.action(.addStandup)
                    .expectRoute(/StandupsListModel.Route.add, state: .init(standup: Standup(id: "0")))
                $0.route(/StandupsListModel.Route.add) {
                    $0.binding(\.standup.title, "Engineering")
                }
                let createdStandup = Standup(id: "0", title: "Engineering")
                $0.action(.confirmAddStandup(createdStandup))
                $0.action(.standupTapped(createdStandup))
                    .expectRoute(/StandupsListModel.Route.detail, state: .init(standup: createdStandup))
                $0.route(/StandupsListModel.Route.detail) {
                    $0.action(.edit)
                    $0.route(/StandupDetailModel.Route.edit) {
                        $0.binding(\.standup.theme, .buttercup)
                    }
                    let editedStandup = Standup(id: "0", theme: .buttercup, title: "Engineering")
                    $0.action(.doneEditing(editedStandup))
                    $0.action(.startMeeting)
                    $0.route(/StandupDetailModel.Route.record) {
                        $0.appear(await: false)
                        $0.binding(\.transcript, "Hello")
                        $0.action(.endMeeting)
                        $0.action(.alertButton(.confirmSave))
                    }
                }
            }
        }
    }
}
