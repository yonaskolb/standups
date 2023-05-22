import Clocks
import Dependencies
import SwiftComponent
import SwiftUI
import SwiftUINavigation
import XCTestDynamicOverlay

struct StandupDetailModel: ComponentModel {

    struct State {
        var standup: Standup
        var alert: AlertState<AlertAction>?
    }

    enum Action {
        case delete
        case edit
        case cancelEdit
        case completeEdit(Standup)
        case startMeeting
        case selectMeeting(Meeting)
        case deleteMeetings(IndexSet)
        case alertButton(AlertAction?)
    }

    enum Input {
        case record(RecordMeetingModel.Output)
    }

    enum Output {
        case standupDeleted(Standup.ID)
        case standupEdited(Standup)
    }

    enum Route {
        case edit(ComponentRoute<StandupFormModel>)
        case meeting(ComponentRoute<MeetingModel>)
        case record(ComponentRoute<RecordMeetingModel>)
    }

    enum AlertAction {
        case confirmDeletion
        case continueWithoutRecording
        case openSettings
    }

    func connect(route: Route, store: Store) -> Connection {
        switch route {
            case .record(let route):
                return store.connect(route, output: Input.record)
            case .edit(let route):
                return store.connect(route)
            case .meeting(let route):
                return store.connect(route)
        }
    }

    func handle(action: Action, store: Store) async {
        switch action {
            case .delete:
                store.alert = .deleteStandup
            case .edit:
                store.route(to: Route.edit, state: .init(standup: store.standup))
            case .cancelEdit:
                store.dismissRoute()
            case .selectMeeting(let meeting):
                store.route(to: Route.meeting, state: .init(meeting: meeting, standup: store.standup))
            case .deleteMeetings(let indices):
                store.standup.meetings.remove(atOffsets: indices)
            case .startMeeting:
                switch store.dependencies.speechClient.authorizationStatus() {
                    case .notDetermined, .authorized:
                        store.route(to: Route.record, state: .init(standup: store.standup))
                    case .denied:
                        store.alert = .speechRecognitionDenied
                    case .restricted:
                        store.alert = .speechRecognitionRestricted
                    @unknown default:
                        break
                }
            case .alertButton(let action):
                store.alert = nil
                switch action {
                    case .confirmDeletion?:
                        store.output(.standupDeleted(store.standup.id))
                    case .continueWithoutRecording?:
                        store.route(to: Route.record, state: .init(standup: store.standup))
                    case .openSettings?:
                        await store.dependencies.openSettings()
                    case nil:
                        break
                }
            case .completeEdit(let standup):
                store.standup = standup
                store.dismissRoute()
                store.output(.standupEdited(standup))
        }
    }

    func handle(input: Input, store: Store) async {
        switch input {
            case .record(.meetingFinished(let transcript)):
                store.dismissRoute()
                let didCancel = (try? await store.dependencies.continuousClock.sleep(for: .milliseconds(400))) == nil
                withAnimation(didCancel ? nil : .default) {
                    store.standup.meetings.insert(
                        Meeting(
                            id: Meeting.ID(store.dependencies.uuid()),
                            date: store.dependencies.date(),
                            transcript: transcript
                        ),
                        at: 0
                    )
                }
            case .record(.dismiss):
                store.dismissRoute()
        }
    }
}

struct StandupDetailView: ComponentView {

    @ObservedObject var model: ViewModel<StandupDetailModel>

    func presentation(for route: StandupDetailModel.Route) -> Presentation {
        switch route {
            case .edit: return .sheet
            case .meeting: return .push
            case .record: return .sheet
        }
    }

    func routeView(_ route: StandupDetailModel.Route) -> some View {
        switch route {
            case .edit(let route):
                NavigationView {
                    StandupFormView(model: route.viewModel)
                        .navigationTitle(model.standup.title)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                model.button(.cancelEdit, "Cancel")
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                model.button(.completeEdit(route.viewModel.state.standup), "Done")
                            }
                        }
                }
            case .record(let route):
                NavigationView {
                    RecordMeetingView(model: route.viewModel)
                }
            case .meeting(let route):
                MeetingView(model: route.viewModel)
        }
    }

    var view: some View {
        List {
            Section {
                model.button(.startMeeting) {
                    Label("Start Meeting", systemImage: "timer")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }
                HStack {
                    Label("Length", systemImage: "clock")
                    Spacer()
                    Text(model.standup.duration.formatted(.units()))
                }

                HStack {
                    Label("Theme", systemImage: "paintpalette")
                    Spacer()
                    Text(model.standup.theme.name)
                        .padding(4)
                        .foregroundColor(model.standup.theme.accentColor)
                        .background(model.standup.theme.mainColor)
                        .cornerRadius(4)
                }
            } header: {
                Text("Standup Info")
            }

            if !model.standup.meetings.isEmpty {
                Section {
                    ForEach(model.standup.meetings) { meeting in
                        model.button(.selectMeeting(meeting)) {
                            HStack {
                                Image(systemName: "calendar")
                                Text(meeting.date, style: .date)
                                Text(meeting.date, style: .time)
                            }
                        }
                    }
                    .onDelete { indices in
                        model.send(.deleteMeetings(indices))
                    }
                } header: {
                    Text("Past meetings")
                }
            }

            Section {
                ForEach(model.standup.attendees) { attendee in
                    Label(attendee.name, systemImage: "person")
                }
            } header: {
                Text("Attendees")
            }

            Section {
                model.button(.delete, "Delete")
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(model.standup.title)
        .toolbar {
            model.button(.edit, "Edit")
        }
        .alert(unwrapping: model.binding(\.alert)) { action in
            model.send(.alertButton(action))
        }
    }
}

extension AlertState where Action == StandupDetailModel.AlertAction {
    static let deleteStandup = Self {
        TextState("Delete?")
    } actions: {
        ButtonState(role: .destructive, action: .confirmDeletion) {
            TextState("Yes")
        }
        ButtonState(role: .cancel) {
            TextState("Nevermind")
        }
    } message: {
        TextState("Are you sure you want to delete this meeting?")
    }

    static let speechRecognitionDenied = Self {
        TextState("Speech recognition denied")
    } actions: {
        ButtonState(action: .continueWithoutRecording) {
            TextState("Continue without recording")
        }
        ButtonState(action: .openSettings) {
            TextState("Open settings")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("""
      You previously denied speech recognition and so your meeting meeting will not be \
      recorded. You can enable speech recognition in settings, or you can continue without \
      recording.
      """)
    }

    static let speechRecognitionRestricted = Self {
        TextState("Speech recognition restricted")
    } actions: {
        ButtonState(action: .continueWithoutRecording) {
            TextState("Continue without recording")
        }
        ButtonState(role: .cancel) {
            TextState("Cancel")
        }
    } message: {
        TextState("""
      Your device does not support speech recognition and so your meeting will not be recorded.
      """)
    }
}

struct StandupDetailComponent: Component, PreviewProvider {

    typealias Model = StandupDetailModel

    static func view(model: ViewModel<StandupDetailModel>) -> some View {
        NavigationView {
            StandupDetailView(model: model)
        }
    }

    static var states: States {
        State("default") {
            .init(standup: .mock)
        }
        State("empty") {
            .init(standup: .init(id: "0"))
        }
        State("speech denied") {
            .init(standup: .mock, alert: .speechRecognitionDenied)
        }
        State("speech restricted") {
            .init(standup: .mock, alert: .speechRecognitionRestricted)
        }
    }

    static var tests: Tests {
        Test("speech restricted", stateName: "default") {
            Step.dependency(\.speechClient.authorizationStatus, { .restricted })
            Step.action(.startMeeting)
                .expectState(\.alert, .speechRecognitionRestricted)
            Step.branch("cancel") {
                Step.binding(\.alert, .none)
                    .expectState(\.alert, .none)
            }
            Step.branch("continue") {
                Step.action(.alertButton(.continueWithoutRecording))
                    .expectRoute(/Model.Route.record, state: .init(standup: .mock))
                    .expectState(\.alert, .none)
            }
        }

        Test("speech denied", stateName: "default") {
            Step.dependency(\.speechClient.authorizationStatus, { .denied })
            Step.action(.startMeeting)
                .expectState(\.alert, .speechRecognitionDenied)
            Step.branch("continue") {
                Step.action(.alertButton(.continueWithoutRecording))
                    .expectState(\.alert, .none)
                    .expectRoute(/Model.Route.record, state: .init(standup: .mock))
                Step.input(.record(.dismiss))
                    .expectEmptyRoute()
            }
            Step.branch("open settings") {
                let settingsOpened = LockIsolated(false)
                Step.dependency(\.openSettings, { settingsOpened.setValue(true) })
                Step.action(.alertButton(.openSettings))
                    .validateState("settings opened") { _ in
                        settingsOpened.value == true
                    }
                    .expectState(\.alert, .none)
            }
            Step.branch("cancel") {
                Step.binding(\.alert, .none)
                    .expectState(\.alert, .none)
            }
            Step.binding(\.alert, .none)
        }

        Test("speech authorized", stateName: "default") {
            Step.dependency(\.speechClient.authorizationStatus, { .authorized })
            Step.action(.startMeeting)
                .expectRoute(/Model.Route.record, state: .init(standup: .mock))
        }

        let standup = Standup(id: "0")
        Test("record transcript", state: .init(standup: standup)) {
            Step.dependency(\.continuousClock, TestClock())
            Step.dependency(\.uuid, .incrementing)
            Step.dependency(\.date, .constant(Date(timeIntervalSince1970: 1_234_567_890)))
            Step.dependency(\.speechClient, .string("Hello"))
            Step.action(.startMeeting)
                .expectRoute(/Model.Route.record, state: .init(standup: standup))
            Step.route(/Model.Route.record, output: .meetingFinished(transcript: "Hello"))
                .expectEmptyRoute()
            Step.advanceClock()
                .expectState {
                    $0.standup.meetings = [
                        Meeting(
                            id: "0",
                            date: Date(timeIntervalSince1970: 1_234_567_890),
                            transcript: "Hello"
                        )
                    ]
                }
        }

        let editedStandup = Standup(id: "0", title: "Engineering")
        Test("edit", state: .init(standup: standup)) {
            Step.action(.edit)
                .expectRoute(/Model.Route.edit, state: .init(standup: standup))
            Step.branch("cancel") {
                Step.action(.cancelEdit)
                    .expectEmptyRoute()
            }
            Step.route(/Model.Route.edit) {
                Step.binding(\.standup.title, editedStandup.title)
            }
            Step.action(.completeEdit(editedStandup))
                .expectState(\.standup, editedStandup)
                .expectOutput(.standupEdited(editedStandup))
                .expectEmptyRoute()
        }

        Test("delete", stateName: "default") {
            Step.action(.delete)
                .expectState(\.alert, .deleteStandup)
            Step.action(.alertButton(.confirmDeletion))
                .expectState(\.alert, nil)
                .expectOutput(.standupDeleted(Standup.mock.id))
        }

        Test("delete meetings", stateName: "default") {
            Step.action(.deleteMeetings(.init(integer: 0)))
                .expectState(\.standup.meetings, [])
        }

        Test("select meeting", stateName: "default") {
            Step.action(.selectMeeting(.mock))
                .expectRoute(/Model.Route.meeting, state: .init(meeting: .mock, standup: .mock))
        }
    }

}
