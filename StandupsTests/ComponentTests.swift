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
                    print("\t\(component.Model.baseName): \(test.name)")
                    for step in result.steps {
                        self.testStep(step)
                    }
                }
            }
        }
    }

    func testStep(_ step: TestStepResult, parent: String? = nil) {
        var printMessage = "\t\tStep \(step.description)"
        if parent != nil {
            printMessage = "\t\(printMessage)"
        }
        print(printMessage)
        if !step.expectations.isEmpty {
            var prefix = "\t\t\t"
            if parent != nil {
                prefix += "\t"
            }
            print("\(prefix)\(step.expectations.joined(separator: "\n\(prefix)"))")
        }
        for error in step.errors {
            var message = "\n\n"
            if let parent {
                message += "\(parent)/"
            }
            message += "\(step.description) failed: \(error.error)"
            if let diff = error.diff {
                message += "\n\n\(diff.joined(separator: "\n"))"
            }

            XCTFail(message, file: error.source.file, line: error.source.line)
        }
        for child in step.children {
            testStep(child, parent: step.description)
        }
    }
}
