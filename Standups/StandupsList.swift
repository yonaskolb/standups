import Combine
import Dependencies
import IdentifiedCollections
import SwiftComponent
import SwiftUI
import SwiftUINavigation

struct StandupsListModel: ComponentModel {

    @Dependency(\.dataManager) var dataManager
    @Dependency(\.uuid) var uuid
    @Dependency(\.mainQueue) var mainQueue

    struct State {
        //TODO: sync updates from detail
        var standups: IdentifiedArrayOf<Standup> = []
        var destination: Destination?
    }

    enum Destination {
        case add(StandupFormModel.State)
        case alert(AlertState<AlertAction>)
        case detail(StandupDetailModel.State)
    }

    enum AlertAction {
        case confirmLoadMockData
    }

    enum Action {
        case addStandup
        case dismissAddStandup
        case confirmAddStandup
        case standupTapped(Standup)
        case alertButton(AlertAction?)
    }

    enum Input {
        case detail(StandupDetailModel.Output)
    }

    func appear(model: Model) async {
        do {
            model.standups = try JSONDecoder().decode(
                IdentifiedArray.self,
                from: self.dataManager.load(.standups)
            )
        } catch is DecodingError {
            model.destination = .alert(.dataFailedToLoad)
        } catch {

        }

        model.statePublisher(\.standups)
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: self.mainQueue)
            .sink { standups in
                try? dataManager.save(JSONEncoder().encode(standups), .standups)
            }
            .store(in: &model.cancellables)
    }

    func handle(action: Action, model: Model) async {
        switch action {
            case .addStandup:
                model.destination = .add(.init(standup: Standup(id: Standup.ID(uuid()))))
            case .dismissAddStandup:
                model.destination = nil
            case .confirmAddStandup:
                defer { model.destination = nil }

                guard case let .add(standupFormState) = model.destination
                else { return }
                var standup = standupFormState.standup

                standup.attendees.removeAll { attendee in
                    attendee.name.allSatisfy(\.isWhitespace)
                }
                if standup.attendees.isEmpty {
                    standup.attendees.append(Attendee(id: Attendee.ID(self.uuid())))
                }
                model.standups.append(standup)
            case .standupTapped(let standup):
                model.destination = .detail(.init(standup: standup))
            case .alertButton(let action):
                switch action {
                    case .confirmLoadMockData?:
                        withAnimation {
                            model.standups = [
                                .mock,
                                .designMock,
                                .engineeringMock,
                            ]
                        }
                    case nil:
                        break
                }
        }
    }

    func handle(input: Input, model: Model) async {
        switch input {
            case .detail(.confirmDeletion(let standup)):
                withAnimation {
                    model.standups.remove(id: standup)
                    model.destination = nil
                }
            case .detail(.standupEdited(let standup)):
                model.standups[id: standup.id] = standup
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

    var view: some View {
        NavigationStack {
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
            .sheet(
                unwrapping: model.binding(\.destination),
                case: /StandupsListModel.Destination.add
            ) { $state in
                NavigationStack {
                    StandupFormView(model: model.scope(state: $state))
                        .navigationTitle("New standup")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Dismiss") {
                                    model.send(.dismissAddStandup)
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") {
                                    model.send(.confirmAddStandup)
                                }
                            }
                        }
                }
            }
            .navigationDestination(
                unwrapping: model.binding(\.destination),
                case: /StandupsListModel.Destination.detail
            ) { $state in
                StandupDetailView(model: model.scope(state: $state, output: Model.Input.detail))
            }
            .alert(
                unwrapping: model.binding(\.destination),
                case: /StandupsListModel.Destination.alert
            ) {
                model.send(.alertButton($0))
            }
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

struct StandupsListFeature: PreviewProvider, ComponentFeature {

    typealias Model = StandupsListModel

    static func createView(model: ViewModel<StandupsListModel>) -> some View {
        StandupsList(model: model)
    }

    static var states: [ComponentState] {
        ComponentState("list") {
            .init(standups: [.mock, .designMock, .engineeringMock])
        }
        ComponentState("deeplink") {
            .init(standups: [.mock], destination: .detail(.init(destination: .edit(.init(standup: .mock)), standup: .mock)))
        }
    }

    static var tests: [ComponentTest] {
        ComponentTest("add", state: .init()) {
            let mainQueue = DispatchQueue.test
            let savedData = LockIsolated(Data?.none)
            let standup = Standup(id: .init(uuidString: "00000000-0000-0000-0000-000000000000")!)
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
            Step.setDependency(\.mainQueue, mainQueue.eraseToAnyScheduler())
            Step.setDependency(\.uuid, .incrementing)
            Step.setDependency(\.dataManager.load, { _ in
                struct FileNotFound: Error {}
                throw FileNotFound()
            })
            Step.setDependency(\.dataManager.save, { data, _ in
                savedData.setValue(data)
            })
            Step.appear()
            Step.action(.addStandup)
                .expectState(\.destination, .add(.init(standup: standup)))
            Step.setBinding(\.destination, .add(.init(standup: addedStandupWithExtra)))
            Step.action(.confirmAddStandup)
                .expectState(\.destination, nil)
                .expectState(\.standups, [addedStandup])
            Step.run("run main") { await mainQueue.run() }
                .validateState("saved standup") {
                    guard let data = savedData.value else { return false }
                    return try! $0.standups == JSONDecoder().decode(IdentifiedArrayOf<Standup>.self, from: data)
                }
        }

        ComponentTest("delete", state: .init(standups: [.mock, .designMock])) {
            Step.action(.standupTapped(.designMock))
                .expectState(\.destination, .detail(.init(standup: .designMock)))
            Step.input(.detail(.confirmDeletion(Standup.designMock.id)))
                .expectState(\.destination, nil)
                .expectState(\.standups, [.mock])
        }

        ComponentTest("edit", state: .init(standups: [.mock, .designMock])) {
            let editedStandup: Standup = {
                var standup = Standup.designMock
                standup.title = "Engineering"
                standup.attendees = [.init(id: .init(), name: "Blob")]
                return standup
            }()
            Step.action(.standupTapped(.designMock))
                .expectState(\.destination, .detail(.init(standup: .designMock)))
            Step.input(.detail(.standupEdited(editedStandup)))
                .expectState(\.standups, [.mock, editedStandup])
        }

        ComponentTest("load successful", state: .init()) {
            Step.setDependency(\.dataManager.load, { _ in try JSONEncoder().encode([Standup.mock, .designMock])
            })
            Step.appear()
                .expectState(\.standups, [.mock, .designMock])
        }

        ComponentTest("load decoding failure", state: .init()) {
            Step.setDependency(\.dataManager, .mock(initialData: Data("bad data".utf8)))
            Step.appear()
                .expectState(\.destination, .alert(.dataFailedToLoad))
            Step.action(.alertButton(.confirmLoadMockData))
                .expectState(\.standups, [.mock, .designMock, .engineeringMock])
        }

        ComponentTest("load silent failure", state: .init()) {
            Step.setDependency(\.dataManager.load, { _ in
                struct FileNotFound: Error {}
                throw FileNotFound()
            })
            Step.appear()
                .expectState(\.destination, nil)
        }
    }
}
