import Foundation
import SwiftComponent
import SwiftUI

#if DEBUG

public let features: [any ComponentFeature.Type] = [
    StandupsListFeature.self,
    StandupDetailFeature.self,
    StandupFormFeature.self,
    RecordMeetingFeature.self,
]

struct Feature_Previews: PreviewProvider {
    static var previews: some View {
        FeatureListView(features: features)
    }
}

#endif
