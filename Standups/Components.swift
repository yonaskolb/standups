import Foundation
import SwiftComponent
import SwiftUI

#if DEBUG

public let components: [any Component.Type] = [
    StandupsListComponent.self,
    StandupDetailComponent.self,
    StandupFormComponent.self,
    RecordMeetingComponent.self,
]

struct Component_Previews: PreviewProvider {
    static var previews: some View {
        ComponentListView(components: components)
    }
}

#endif
