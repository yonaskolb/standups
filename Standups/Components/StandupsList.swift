import Combine
import IdentifiedCollections
import SwiftComponent
import SwiftUI
import SwiftUINavigation

struct StandupsListModel: ComponentModel {

    struct State {
        var standups: IdentifiedArrayOf<Standup> = []
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
        case standupTapped(Standup)
        case alertButton(AlertAction?)
    }

    enum Input {
        case detail(StandupDetailModel.Output)
    }

    func connect(route: Route, store: Store) -> Connection {
        switch route {
            case .detail(let route):
                return store.connect(route, output: Input.detail)
            case .add(let route):
                return store.connect(route)
        }
    }

    func appear(store: Store) async {
        do {
            store.standups = try JSONDecoder().decode(
                IdentifiedArray.self,
                from: store.dependencies.dataManager.load(.standups)
            )
        } catch is DecodingError {
            store.alert = .dataFailedToLoad
        } catch {

        }

        store.statePublisher(\.standups)
            .debounce(for: .seconds(1), scheduler: store.dependencies.mainQueue)
            .sink { standups in
                try? store.dependencies.dataManager.save(JSONEncoder().encode(standups), .standups)
            }
            .store(in: &store.cancellables)
    }

    func handle(action: Action, store: Store) async {
        switch action {
            case .addStandup:
                store.route(to: Route.add, state: .init(standup: Standup(id: .init(store.dependencies.uuid()))))
            case .dismissAddStandup:
                store.dismissRoute()
            case .confirmAddStandup(let standup):
                var standup = standup
                standup.attendees.removeAll { attendee in
                    attendee.name.allSatisfy(\.isWhitespace)
                }
                if standup.attendees.isEmpty {
                    standup.attendees.append(Attendee(id: Attendee.ID(store.dependencies.uuid())))
                }
                store.standups.append(standup)
                store.dismissRoute()
            case .standupTapped(let standup):
                store.route(to: Route.detail, state: .init(standup: standup))
            case .alertButton(let action):
                switch action {
                    case .confirmLoadMockData:
                        withAnimation {
                            store.standups = [
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

    func handle(input: Input, store: Store) async {
        switch input {
            case .detail(.standupDeleted(let standup)):
                withAnimation {
                    store.standups.remove(id: standup)
                    store.dismissRoute()
                }
            case .detail(.standupEdited(let standup)):
                store.standups[id: standup.id] = standup
                store.dismissRoute()
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

    func presentation(for route: StandupsListModel.Route) -> Presentation {
        switch route {
            case .add:
                return .sheet
            case .detail:
                return .push
        }
    }

    func routeView(_ route: StandupsListModel.Route) -> some View {
        switch route {
            case .add(let route):
                NavigationStack {
                    StandupFormView(model: route.viewModel)
                        .navigationTitle("New standup")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Dismiss") {
                                    model.send(.dismissAddStandup)
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") {
                                    model.send(.confirmAddStandup(route.viewModel.state.standup))
                                }
                            }
                        }
                }
            case .detail(let route):
                StandupDetailView(model: route.viewModel)
        }
    }

    var view: some View {
        List {
            ForEach(model.standups) { standup in
                model.button(.standupTapped(standup)) {
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
        NavigationView { StandupsList(model: model) }
    }

    static var states: States {
        State("list") {
            .init(standups: [.mock, .designMock, .engineeringMock])
        }

        State("empty") {
            .init(standups: [])
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
        Test("Add", state: .init()) {
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
            Step.action(.confirmAddStandup(addedStandupWithExtra))
                .expectEmptyRoute()
                .expectState(\.standups, [addedStandup])
            Step.run("Run main") { await mainQueue.run() }
                .validateState("saved standup") {
                    standups.value == $0.standups.elements
                }
        }

        Test("Select", state: Model.State(standups: [.mock, .designMock]), assertions: .all) {
            Step.action(.standupTapped(.designMock))
                .expectRoute(/Model.Route.detail, state: .init(standup: .designMock))
            Step.fork("Delete") {
                Step.route(/Model.Route.detail, output: .standupDeleted(Standup.designMock.id))
                    .expectEmptyRoute()
                    .expectState(\.standups, [.mock])
            }
            Step.fork("Edit") {
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

        Test("Load", state: .init()) {
            Step.fork("load failure") {
                Step.dependency(\.dataManager, .failToLoad)
                Step.appear()
                    .expectState(\.alert, nil)
            }
            Step.fork("decoding failure") {
                Step.dependency(\.dataManager, .failToDecode)
                Step.appear()
                    .expectState(\.alert, .dataFailedToLoad)
                Step.action(.alertButton(.confirmLoadMockData))
                    .expectState(\.standups, [.mock, .designMock, .engineeringMock])
                Step.binding(\.alert, nil)
            }
            Step.fork("successful") {
                Step.dependency(\.dataManager, .mockStandups([.mock, .designMock]))
                Step.appear()
                    .expectState(\.standups, [.mock, .designMock])
            }
        }
    }
}
