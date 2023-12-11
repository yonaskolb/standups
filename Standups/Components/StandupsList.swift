import Combine
import IdentifiedCollections
import SwiftComponent
import SwiftUI
import SwiftUINavigation

@ComponentModel
struct StandupsListModel {
    
    struct State {
        var standups: IdentifiedArrayOf<Standup> = []
        var loaded = false
        var alert: AlertState<AlertAction>?
    }
    
    enum Route {
        case add(ComponentRoute<StandupFormModel>)
        case detail(ComponentRoute<StandupDetailModel>)
    }
    
    enum AlertAction {
        case confirmLoadMockData
    }
    
    enum Action {
        case addStandup
        case dismissAddStandup
        case confirmAddStandup(Standup)
        case selectStandup(Standup)
        case alertButton(AlertAction?)
    }
    
    enum Input {
        case detail(StandupDetailModel.Output)
    }
    
    func connect(route: Route) -> Connection {
        switch route {
        case .detail(let route):
            return connect(route, output: Input.detail)
        case .add(let route):
            return connect(route)
        }
    }
    
    func appear() async {
        guard !state.loaded else { return }

        do {
            state.standups = try JSONDecoder().decode(
                IdentifiedArray.self,
                from: dependencies.dataManager.load(.standups)
            )
        } catch is DecodingError {
            state.alert = .dataFailedToLoad
        } catch {
            
        }
        state.loaded = true
    }
    
    func handle(action: Action) async {
        switch action {
        case .addStandup:
            route(to: Route.add, state: .init(standup: Standup(id: .init(dependencies.uuid()))))
        case .dismissAddStandup:
            dismissRoute()
        case .confirmAddStandup(let standup):
            var standup = standup
            standup.attendees.removeAll { attendee in
                attendee.name.allSatisfy(\.isWhitespace)
            }
            if standup.attendees.isEmpty {
                standup.attendees.append(Attendee(id: Attendee.ID(dependencies.uuid())))
            }
            state.standups.append(standup)
            dismissRoute()
            saveStandups()
        case .selectStandup(let standup):
            route(to: Route.detail, state: .init(standup: standup))
        case .alertButton(let action):
            switch action {
            case .confirmLoadMockData:
                withAnimation {
                    state.standups = [
                        .mock,
                        .designMock,
                        .engineeringMock,
                    ]
                }
            case .none:
                break
            }
        }
    }
    
    func saveStandups() {
        try? dependencies.dataManager.save(JSONEncoder().encode(state.standups), .standups)
    }
    
    func handle(input: Input) async {
        switch input {
        case .detail(.standupDeleted(let standup)):
            withAnimation {
                state.standups.remove(id: standup)
                dismissRoute()
                saveStandups()
            }
        case .detail(.standupEdited(let standup)):
            state.standups[id: standup.id] = standup
            dismissRoute()
            saveStandups()
        }
    }
}

extension AlertState where Action == StandupsListModel.AlertAction {
    static let dataFailedToLoad = Self {
        TextState("Data failed to load")
    } actions: {
        ButtonState(action: .confirmLoadMockData) {
            TextState("Yes")
        }
        ButtonState(role: .cancel) {
            TextState("No")
        }
    } message: {
        TextState(
      """
      Unfortunately your past data failed to load. Would you like to load some mock data to play \
      around with?
      """)
    }
}

struct StandupsList: ComponentView {
    @ObservedObject var model: ViewModel<StandupsListModel>
    
    func presentation(route: StandupsListModel.Route) -> Presentation {
        switch route {
        case .add:
            return .sheet
        case .detail:
            return .push
        }
    }
    
    func view(route: StandupsListModel.Route) -> some View {
        switch route {
        case .add(let route):
            NavigationStack {
                StandupFormView(model: route.model)
                    .navigationTitle("New standup")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            button(.dismissAddStandup, "Dismiss")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            button(.confirmAddStandup(route.model.state.standup), "Add")
                        }
                    }
            }
        case .detail(let route):
            StandupDetailView(model: route.model)
        }
    }
    
    var view: some View {
        List {
            ForEach(model.standups) { standup in
                model.button(.selectStandup(standup)) {
                    CardView(standup: standup)
                }
                .listRowBackground(standup.theme.mainColor)
            }
        }
        .toolbar {
            model.button(.addStandup) {
                Image(systemName: "plus")
            }
        }
        .navigationTitle("Daily Standups")
        .alert(unwrapping: model.binding(\.alert)) {
            model.send(.alertButton($0))
        }
    }
}

struct CardView: View {
    let standup: Standup
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(self.standup.title)
                .font(.headline)
            Spacer()
            HStack {
                Label("\(self.standup.attendees.count)", systemImage: "person.3")
                Spacer()
                Label(self.standup.duration.formatted(.units()), systemImage: "clock")
                    .labelStyle(.trailingIcon)
            }
            .font(.caption)
        }
        .padding()
        .foregroundColor(self.standup.theme.accentColor)
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.title
            configuration.icon
        }
    }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: Self { Self() }
}

extension URL {
    fileprivate static let standups = Self.documentsDirectory.appending(component: "standups.json")
}

struct StandupsListComponent: Component, PreviewProvider {
    
    typealias Model = StandupsListModel
    
    static func view(model: ViewModel<StandupsListModel>) -> some View {
        NavigationStack { StandupsList(model: model) }
    }
    
    static var preview = PreviewModel(state: .init(standups: [.mock, .designMock, .engineeringMock]))
    
    static var tests: Tests {
        Test("add", state: .init()) {
            let mainQueue = DispatchQueue.test
            let standups = LockIsolated<[Standup]>([])
            let standup = Standup(id: "0")
            let addedStandup: Standup = {
                var standup = standup
                standup.title = "Engineering"
                standup.attendees = [.init(id: .init(), name: "Blob")]
                return standup
            }()
            let addedStandupWithExtra: Standup = {
                var standup = addedStandup
                standup.attendees.append(Attendee(id: Attendee.ID(), name: ""))
                standup.attendees.append(Attendee(id: Attendee.ID(), name: "   "))
                return standup
            }()
            Step.dependency(\.mainQueue, mainQueue.eraseToAnyScheduler())
            Step.dependency(\.uuid, .incrementing)
            Step.dependency(\.dataManager, .mockStandups(standups))
            Step.appear()
            Step.action(.addStandup)
                .expectRoute(/Model.Route.add, state: .init(standup: standup))
            Step.branch("dismiss") {
                Step.action(.dismissAddStandup)
                    .expectEmptyRoute()
            }
            Step.branch("confirm") {
                Step.action(.confirmAddStandup(addedStandupWithExtra))
                    .expectEmptyRoute()
                    .expectState(\.standups, [addedStandup])
                Step.run("Run main") { await mainQueue.run() }
                    .validateState("saved standup") {
                        standups.value == $0.standups.elements
                    }
            }
        }
        
        Test("select", state: .init(standups: [.mock, .designMock])) {
            Step.action(.selectStandup(.designMock))
                .expectRoute(/Model.Route.detail, state: .init(standup: .designMock))
            Step.branch("delete") {
                Step.route(/Model.Route.detail, output: .standupDeleted(Standup.designMock.id))
                    .expectEmptyRoute()
                    .expectState(\.standups, [.mock])
            }
            Step.branch("edit") {
                let editedStandup: Standup = {
                    var standup = Standup.designMock
                    standup.title = "Engineering"
                    standup.attendees = [.init(id: .init(), name: "Blob")]
                    return standup
                }()
                Step.route(/Model.Route.detail, output: .standupEdited(editedStandup))
                    .expectState(\.standups, [.mock, editedStandup])
                    .expectEmptyRoute()
            }
        }
        
        Test("load", state: .init()) {
            Step.snapshot("empty")
            Step.branch("load failure") {
                Step.appear()
                    .expectState(\.alert, nil)
                    .dependency(\.dataManager, .failToLoad)
            }
            Step.branch("decoding failure") {
                Step.appear()
                    .expectState(\.alert, .dataFailedToLoad)
                    .dependency(\.dataManager, .failToDecode)
                Step.action(.alertButton(.confirmLoadMockData))
                    .expectState(\.standups, [.mock, .designMock, .engineeringMock])
                Step.binding(\.alert, nil)
            }
            Step.branch("successful") {
                Step.appear()
                    .dependency(\.dataManager, .mockStandups([.mock, .designMock]))
                    .expectState(\.standups, [.mock, .designMock])
                Step.snapshot("content")
            }
        }
    }
}
