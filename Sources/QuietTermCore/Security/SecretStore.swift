import Foundation

public enum SecretStoreError: Error, Equatable, Sendable {
    case notFound
    case storageFailed(String)
}

public protocol SecretStore {
    func save(_ data: Data, id: String) throws
    func read(id: String) throws -> Data
    func delete(id: String) throws
}

public final class InMemorySecretStore: SecretStore {
    private var dataByID: [String: Data]

    public init(dataByID: [String: Data] = [:]) {
        self.dataByID = dataByID
    }

    public func save(_ data: Data, id: String) throws {
        dataByID[id] = data
    }

    public func read(id: String) throws -> Data {
        guard let data = dataByID[id] else {
            throw SecretStoreError.notFound
        }

        return data
    }

    public func delete(id: String) throws {
        dataByID.removeValue(forKey: id)
    }
}
