//
//  Mocks.swift
//  Standups
//
//  Created by Yonas Kolb on 7/2/2023.
//

import Foundation

extension Standup {
    static let mock = Self(
        id: Standup.ID(UUID()),
        attendees: [
            Attendee(id: .init(), name: "Blob"),
            Attendee(id: .init(), name: "Blob Jr"),
            Attendee(id: .init(), name: "Blob Sr"),
            Attendee(id: .init(), name: "Blob Esq"),
            Attendee(id: .init(), name: "Blob III"),
            Attendee(id: .init(), name: "Blob I"),
        ],
        duration: .seconds(60),
        meetings: [.mock],
        theme: .orange,
        title: "Design"
    )

    static let engineeringMock = Self(
        id: Standup.ID(UUID()),
        attendees: [
            Attendee(id: .init(), name: "Blob"),
            Attendee(id: .init(), name: "Blob Jr"),
        ],
        duration: .seconds(60 * 10),
        meetings: [],
        theme: .periwinkle,
        title: "Engineering"
    )

    static let designMock = Self(
        id: Standup.ID(UUID()),
        attendees: [
            Attendee(id: .init(), name: "Blob Sr"),
            Attendee(id: .init(), name: "Blob Jr"),
        ],
        duration: .seconds(60 * 30),
        meetings: [],
        theme: .poppy,
        title: "Product"
    )
}

extension Meeting {

    static let mock = Meeting(
        id: Meeting.ID(UUID()),
        date: Date().addingTimeInterval(-60 * 60 * 24 * 7),
        transcript: """
          Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor \
          incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud \
          exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure \
          dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. \
          Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt \
          mollit anim id est laborum.
          """
    )
}
