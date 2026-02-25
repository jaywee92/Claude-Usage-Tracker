//
//  OAuthCredentials.swift
//  Claude Usage
//

import Foundation

struct OAuthCredentials: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String?

    var isExpired: Bool {
        Date() >= expiresAt
    }

    /// Returns true if the token expires within the next 5 minutes.
    var expiresInFiveMinutes: Bool {
        Date() >= expiresAt.addingTimeInterval(-300)
    }
}
