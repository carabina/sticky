import Foundation

public protocol Persistable: Codable {}

public protocol UniqueIndexable {
    associatedtype Index: Equatable
    var index: Index { get }
}

public typealias Stickyable = Persistable & Equatable & UniqueIndexable

public extension Persistable {
    
    public static func read() -> [Self]? {
        stickyLog(debugDescription)
        return Self.decode(from: fileData)
    }
    
    public static func readAsync(completion: @escaping ([Self]?) -> Void) {
        stickyLog(debugDescription)
        DispatchQueue.main.async {
            completion(Self.decode(from: fileData))
        }
    }
    
    public static var name: String {
        return String(describing: Self.self)
    }
    
    public static func registerForNotification() {
        if notificationName == nil {
            Sticky.shared.registeredNotifications.append(Self.self)
        }
    }
    
    public static func deregisterForNotification() {
        if let index = Sticky.shared.registeredNotifications.index(where: { $0 == Self.self} ) {
            Sticky.shared.registeredNotifications.remove(at: index)
        }
    }
    
    public static var notificationName: NSNotification.Name? {
        if Sticky.shared.registeredNotifications.contains(where: { $0 == Self.self }) {
            return NSNotification.Name(name)
        }
        return nil
    }
    
    public static var debugDescription: String {
        guard let data = fileData else { return "" }
        return "\(name): \(String(bytes: data, encoding: .utf8) ?? "")"
    }
    
    private static func decode(from data: Data?) -> [Self]? {
        var decoded: [Self]? = nil
        guard let jsonData = data else { return nil }
        do {
            decoded = try JSONDecoder().decode([Self].self, from: jsonData)
        } catch {
            print(error.localizedDescription)
        }
        return decoded
    }
    
    private static var fileData: Data? {
        return FileHandler.read(from: filePath)
    }
    
    public static var filePath: String {
        return FileHandler.fullPath(for: Self.self)
    }
}

public extension Persistable where Self: Equatable {
    private var store: Store<Self> {
        let objects = Self.read()
        return Store(value: self, stored: objects)
    }
    
    private func storeAsync(completion: @escaping (Store<Self>) -> Void) {
        Self.readAsync { result in
            completion(Store(value: self, stored: result))
        }
    }
    
    public var isStored: Bool {
        if let _ = Self.read()?.index(of: self) {
            return true
        }
        return false
    }
    
    public func save() {
        stickyLog("\(Self.name) saving without index")
        if Sticky.shared.configuration.async {
            storeAsync { store in
                self.save(in: store)
            }
        } else {
            save(in: self.store)
        }
    }
    
    fileprivate func save(in store: Store<Self>) {
        store.save()
    }
}

public extension Persistable where Self: Equatable & UniqueIndexable {
    private var indexStore: IndexStore<Self> {
        let objects = Self.read()
        return IndexStore(value: self, stored: objects)
    }
    
    private func indexStoreAsync(completion: @escaping (IndexStore<Self>) -> Void) {
        Self.readAsync { result in
            completion(IndexStore(value: self, stored: result))
        }
    }
    
    public func save() {
        stickyLog("\(Self.name) saving with index")
        if Sticky.shared.configuration.async {
            indexStoreAsync { store in
                self.save(in: store)
            }
        } else {
            save(in: self.indexStore)
        }
    }
}

internal extension Collection where Element: Persistable, Self: Codable {
    internal func saveWithOverwrite() {
        guard let encodedData = encode(self) else { return }
        let path = FileHandler.fullPath(for: Element.self)
        DispatchQueue.main.async {
            FileHandler.write(data: encodedData, to: path)
        }
    }
    
    private func encode<T>(_ obj: T) -> Data? where T: Encodable {
        var data: Data? = nil
        do {
            data = try JSONEncoder().encode(obj)
        } catch let error {
            print(error.localizedDescription)
        }
        return data
    }
}
