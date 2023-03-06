import Foundation
//import XCTest
import Quick
import SwiftComponent
import Standups

final class ComponentTests: QuickSpec {

    override func spec() {
        for component in Standups.components {
            testComponent(component)
        }
    }

    func testComponent<ComponentType: Component>( _ component: ComponentType.Type) {
        describe(component.Model.baseName) {
            for test in component.tests {
                it(test.name, file: test.source.file, line: test.source.line) {
                    let result = await ComponentType.run(test)
                    print("\tComponent \(component.Model.baseName): \(test.name)")
                    for step in result.steps {
                        self.testStep(step)
                    }
                }
            }
        }
    }

    func testStep(_ step: TestStepResult, parent: String? = nil) {
        print("\t\tStep \(step.description)")
        if !step.expectations.isEmpty {
            print("\t\t\t\(step.expectations.joined(separator: "\n\t\t\t"))")
        }
        for error in step.errors {
            var message = "\n\n"
            if let parent {
                message += "\(parent)/"
            }
            message += "\(step.description) failed: \(error.error)"
            if let diff = error.diff {
                message += "\n\n\(diff)"
            }

            XCTFail(message, file: error.source.file, line: error.source.line)
        }
        for child in step.children {
            testStep(child, parent: step.description)
        }
    }
}
