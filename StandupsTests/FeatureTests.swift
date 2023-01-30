import Foundation
//import XCTest
import Quick
import SwiftComponent
import Standups

final class FeatureTests: QuickSpec {

    override func spec() {
        for feature in Standups.features {
            testComponent(feature)
        }
    }

    func testComponent<Feature: ComponentFeature>( _ component: Feature.Type) {
        describe(component.Model.baseName) {
            for test in component.tests {
                it(test.name, file: test.source.file, line: test.source.line) {
                    let result = await Feature.run(test)
                    print("\tComponent \(component.Model.baseName): \(test.name)")
                    for step in result.steps {
                        print("\t\tStep \(step.step.description)")
                        if !step.step.expectations.isEmpty {
                            print("\t\t\t\(step.step.expectations.map(\.description).joined(separator: "\n\t\t\t"))")
                        }
                        for error in step.errors {
                            var message = "\n\n\(step.step.description) failed: \(error.error)"
                            if let diff = error.diff {
                                message += "\n\n\(diff)"
                            }

                            XCTFail(message, file: error.source.file, line: error.source.line)
                        }
                    }
                }
            }
        }
    }
}
