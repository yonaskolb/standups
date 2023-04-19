import Dependencies
import SwiftUI
import SwiftUINavigation
import SwiftComponent

struct StandupFormModel: ComponentModel {

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

    func appear(store: Store) async {
        if store.standup.attendees.isEmpty {
            store.standup.attendees.append(Attendee(id: Attendee.ID(store.dependencies.uuid())))
        }
    }

    func handle(action: Action, store: Store) async {
        switch action {
            case .addAttendee:
                let attendee = Attendee(id: Attendee.ID(store.dependencies.uuid()))
                store.standup.attendees.append(attendee)
                store.focus = .attendee(attendee.id)
            case .deleteAttendees(let indices):
                var attendees = store.standup.attendees
                attendees.remove(atOffsets: indices)
                if attendees.isEmpty {
                    attendees.append(Attendee(id: Attendee.ID(store.dependencies.uuid())))
                }
                store.standup.attendees = attendees

                guard let firstIndex = indices.first
                else { return }
                let index = min(firstIndex, store.standup.attendees.count - 1)
                store.focus = .attendee(store.standup.attendees[index].id)
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

    static var states: States {
        State("focus attendee") {
            .init(focus: .attendee(Standup.mock.attendees[3].id), standup: .mock)
        }
    }

    static var tests: Tests {
        Test("fill", state: .init(standup: .init(id: .init()))) {
            Step.dependency(\.uuid, .incrementing)
            Step.appear()
                .expectState(\.standup.attendees, [.init(id: "0")])
            Step.binding(\.standup.title, "Engineering")
            Step.binding(\.standup.duration, .seconds(20))
            Step.binding(\.standup.theme, .navy)
            Step.binding(\.focus, .attendee("0"))
            Step.binding(\.standup.attendees[id: "0"]!.name, "Tahmina")
            Step.action(.addAttendee)
                .expectState(\.standup.attendees, [.init(id: "0", name: "Tahmina"), .init(id: "1")])
                .expectState(\.focus, .attendee("1"))
            Step.binding(\.standup.attendees[id: "1"]!.name, "Sarah")
        }
        Test("add attendee", state: .init(standup: .init(id: .init(), title: "Engineering"))) {
            Step.dependency(\.uuid, .incrementing)
            Step.appear()
                .expectState {
                    $0.standup.attendees = [Attendee(id: "0")]
                }
            Step.action(.addAttendee)
                .expectState {
                    $0.standup.attendees =
                    [
                        Attendee(id: "0"),
                        Attendee(id: "1"),
                    ]
                    $0.focus = .attendee("1")
                }
        }
        let uuid = UUIDGenerator.incrementing
        Test("remove attendee", state: .init(standup: Standup(
            id: Standup.ID(),
            attendees: [
                Attendee(id: Attendee.ID(uuid())),
                Attendee(id: Attendee.ID(uuid())),
                Attendee(id: Attendee.ID(uuid())),
                Attendee(id: Attendee.ID(uuid())),
            ],
            title: "Engineering"
        ))) {
            Step.dependency(\.uuid, uuid)
            Step.appear()
            Step.action(.deleteAttendees([0]))
                .expectState(\.focus, .attendee("1"))
                .expectState(\.standup.attendees, [
                    Attendee(id: "1"),
                    Attendee(id: "2"),
                    Attendee(id: "3"),
                ])
                .expectState {
                    $0.focus = .attendee("1")
                    $0.standup.attendees = [
                        Attendee(id: "1"),
                        Attendee(id: "2"),
                        Attendee(id: "3"),
                    ]
                }
            Step.action(.deleteAttendees([1]))
                .expectState {
                    $0.focus = .attendee("3")
                    $0.standup.attendees = [
                        Attendee(id: "1"),
                        Attendee(id: "3"),
                    ]
                }
            Step.action(.deleteAttendees([1]))
                .expectState {
                    $0.focus = .attendee("1")
                    $0.standup.attendees = [
                        Attendee(id: "1"),
                    ]
                }
            Step.action(.deleteAttendees([0]))
                .expectState {
                    $0.focus = .attendee("4")
                    $0.standup.attendees = [
                        Attendee(id: "4"),
                    ]
                }
        }
    }
}
