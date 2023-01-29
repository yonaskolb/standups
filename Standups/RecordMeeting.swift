import Clocks
import Dependencies
import Speech
import SwiftComponent
import SwiftUI
import SwiftUINavigation
import XCTestDynamicOverlay

struct RecordMeetingModel: ComponentModel {
    
    @Dependency(\.continuousClock) var clock
    @Dependency(\.soundEffectClient) var soundEffectClient
    @Dependency(\.speechClient) var speechClient

    struct State {
        var standup: Standup
        var destination: Destination?
        var isDismissed = false
        var secondsElapsed = 0
        var speakerIndex = 0
        fileprivate var transcript = ""

        var durationRemaining: Duration {
            standup.duration - .seconds(secondsElapsed)
        }

        var isAlertOpen: Bool {
            switch destination {
                case .alert:
                    return true
                case .none:
                    return false
            }
        }

        init(
            destination: Destination? = nil,
            standup: Standup
        ) {
            self.destination = destination
            self.standup = standup
        }
    }

    enum Output {
        case meetingFinished(transcript: String)
    }

    enum Destination {
        case alert(AlertState<AlertAction>)
    }

    enum AlertAction {
        case confirmSave
        case confirmDiscard
    }

    enum Action {
        case nextSpeaker
        case endMeeting
        case alertButton(AlertAction?)
        case finishMeeting

    }

    func appear(model: Model) async {

        self.soundEffectClient.load("ding.wav")

        let authorization =
        await self.speechClient.authorizationStatus() == .notDetermined
        ? self.speechClient.requestAuthorization()
        : self.speechClient.authorizationStatus()

        await withTaskGroup(of: Void.self) { group in
            if authorization == .authorized {
                group.addTask {
                    await self.startSpeechRecognition(model: model)
                }
            }
            group.addTask {
                await self.startTimer(model: model)
            }
        }
    }

    func handle(action: Action, model: Model) async {
        switch action {
            case .nextSpeaker:
                guard model.speakerIndex < model.standup.attendees.count - 1
                else {
                    model.destination = .alert(.endMeeting(isDiscardable: false))
                    return
                }

                self.soundEffectClient.play()
                model.speakerIndex += 1
                model.secondsElapsed = model.speakerIndex * Int(model.standup.durationPerAttendee.components.seconds)
            case .endMeeting:
                model.destination = .alert(.endMeeting(isDiscardable: true))
            case .alertButton(let action):
                switch action {
                    case .confirmSave?:
                        finishMeeting(model: model)
                    case .confirmDiscard?:
                        model.isDismissed = true
                    case .none: break
                }
                model.destination = nil
            case .finishMeeting:
                finishMeeting(model: model)
        }
    }

    private func finishMeeting(model: Model) {
        model.isDismissed = true
        model.output(.meetingFinished(transcript: model.transcript))
    }

    private func startSpeechRecognition(model: Model) async {
        do {
            let speechTask = await self.speechClient.startTask(SFSpeechAudioBufferRecognitionRequest())
            for try await result in speechTask {
                model.transcript = result.bestTranscription.formattedString
            }
        } catch {
            if !model.transcript.isEmpty {
                model.transcript += " ❌"
            }
            model.destination = .alert(.speechRecognizerFailed)
        }
    }

    private func startTimer(model: Model) async {
        for await _ in self.clock.timer(interval: .seconds(1)) where !model.state.isAlertOpen {
            guard !model.isDismissed
            else { break }

            model.secondsElapsed += 1

            let secondsPerAttendee = Int(model.standup.durationPerAttendee.components.seconds)
            if model.secondsElapsed.isMultiple(of: secondsPerAttendee) {
                if model.speakerIndex == model.standup.attendees.count - 1 {
                    finishMeeting(model: model)
                    break
                }
                model.speakerIndex += 1
                self.soundEffectClient.play()
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
        .alert(
            unwrapping: model.binding(\.destination),
            case: /RecordMeetingModel.Destination.alert
        ) { action in
            model.send(.alertButton(action))
        }
        .onChange(of: model.isDismissed) { _ in self.dismiss() }
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

struct RecordMeetingFeature: PreviewProvider, ComponentFeature {

    typealias Model = RecordMeetingModel

    static func createView(model: ViewModel<RecordMeetingModel>) -> some View {
        NavigationView { RecordMeetingView(model: model) }
    }

    static var states: [ComponentState] {
        ComponentState("default") {
            .init(standup: .mock)
        }
        ComponentState("quick") {
            .init(standup: Standup(
                id: Standup.ID(),
                attendees: [
                    Attendee(id: Attendee.ID()),
                    Attendee(id: Attendee.ID()),
                ],
                duration: .seconds(3)
            ))
        }
        ComponentState("failed speech") {
            .init(destination: .alert(.speechRecognizerFailed), standup: .mock)
        }
    }

    static var tests: [ComponentTest] {
        ComponentTest("timer", stateName: "quick") {
            let soundEffectPlayCount = LockIsolated(0)
            Step.setDependency(\.speechClient.authorizationStatus, { .denied })
            Step.setDependency(\.soundEffectClient, .noop)
            Step.setDependency(\.continuousClock, TestClock())
            Step.setDependency(\.soundEffectClient.play, { soundEffectPlayCount.withValue { $0 += 1 } })
            Step.appear(await: false)
                .expectState {
                    $0.speakerIndex = 0
                    $0.secondsElapsed = 0
                }
                .validateState("sound played") { _ in
                    soundEffectPlayCount.value == 0
                }
            Step.advanceClock()
                .expectState {
                    $0.speakerIndex = 1
                    $0.secondsElapsed = 1
                }
                .validateState("sound played") { _ in
                    soundEffectPlayCount.value == 1
                }
            Step.advanceClock()
                .expectOutput(.meetingFinished(transcript: ""))
        }

        ComponentTest("record transcript", stateName: "default") {
            Step.setDependency(\.speechClient.authorizationStatus, { .authorized })
            Step.setDependency(\.continuousClock, ImmediateClock())
            Step.setDependency(\.soundEffectClient, .noop)
            Step.setDependency(\.speechClient.startTask, { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(
                        SpeechRecognitionResult(
                            bestTranscription: Transcription(formattedString: "I completed the project"),
                            isFinal: true
                        )
                    )
                    continuation.finish()
                }}
            )
            Step.appear()
                .expectState {
                    $0.isDismissed = true
                }
                .expectOutput(.meetingFinished(transcript: "I completed the project"))
        }

        ComponentTest("end meeting save", stateName: "default") {
            Step.setDependency(\.speechClient.authorizationStatus, { .denied })
            Step.setDependency(\.soundEffectClient, .noop)
            Step.setDependency(\.continuousClock, TestClock())
            Step.appear(await: false)
            Step.action(.endMeeting)
                .expectState {
                    $0.destination = .alert(.endMeeting(isDiscardable: true))
                }
            Step.advanceClock(.seconds(10))
                .expectState {
                    // has paused
                    $0.secondsElapsed = 0
                    $0.speakerIndex = 0
                }
            Step.action(.alertButton(.confirmSave))
                .expectOutput(.meetingFinished(transcript: ""))
        }

        ComponentTest("end meeting discard", stateName: "default") {
            Step.action(.endMeeting)
                .expectState {
                    $0.destination = .alert(.endMeeting(isDiscardable: true))
                }
            Step.action(.alertButton(.confirmDiscard))
                .expectState {
                    $0.isDismissed = true
                }
        }

        ComponentTest("next speaker", stateName: "quick") {
            let soundEffectPlayCount = LockIsolated(0)
            Step.setDependency(\.soundEffectClient, .noop)
            Step.setDependency(\.continuousClock, TestClock())
            Step.setDependency(\.soundEffectClient.play, { soundEffectPlayCount.withValue { $0 += 1 } })
            Step.appear(await: false)
                .expectState {
                    $0.speakerIndex = 0
                    $0.secondsElapsed = 0
                }
                .validateState("sound played") { _ in
                    soundEffectPlayCount.value == 0
                }
            Step.action(.nextSpeaker)
                .expectState {
                    $0.speakerIndex = 1
                    $0.secondsElapsed = 1
                }
                .validateState("sound played") { _ in
                    soundEffectPlayCount.value == 1
                }
            Step.action(.nextSpeaker)
                .expectState {
                    $0.destination = .alert(.endMeeting(isDiscardable: false))
                }
            Step.advanceClock()
                .expectState {
                    $0.speakerIndex = 1
                    $0.secondsElapsed = 1
                }
                .validateState("sound played") { _ in
                    // no sound played
                    soundEffectPlayCount.value == 1
                }
            Step.action(.alertButton(.confirmSave))
                .expectOutput(.meetingFinished(transcript: ""))
        }

        ComponentTest("speech failure continue", stateName: "quick") {
            Step.setDependency(\.speechClient.startTask, { _ in
                AsyncThrowingStream {
                    $0.yield(
                        SpeechRecognitionResult(
                            bestTranscription: Transcription(formattedString: "I completed the project"),
                            isFinal: true
                        )
                    )
                    struct SpeechRecognitionFailure: Error {}
                    $0.finish(throwing: SpeechRecognitionFailure())
                }}
            )
            Step.setDependency(\.soundEffectClient, .noop)
            Step.setDependency(\.continuousClock, TestClock())
            Step.appear(await: false)
            Step.advanceClock()
                .expectState {
                    $0.destination = .alert(.speechRecognizerFailed)
                }
            Step.action(.alertButton(.none))
                .expectState {
                    $0.destination = nil
                    $0.isDismissed = false
                }
            Step.advanceClock(.seconds(60))
                .expectOutput(.meetingFinished(transcript: "I completed the project ❌"))
        }

        ComponentTest("speech failure discard", stateName: "quick") {
            Step.setDependency(\.speechClient.startTask, { _ in
                AsyncThrowingStream {
                    $0.yield(
                        SpeechRecognitionResult(
                            bestTranscription: Transcription(formattedString: "I completed the project"),
                            isFinal: true
                        )
                    )
                    struct SpeechRecognitionFailure: Error {}
                    $0.finish(throwing: SpeechRecognitionFailure())
                }}
            )
            Step.setDependency(\.soundEffectClient, .noop)
            Step.setDependency(\.continuousClock, TestClock())
            Step.appear(await: false)
            Step.advanceClock()
                .expectState {
                    $0.destination = .alert(.speechRecognizerFailed)
                }
            Step.action(.alertButton(.confirmDiscard))
                .expectState {
                    $0.isDismissed = true
                }
        }
    }
}
