import SwiftUI
import Tagged

// makes initialising Tagged UUIDs easier
extension UUID: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        let empty = "00000000-0000-0000-0000-000000000000"
        let string = String(empty.dropLast(value.count)) + value
        self.init(uuidString: string)!
    }
}

