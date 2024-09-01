import Foundation
import SwiftComponent
import Dependencies

extension TestStep {

    static func advanceClock(_ duration: Duration = .seconds(1), file: StaticString = #filePath, line: UInt = #line) -> Self {
        .init(title: "Advance clock", details: duration.formatted(), file: file, line: line) { context in
            guard let clock = context.model.dependencies.continuousClock as? TestClock<Duration> else { return }
            await clock.advance(by: duration)
        }
    }
}
