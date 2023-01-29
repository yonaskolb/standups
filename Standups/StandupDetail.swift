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
        var destination: Destination?
        var isDismissed = false
        var standup: Standup
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

    enum Destination {
        case alert(AlertState<AlertAction>)
        case edit(StandupFormModel.State)
        case meeting(Meeting)
        case record(RecordMeetingModel.State)
    }
    enum AlertAction {
        case confirmDeletion
        case continueWithoutRecording
        case openSettings
    }

    func handle(action: Action, model: Model) async {
        switch action {
            case .delete:
                model.destination = .alert(.deleteStandup)
            case .edit:
                model.destination = .edit(.init(standup: model.standup))
            case .cancel:
                model.destination = nil
            case .tapMeeting(let meeting):
                model.destination = .meeting(meeting)
            case .deleteMeetings(let indices):
                model.standup.meetings.remove(atOffsets: indices)
            case .startMeeting:
                switch authorizationStatus() {
                    case .notDetermined, .authorized:
                        model.destination = .record(.init(standup: model.standup))
                    case .denied:
                        model.destination = .alert(.speechRecognitionDenied)
                    case .restricted:
                        model.destination = .alert(.speechRecognitionRestricted)
                    @unknown default:
                        break
                }
            case .alertButton(let action):
                switch action {
                    case .confirmDeletion?:
                        model.output(.confirmDeletion(model.standup.id))
                        model.isDismissed = true
                    case .continueWithoutRecording?:
                        model.destination = .record(.init(standup: model.standup))
                    case .openSettings?:
                        await self.openSettings()
                    case nil:
                        break
                }
            case .doneEditing(let standup):
                model.standup = standup
                model.destination = nil
                model.output(.standupEdited(standup))
        }
    }

    func handle(input: Input, model: Model) async {
        switch input {
            case .record(.meetingFinished(let transcript)):
                let didCancel = (try? await self.clock.sleep(for: .milliseconds(400))) == nil
                withAnimation(didCancel ? nil : .default) {
                    model.standup.meetings.insert(
                        Meeting(
                            id: Meeting.ID(self.uuid()),
                            date: self.now,
                            transcript: transcript
                        ),
                        at: 0
                    )
                    model.destination = nil
                }
        }
    }
}

struct StandupDetailView: ComponentView {

    @Environment(\.dismiss) var dismiss
    @ObservedObject var model: ViewModel<StandupDetailModel>

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
        .navigationDestination(
            unwrapping: model.binding(\.destination),
            case: /StandupDetailModel.Destination.meeting
        ) { $meeting in
            MeetingView(meeting: meeting, standup: model.standup)
        }
        .navigationDestination(
            unwrapping: model.binding(\.destination),
            case: /StandupDetailModel.Destination.record
        ) { $state in
            RecordMeetingView(model: model.scope(state: state, output: Model.Input.record))
        }
        .alert(
            unwrapping: model.binding(\.destination),
            case: /StandupDetailModel.Destination.alert
        ) { action in
            model.send(.alertButton(action))
        }
        .sheet(
            unwrapping: model.binding(\.destination),
            case: /StandupDetailModel.Destination.edit
        ) { $state in
            NavigationStack {
                StandupFormView(model: model.scope(state: $state))
                    .navigationTitle(model.standup.title)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            model.button(.cancel, "Cancel")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            model.button(.doneEditing(state.standup), "Done")
                        }
                    }
            }
        }
        .onChange(of: model.isDismissed) { _ in self.dismiss() }
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

struct MeetingView: View {
    let meeting: Meeting
    let standup: Standup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Divider()
                    .padding(.bottom)
                Text("Attendees")
                    .font(.headline)
                ForEach(self.standup.attendees) { attendee in
                    Text(attendee.name)
                }
                Text("Transcript")
                    .font(.headline)
                    .padding(.top)
                Text(self.meeting.transcript)
            }
        }
        .navigationTitle(Text(self.meeting.date, style: .date))
        .padding()
    }
}

struct StandupDetailFeature: PreviewProvider, ComponentFeature {

    typealias Model = StandupDetailModel

    static func createView(model: ViewModel<StandupDetailModel>) -> some View {
        NavigationView {
            StandupDetailView(model: model)
        }
    }

    static var states: [ComponentState] {
        ComponentState("default") {
            .init(standup: .mock)
        }
        ComponentState("speech denied") {
            .init(destination: .alert(.speechRecognitionDenied), standup: .mock)
        }
        ComponentState("speech restricted") {
            .init(destination: .alert(.speechRecognitionRestricted), standup: .mock)
        }
    }

    static var tests: [ComponentTest] {
        ComponentTest("speech restricted", stateName: "default") {
            Step.setDependency(\.speechClient.authorizationStatus, { .restricted })
            Step.action(.startMeeting)
                .expectState(\.destination, .alert(.speechRecognitionRestricted))
            Step.setBinding(\.destination, nil)
        }

        ComponentTest("speech denied", stateName: "default") {
            Step.setDependency(\.speechClient.authorizationStatus, { .denied })
            Step.action(.startMeeting)
                .expectState(\.destination, .alert(.speechRecognitionDenied))
            Step.setBinding(\.destination, nil)
        }

        ComponentTest("open settings", stateName: "default") {
            Step.setDependency(\.speechClient.authorizationStatus, { .denied })
            Step.action(.startMeeting)
                .expectState(\.destination, .alert(.speechRecognitionDenied))
            let settingsOpened = LockIsolated(false)
            Step.setDependency(\.openSettings, { settingsOpened.setValue(true) })
            Step.setBinding(\.destination, nil)
            Step.action(.alertButton(.openSettings))
                .validateState("settings opened") { _ in
                    settingsOpened.value == true
                }
        }

        ComponentTest("continue without recording", state: .init(standup: .mock)) {
            Step.setDependency(\.speechClient.authorizationStatus, { .denied })
            Step.action(.startMeeting)
                .expectState(\.destination, .alert(.speechRecognitionDenied))
            Step.setBinding(\.destination, nil)
            Step.action(.alertButton(.continueWithoutRecording))
                .validateState("is recording") { state in
                    guard case let .record(state) = state.destination else { return false}
                    return state.standup == .mock
                }
        }

        ComponentTest("speech authorized", stateName: "default") {
            Step.setDependency(\.speechClient.authorizationStatus, { .authorized })
            Step.action(.startMeeting)
                .validateState("is recording") { state in
                    guard case let .record(model) = state.destination else { return false}
                    return model.standup == .mock
                }
        }

        let standup = Standup(id: .init(uuidString: "00000000-0000-0000-0000-000000000000")!)
        ComponentTest("record transcript", state: .init(standup: standup)) {
            Step.setDependency(\.uuid, .incrementing)
            Step.setDependency(\.date, .constant(Date(timeIntervalSince1970: 1_234_567_890)))
            Step.action(.startMeeting)
                .expectState(\.destination, .record(.init(standup: standup)))
            Step.input(.record(.meetingFinished(transcript: "Hello")))
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
        ComponentTest("edit", state: .init(standup: standup)) {
            Step.action(.edit)
                .expectState(\.destination, .edit(.init(standup: standup)))
            Step.setBinding(\.destination, .edit(.init(standup: editedStandup)))
            Step.action(.doneEditing(editedStandup))
                .expectState(\.standup, editedStandup)
                .expectOutput(.standupEdited(editedStandup))
        }
    }

}
