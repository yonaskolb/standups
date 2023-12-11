import Dependencies
import SwiftUI
import SwiftUINavigation
import SwiftComponent

@ComponentModel
struct StandupFormModel {
    
    struct State {
        var focus: Field? = .title
        var standup: Standup
    }
    
    enum Field: Hashable {
        case attendee(Attendee.ID)
        case title
    }
    
    enum Action {
        case deleteAttendees(IndexSet)
        case addAttendee
    }
    
    func appear() async {
        if state.standup.attendees.isEmpty {
            state.standup.attendees.append(Attendee(id: Attendee.ID(dependencies.uuid())))
        }
    }
    
    func handle(action: Action) async {
        switch action {
        case .addAttendee:
            let attendee = Attendee(id: Attendee.ID(dependencies.uuid()))
            state.standup.attendees.append(attendee)
            state.focus = .attendee(attendee.id)
        case .deleteAttendees(let indices):
            var attendees = state.standup.attendees
            attendees.remove(atOffsets: indices)
            if attendees.isEmpty {
                attendees.append(Attendee(id: Attendee.ID(dependencies.uuid())))
            }
            state.standup.attendees = attendees

            guard let firstIndex = indices.first
            else { return }
            let index = min(firstIndex, state.standup.attendees.count - 1)
            state.focus = .attendee(state.standup.attendees[index].id)
        }
    }
}

struct StandupFormView: ComponentView {
    
    @FocusState var focus: StandupFormModel.Field?
    @ObservedObject var model: ViewModel<StandupFormModel>
    
    var view: some View {
        Form {
            Section {
                TextField("Title", text: model.binding(\.standup.title))
                    .focused(self.$focus, equals: .title)
                HStack {
                    Slider(value: model.binding(\.standup.duration.seconds), in: 5...30, step: 1) {
                        Text("Length")
                    }
                    Spacer()
                    Text(model.standup.duration.formatted(.units()))
                }
                ThemePicker(selection: model.binding(\.standup.theme))
            } header: {
                Text("Standup Info")
            }
            Section {
                ForEach(model.binding(\.standup.attendees)) { $attendee in
                    TextField("Name", text: $attendee.name)
                        .focused(self.$focus, equals: .attendee(attendee.id))
                }
                .onDelete { indices in
                    model.send(.deleteAttendees(indices))
                }
                model.button(.addAttendee, "New attendee")
            } header: {
                Text("Attendees")
            }
        }
        // this causes a crash when run in preview
        //        .bind(model.binding(\.focus), to: self.$focus)
    }
}

struct ThemePicker: View {
    @Binding var selection: Theme
    
    var body: some View {
        Picker("Theme", selection: $selection) {
            ForEach(Theme.allCases) { theme in
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.mainColor)
                    Label(theme.name, systemImage: "paintpalette")
                        .padding(4)
                }
                .foregroundColor(theme.accentColor)
                .fixedSize(horizontal: false, vertical: true)
                .tag(theme)
            }
        }
    }
}

extension Duration {
    fileprivate var seconds: Double {
        get { Double(self.components.seconds / 60) }
        set { self = .seconds(newValue * 60) }
    }
}

struct StandupFormComponent: Component, PreviewProvider {
    
    typealias Model = StandupFormModel
    
    static func view(model: ViewModel<StandupFormModel>) -> some View {
        StandupFormView(model: model)
    }
    
    static var preview = PreviewModel(state: .init(standup: .mock))
    
    static var tests: Tests {
        Test("fill", state: .init(standup: .init(id: "1"))) {
            Step.snapshot("empty")
            Step.dependency(\.uuid, .incrementing)
            Step.appear()
                .expectState(\.standup.attendees, [.init(id: "0")])
            Step.binding(\.standup.title, "Engineering")
            Step.binding(\.standup.duration, .seconds(20*60))
            Step.binding(\.standup.theme, .navy)
            Step.binding(\.focus, .attendee("0"))
            Step.binding(\.standup.attendees[id: "0"]!.name, "Tahmina")
            Step.action(.addAttendee)
                .expectState(\.standup.attendees, [.init(id: "0", name: "Tahmina"), .init(id: "1")])
                .expectState(\.focus, .attendee("1"))
            Step.binding(\.standup.attendees[id: "1"]!.name, "Sarah")
            Step.snapshot("filled")
        }
        Test("remove attendee", state: .init(standup: Standup(
            id: Standup.ID(),
            attendees: [
                .mock("1"),
                .mock("2"),
                .mock("3"),
                .mock("4"),
            ],
            title: "Engineering"
        ))) {
            Step.dependency(\.uuid, .incrementing)
            Step.appear()
            Step.action(.deleteAttendees([0]))
                .expectState(\.focus, .attendee("2"))
                .expectState(\.standup.attendees, [
                    .mock("2"),
                    .mock("3"),
                    .mock("4"),
                ])
            Step.action(.deleteAttendees([1]))
                .expectState(\.focus, .attendee("4"))
                .expectState(\.standup.attendees, [
                    .mock("2"),
                    .mock("4"),
                ])
            Step.action(.deleteAttendees([1]))
                .expectState(\.focus, .attendee("2"))
                .expectState(\.standup.attendees, [.mock("2")])
            Step.action(.deleteAttendees([0]))
                .expectState(\.focus, .attendee("0"))
                .expectState(\.standup.attendees, [.init(id: "0")])
        }
    }
}
