import Foundation

public enum ProfileSyncMerger {
    public static func merge(local: [HostProfile], remote: [HostProfile]) -> [HostProfile] {
        let allProfiles = local + remote
        let mergedByID = allProfiles.reduce(into: [UUID: HostProfile]()) { result, profile in
            guard let existing = result[profile.id] else {
                result[profile.id] = profile
                return
            }

            if profile.updatedAt >= existing.updatedAt {
                result[profile.id] = profile
            }
        }

        return mergedByID.values.sorted { left, right in
            if left.alias.localizedCaseInsensitiveCompare(right.alias) == .orderedSame {
                return left.id.uuidString < right.id.uuidString
            }

            return left.alias.localizedCaseInsensitiveCompare(right.alias) == .orderedAscending
        }
    }
}
