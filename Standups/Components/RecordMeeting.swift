import Clocks
import Speech
import SwiftComponent
import SwiftUI
import SwiftUINavigation
import XCTestDynamicOverlay

@ComponentModel
struct RecordMeetingModel {

    struct State {
        var standup: Standup
        var alert: AlertState<AlertAction>?
        var secondsElapsed = 0
        var speakerIndex = 0
        var transcript = ""

        var durationRemaining: Duration {
            standup.duration - .seconds(secondsElapsed)
        }

        var isAlertOpen: Bool {
            alert != nil
        }
    }

    enum Output {
        case dismiss
        case meetingFinished(transcript: String)
    }

    enum AlertAction {
        case confirmSave
        case confirmDiscard
    }

    enum Action {
        case nextSpeaker
        case endMeeting
        case alertButton(AlertAction?)
    }

    func appear() async {

        dependencies.soundEffectClient.load("ding.wav")

        let authorization =
        await dependencies.speechClient.authorizationStatus() == .notDetermined
        ? dependencies.speechClient.requestAuthorization()
        : dependencies.speechClient.authorizationStatus()

        await withTaskGroup(of: Void.self) { group in
            if authorization == .authorized {
                group.addTask {
                    await self.startSpeechRecognition()
                }
            }
            group.addTask {
                await self.startTimer()
            }
        }
    }

    func handle(action: Action) async {
        switch action {
        case .nextSpeaker:
            guard state.speakerIndex < state.standup.attendees.count - 1
            else {
                state.alert = .endMeeting(isDiscardable: false)
                return
            }

            dependencies.soundEffectClient.play()
            state.speakerIndex += 1
            state.secondsElapsed = state.speakerIndex * Int(state.standup.durationPerAttendee.components.seconds)
        case .endMeeting:
            state.alert = .endMeeting(isDiscardable: true)
        case .alertButton(let action):
            switch action {
            case .confirmSave?:
                finishMeeting()
            case .confirmDiscard?:
                output(.dismiss)
            case .none: break
            }
            state.alert = nil
        }
    }

    private func finishMeeting() {
        output(.meetingFinished(transcript: state.transcript))
    }

    private func startSpeechRecognition() async {
        do {
            let speechTask = await dependencies.speechClient.startTask(SFSpeechAudioBufferRecognitionRequest())
            for try await result in speechTask {
                state.transcript = result.bestTranscription.formattedString
            }
        } catch {
            if !state.transcript.isEmpty {
                state.transcript += " ❌"
            }
            state.alert = .speechRecognizerFailed
        }
    }

    private func startTimer() async {
        for await _ in dependencies.continuousClock.timer(interval: .seconds(1)) where !state.isAlertOpen {

            state.secondsElapsed += 1

            let secondsPerAttendee = Int(state.standup.durationPerAttendee.components.seconds)
            if state.secondsElapsed.isMultiple(of: secondsPerAttendee) {
                if state.speakerIndex == state.standup.attendees.count - 1 {
                    finishMeeting()
                    break
                }
                state.speakerIndex += 1
                dependencies.soundEffectClient.play()
            }
        }
    }
}

extension AlertState where Action == RecordMeetingModel.AlertAction {
    static func endMeeting(isDiscardable: Bool) -> Self {
        Self {
            TextState("End meeting?")
        } actions: {
            ButtonState(action: .confirmSave) {
                TextState("Save and end")
            }
            if isDiscardable {
                ButtonState(role: .destructive, action: .confirmDiscard) {
                    TextState("Discard")
                }
            }
            ButtonState(role: .cancel) {
                TextState("Resume")
            }
        } message: {
            TextState("You are ending the meeting early. What would you like to do?")
        }
    }

    static let speechRecognizerFailed = Self {
        TextState("Speech recognition failure")
    } actions: {
        ButtonState(role: .cancel) {
            TextState("Continue meeting")
        }
        ButtonState(role: .destructive, action: .confirmDiscard) {
            TextState("Discard meeting")
        }
    } message: {
        TextState(
      """
      The speech recognizer has failed for some reason and so your meeting will no longer be \
      recorded. What do you want to do?
      """)
    }
}

struct RecordMeetingView: ComponentView {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var model: ViewModel<RecordMeetingModel>

    var view: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(model.standup.theme.mainColor)

            VStack {
                MeetingHeaderView(
                    secondsElapsed: model.secondsElapsed,
                    durationRemaining: model.durationRemaining,
                    theme: model.standup.theme
                )
                MeetingTimerView(
                    standup: model.standup,
                    speakerIndex: model.speakerIndex
                )
                MeetingFooterView(
                    standup: model.standup,
                    nextButtonTapped: { model.send(.nextSpeaker) },
                    speakerIndex: model.speakerIndex
                )
            }
        }
        .padding()
        .foregroundColor(model.standup.theme.accentColor)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                model.button(.endMeeting, "End meeting")
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert(unwrapping: model.binding(\.alert)) { action in
            model.send(.alertButton(action))
        }
    }
}

struct MeetingHeaderView: View {
    let secondsElapsed: Int
    let durationRemaining: Duration
    let theme: Theme

    var body: some View {
        VStack {
            ProgressView(value: self.progress)
                .progressViewStyle(MeetingProgressViewStyle(theme: self.theme))
            HStack {
                VStack(alignment: .leading) {
                    Text("Time Elapsed")
                        .font(.caption)
                    Label(
                        Duration.seconds(self.secondsElapsed).formatted(.units()),
                        systemImage: "hourglass.bottomhalf.fill"
                    )
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Time Remaining")
                        .font(.caption)
                    Label(self.durationRemaining.formatted(.units()), systemImage: "hourglass.tophalf.fill")
                        .font(.body.monospacedDigit())
                        .labelStyle(.trailingIcon)
                }
            }
        }
        .padding([.top, .horizontal])
    }

    private var totalDuration: Duration {
        .seconds(self.secondsElapsed) + self.durationRemaining
    }

    private var progress: Double {
        guard totalDuration > .seconds(0) else { return 0 }
        return Double(self.secondsElapsed) / Double(self.totalDuration.components.seconds)
    }
}

struct MeetingProgressViewStyle: ProgressViewStyle {
    var theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10.0)
                .fill(theme.accentColor)
                .frame(height: 20.0)

            ProgressView(configuration)
                .tint(theme.mainColor)
                .frame(height: 12.0)
                .padding(.horizontal)
        }
    }
}

struct MeetingTimerView: View {
    let standup: Standup
    let speakerIndex: Int

    var body: some View {
        Circle()
            .strokeBorder(lineWidth: 24)
            .overlay {
                VStack {
                    Group {
                        if self.speakerIndex < self.standup.attendees.count {
                            Text(self.standup.attendees[self.speakerIndex].name)
                        } else {
                            Text("Someone")
                        }
                    }
                    .font(.title)
                    Text("is speaking")
                    Image(systemName: "mic.fill")
                        .font(.largeTitle)
                        .padding(.top)
                }
                .foregroundStyle(self.standup.theme.accentColor)
            }
            .overlay {
                ForEach(Array(self.standup.attendees.enumerated()), id: \.element.id) { index, attendee in
                    if index < self.speakerIndex + 1 {
                        SpeakerArc(totalSpeakers: self.standup.attendees.count, speakerIndex: index)
                            .rotation(Angle(degrees: -90))
                            .stroke(self.standup.theme.mainColor, lineWidth: 12)
                    }
                }
            }
            .padding(.horizontal)
    }
}

struct SpeakerArc: Shape {
    let totalSpeakers: Int
    let speakerIndex: Int

    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.size.width, rect.size.height) - 24.0
        let radius = diameter / 2.0
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: self.startAngle,
                endAngle: self.endAngle,
                clockwise: false
            )
        }
    }

    private var degreesPerSpeaker: Double {
        360.0 / Double(self.totalSpeakers)
    }
    private var startAngle: Angle {
        Angle(degrees: self.degreesPerSpeaker * Double(self.speakerIndex) + 1.0)
    }
    private var endAngle: Angle {
        Angle(degrees: self.startAngle.degrees + self.degreesPerSpeaker - 1.0)
    }
}

struct MeetingFooterView: View {
    let standup: Standup
    var nextButtonTapped: () -> Void
    let speakerIndex: Int

    var body: some View {
        VStack {
            HStack {
                if self.speakerIndex < self.standup.attendees.count - 1 {
                    Text("Speaker \(self.speakerIndex + 1) of \(self.standup.attendees.count)")
                } else {
                    Text("No more speakers.")
                }
                Spacer()
                Button(action: self.nextButtonTapped) {
                    Image(systemName: "forward.fill")
                }
            }
        }
        .padding([.bottom, .horizontal])
    }
}

struct RecordMeetingComponent: Component, PreviewProvider {

    typealias Model = RecordMeetingModel

    static func view(model: ViewModel<RecordMeetingModel>) -> some View {
        NavigationStack { RecordMeetingView(model: model) }
    }

    static var preview = PreviewModel(state: .init(standup: Standup(
        id: Standup.ID(),
        attendees: [
            Attendee(id: Attendee.ID()),
            Attendee(id: Attendee.ID()),
        ],
        duration: .seconds(2)
    )))

    static var tests: Tests {
        Test("timer") {
            let soundEffectPlayCount = LockIsolated(0)
            Step.dependency(\.speechClient.authorizationStatus, { .denied })
            Step.dependency(\.continuousClock, TestClock())
            Step.dependency(\.soundEffectClient.play, { soundEffectPlayCount.withValue { $0 += 1 } })
            Step.appear(await: false)
                .expectState(\.secondsElapsed, 0)
                .expectState(\.speakerIndex, 0)
                .validateState("sound played") { _ in
                    soundEffectPlayCount.value == 0
                }
            Step.advanceClock()
                .expectState(\.secondsElapsed, 1)
                .expectState(\.speakerIndex, 1)
                .validateState("sound played") { _ in
                    soundEffectPlayCount.value == 1
                }
            Step.advanceClock()
                .expectState(\.secondsElapsed, 2)
                .expectOutput(.meetingFinished(transcript: ""))
        }

        Test("record transcript") {
            Step.dependency(\.speechClient, .string("hello"))
            Step.dependency(\.continuousClock, TestClock())
            Step.appear(await: false)
            Step.advanceClock(.seconds(1))
                .expectState(\.secondsElapsed, 1)
                .expectState(\.speakerIndex, 1)
                .expectState(\.transcript, "hello")
            Step.advanceClock(.seconds(1))
                .expectState(\.secondsElapsed, 2)
                .expectOutput(.meetingFinished(transcript: "hello"))
        }

        Test("end meeting") {
            Step.dependency(\.speechClient.authorizationStatus, { .denied })
            Step.dependency(\.continuousClock, TestClock())
            Step.appear(await: false)
            Step.action(.endMeeting)
                .expectState(\.alert, .endMeeting(isDiscardable: true))
            Step.advanceClock(.seconds(10))
                .expectState {
                    // has paused
                    $0.secondsElapsed = 0
                    $0.speakerIndex = 0
                }
            Step.branch("save") {
                Step.action(.alertButton(.confirmSave))
                    .expectOutput(.meetingFinished(transcript: ""))
                    .expectState(\.alert, .none)
            }
            Step.branch("discard") {
                Step.action(.alertButton(.confirmDiscard))
                    .expectOutput(.dismiss)
            }
        }

        Test("next speaker") {
            let soundEffectPlayCount = LockIsolated(0)
            Step.dependency(\.speechClient, .string("hello"))
            Step.dependency(\.continuousClock, TestClock())
            Step.dependency(\.soundEffectClient.play, { soundEffectPlayCount.withValue { $0 += 1 } })
            Step.appear(await: false)
                .expectState(\.speakerIndex, 0)
                .expectState(\.secondsElapsed, 0)
                .validateState("sound played") { _ in
                    soundEffectPlayCount.value == 0
                }
            Step.action(.nextSpeaker)
                .expectState(\.speakerIndex, 1)
                .expectState(\.secondsElapsed, 1)
                .validateState("sound played") { _ in
                    soundEffectPlayCount.value == 1
                }
            Step.action(.nextSpeaker)
                .expectState(\.alert, .endMeeting(isDiscardable: false))
            Step.advanceClock()
                .expectState(\.speakerIndex, 1)
                .expectState(\.secondsElapsed, 1)
                .validateState("sound played") { _ in
                    // no sound played
                    soundEffectPlayCount.value == 1
                }
            Step.action(.alertButton(.confirmSave))
                .expectOutput(.meetingFinished(transcript: "hello"))
        }

        Test("speech failure", assertions: []) {
            Step.dependency(\.speechClient, .string("I completed the project", fail: true))
            Step.dependency(\.continuousClock, TestClock())
            Step.appear(await: false)
            Step.advanceClock()
                .expectState(\.alert, .speechRecognizerFailed)
                .expectState(\.transcript, "I completed the project ❌")
            Step.branch("continue") {
                Step.action(.alertButton(.none))
                    .expectState(\.alert, .none)
                Step.advanceClock(.seconds(60))
                    .expectOutput(.meetingFinished(transcript: "I completed the project ❌"))
            }
            Step.branch("discard") {
                Step.action(.alertButton(.confirmDiscard))
                    .expectState(\.alert, .none)
                    .expectOutput(.dismiss)
            }
        }
    }
}
