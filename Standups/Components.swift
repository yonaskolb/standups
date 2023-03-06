import Foundation
import SwiftComponent
import SwiftUI

#if DEBUG

public let components: [any Component.Type] = [
    MainComponent.self,
    StandupsListComponent.self,
    StandupDetailComponent.self,
    MeetingComponent.self,
    StandupFormComponent.self,
    RecordMeetingComponent.self,
]

struct Component_Previews: PreviewProvider {
    static var previews: some View {
        ComponentListView(components: components)
    }
}

#endif
