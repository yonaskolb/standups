import Foundation
import SwiftUI
import SwiftComponent

struct MeetingModel: ComponentModel {

    struct State {
        let meeting: Meeting
        let standup: Standup
    }
}

struct MeetingView: ComponentView {
    @ObservedObject var model: ViewModel<MeetingModel>

    var view: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Divider()
                    .padding(.bottom)
                Text("Attendees")
                    .font(.headline)
                ForEach(model.standup.attendees) { attendee in
                    Text(attendee.name)
                }
                Text("Transcript")
                    .font(.headline)
                    .padding(.top)
                Text(model.meeting.transcript)
            }
        }
        .padding()
        .navigationTitle(Text(model.meeting.date, style: .date))
    }
}

struct MeetingComponent: Component, PreviewProvider {

    typealias Model = MeetingModel

    static func view(model: ViewModel<MeetingModel>) -> some View {
        NavigationStack {
            MeetingView(model: model)
        }
    }

    static var states: States {
        State("default") {
            .init(meeting: .mock, standup: .mock)
        }
    }
}
