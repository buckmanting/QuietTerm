import Foundation
import Testing
@testable import QuietTermCore

@Test func profileSyncMergerUsesLastEditWins() {
    let id = UUID()
    let older = Date(timeIntervalSince1970: 100)
    let newer = Date(timeIntervalSince1970: 200)

    let local = HostProfile(
        id: id,
        alias: "Old",
        hostname: "old.example.com",
        username: "me",
        authMethod: .password(savedSecretID: nil),
        updatedAt: older
    )
    let remote = HostProfile(
        id: id,
        alias: "New",
        hostname: "new.example.com",
        username: "me",
        authMethod: .password(savedSecretID: nil),
        updatedAt: newer
    )

    let merged = ProfileSyncMerger.merge(local: [local], remote: [remote])

    #expect(merged.count == 1)
    #expect(merged.first?.alias == "New")
}
