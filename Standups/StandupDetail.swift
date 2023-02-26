import Clocks
import CustomDump
import Dependencies
import SwiftComponent
import SwiftUI
import SwiftUINavigation
import XCTestDynamicOverlay

struct StandupDetailModel: ComponentModel {

    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.openSettings) var openSettings
    @Dependency(\.speechClient.authorizationStatus) var authorizationStatus
    @Dependency(\.uuid) var uuid

    struct State {
        var standup: Standup
        var alert: AlertState<AlertAction>?
    }

    enum Action {
        case delete
        case edit
        case cancel
        case startMeeting
        case tapMeeting(Meeting)
        case deleteMeetings(IndexSet)
        case alertButton(AlertAction?)
        case doneEditing(Standup)
    }

    enum Input {
        case record(RecordMeetingModel.Output)
    }

    enum Output {
        case confirmDeletion(Standup.ID)
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
            case .cancel:
                store.dismissRoute()
            case .tapMeeting(let meeting):
                store.route(to: Route.meeting, state: .init(meeting: meeting, standup: store.standup))
            case .deleteMeetings(let indices):
                store.standup.meetings.remove(atOffsets: indices)
            case .startMeeting:
                switch authorizationStatus() {
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
                switch action {
                    case .confirmDeletion?:
                        store.output(.confirmDeletion(store.standup.id))
                    case .continueWithoutRecording?:
                        store.route(to: Route.record, state: .init(standup: store.standup))
                    case .openSettings?:
                        await self.openSettings()
                    case nil:
                        break
                }
            case .doneEditing(let standup):
                store.standup = standup
                store.dismissRoute()
                store.output(.standupEdited(standup))
        }
    }

    func handle(input: Input, store: Store) async {
        switch input {
            case .record(.meetingFinished(let transcript)):
                let didCancel = (try? await self.clock.sleep(for: .milliseconds(400))) == nil
                withAnimation(didCancel ? nil : .default) {
                    store.standup.meetings.insert(
                        Meeting(
                            id: Meeting.ID(self.uuid()),
                            date: self.now,
                            transcript: transcript
                        ),
                        at: 0
                    )
                    store.dismissRoute()
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
            case .record: return .push
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
                                model.button(.cancel, "Cancel")
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                model.button(.doneEditing(route.viewModel.state.standup), "Done")
                            }
                        }
                }
            case .record(let route):
                RecordMeetingView(model: route.viewModel)
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
                        model.button(.tapMeeting(meeting)) {
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

struct StandupDetailComponent: PreviewProvider, Component {

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
            Step.binding(\.alert, .none)
        }

        Test("speech denied", stateName: "default") {
            Step.dependency(\.speechClient.authorizationStatus, { .denied })
            Step.action(.startMeeting)
                .expectState(\.alert, .speechRecognitionDenied)
            Step.binding(\.alert, .none)
        }

        Test("open settings", stateName: "default") {
            Step.dependency(\.speechClient.authorizationStatus, { .denied })
            Step.action(.startMeeting)
                .expectState(\.alert, .speechRecognitionDenied)
            let settingsOpened = LockIsolated(false)
            Step.dependency(\.openSettings, { settingsOpened.setValue(true) })
            Step.binding(\.alert, .none)
            Step.action(.alertButton(.openSettings))
                .validateState("settings opened") { _ in
                    settingsOpened.value == true
                }
        }

        Test("continue without recording", state: .init(standup: .mock)) {
            Step.dependency(\.speechClient.authorizationStatus, { .denied })
            Step.action(.startMeeting)
                .expectState(\.alert, .speechRecognitionDenied)
            Step.binding(\.alert, .none)
            Step.action(.alertButton(.continueWithoutRecording))
                .expectRoute(/Model.Route.record, state: .init(standup: .mock))
        }

        Test("speech authorized", stateName: "default") {
            Step.dependency(\.speechClient.authorizationStatus, { .authorized })
            Step.action(.startMeeting)
                .expectRoute(/Model.Route.record, state: .init(standup: .mock))
        }

        let standup = Standup(id: .init(uuidString: "00000000-0000-0000-0000-000000000000")!)
        Test("record transcript", state: .init(standup: standup)) {
            Step.dependency(\.continuousClock, TestClock())
            Step.dependency(\.uuid, .incrementing)
            Step.dependency(\.date, .constant(Date(timeIntervalSince1970: 1_234_567_890)))
            Step.action(.startMeeting)
                .expectRoute(/Model.Route.record, state: .init(standup: standup))
            Step.route(/Model.Route.record) {
                TestStep<RecordMeetingModel>.binding(\.transcript, "Hello")
                TestStep<RecordMeetingModel>.action(.endMeeting)
                TestStep<RecordMeetingModel>.action(.alertButton(.confirmSave))
            }
            // Step.input(.record(.meetingFinished(transcript: "Hello")))
            Step.advanceClock()
                .expectState {
                    $0.standup.meetings = [
                        Meeting(
                            id: Meeting.ID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                            date: Date(timeIntervalSince1970: 1_234_567_890),
                            transcript: "Hello"
                        )
                    ]
                }
        }

        let editedStandup: Standup = {
            var standup = standup
            standup.title = "Engineering"
            return standup
        }()
        Test("edit", state: .init(standup: standup)) {
            Step.action(.edit)
                .expectRoute(/Model.Route.edit, state: .init(standup: standup))
            Step.route(/Model.Route.edit) {
                TestStep<StandupFormModel>.binding(\.standup.title, editedStandup.title)
            }
            Step.action(.doneEditing(editedStandup))
                .expectState(\.standup, editedStandup)
                .expectOutput(.standupEdited(editedStandup))
                .expectState(\.standup, editedStandup)
        }
    }

}
