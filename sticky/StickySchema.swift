import Foundation

typealias JSON = Any

internal typealias StickyEntityCollection = [[String: Any]]
internal typealias StickyDataMap<Key: Hashable> = [Key: Any]
internal typealias StickyEntity = String

internal enum SchemaUpdateResult {
    case success
    case error(String)
}

public struct StickySchemaFile {
    public var version: Int
    public var fileUrl: URL
    
    public init(version: Int, fileUrl: URL) {
        self.version = version
        self.fileUrl = fileUrl
    }
}

internal struct StickySchemaData<Key: Hashable> {
    var action: StickySchemaAction<Key>
    var entity: StickyEntity
//    var element: StickyDataNode
    var node: Node<Key>
}

struct Node<Key: Hashable> {
    var path: [Key]
    var key: Key
    var value: Any
}

internal enum StickySchemaAction<Key: Hashable>: String {
    case renameEntity
    case renameProperty
    case newProperty
    case removeProperty
    
    init?(_ value: Key) {
        guard
            let stringValue = value as? String,
            let action = StickySchemaAction(rawValue: stringValue)
            else { return nil }
        self =  action
    }
}

public class StickySchemaUpdater {
    
    // MARK: Public properties
    
    public var stickySchemaFile: StickySchemaFile
    public var version: Int {
        return stickySchemaFile.version
    }
    
    // MARK: Private properties
    
    private let actions: [StickySchemaAction<String>] = [
        .renameEntity,
        .renameProperty,
        .newProperty,
        .removeProperty
    ]
    
    public init(for stickySchemaFile: StickySchemaFile) {
        self.stickySchemaFile = stickySchemaFile
    }
}

// MARK: Public API

extension StickySchemaUpdater {
    
    public static func processUpdates(for schemaFiles: [StickySchemaFile]) {
        // Sort each file by version number then process updates
        schemaFiles
            .sorted { $0.version < $1.version }
            .compactMap { schemaFile in
                StickySchemaUpdater(for: schemaFile)
            }
            .forEach { stickySchema in
                stickySchema.process()
        }
    }
    
    public static func checkUpdateNeeded(for version: Int) -> Bool {
        return version != Sticky.shared.currentSchemaVersion
    }
}

// MARK: Process flow control methods

extension StickySchemaUpdater {
    private func process() {
        stickyLog("----Begin update to version \(version)----")
        stickyLog("Processing schema file...")
        guard let data = schemaData(from: stickySchemaFile) else { return }
        
        stickyLog("Converting data file to json...")
        guard let jsonData = json(from: data) else { return }
        
        stickyLog("Converting json to dictionary...")
        guard let dictionaryData = dictionary(from: jsonData) else { return }
        
        stickyLog("Looking for actions to process...")
//        guard let schemaData = processUpdaterResult(stickySchemaData(for: dictionaryData)) else { return }
        guard let schemaData = parseSchema(from: dictionaryData) else { return }
        
        var memoryStore: [StickyEntity: StickyEntityCollection] = [:]
        print("here: \(schemaData)")
        stickyLog("----Processing actions...")
        
        for schemaUpdateAction in schemaData {
            var collection: StickyEntityCollection = []
            
            guard let stored = stored(for: schemaUpdateAction.entity, memoryStore: memoryStore) else { return }

            for dataItem in stored {
                stickyLog("Performing action \(schemaUpdateAction.action) on entity \(schemaUpdateAction.entity)")
                let action = schemaUpdateAction.action
                switch action {
                case .removeProperty:
                    if let properties = schemaUpdateAction.node.value as? [String] {
                        var pathWithKey = schemaUpdateAction.node.path
                        pathWithKey.append(schemaUpdateAction.node.key)
                        let updatedItem = performOperation(on: dataItem, at: pathWithKey, with: removeKeys(properties))
                        collection.append(updatedItem)
                    }
                case .newProperty:
                    let updatedItem = performOperation(on: dataItem, at: schemaUpdateAction.node.path, with: newNode(schemaUpdateAction.node.value, for: schemaUpdateAction.node.key))
                    collection.append(updatedItem)
                case .renameProperty:
                    if let newKey = schemaUpdateAction.node.value as? String {
                        let updatedItem = performOperation(on: dataItem, at: schemaUpdateAction.node.path, with: renameKey(from: schemaUpdateAction.node.key, to: newKey))
                        collection.append(updatedItem)
                    }
                default:
                    stickyLog("No action taken")
                }

            }
            memoryStore.updateValue(collection, forKey: schemaUpdateAction.entity)
            collection = []
        }
        
        for (entity, collection) in memoryStore {
            let writeResult = writeJsonFile(for: collection, to: entity)
            if case .error(_) = writeResult {
                return
            }
        }

        print(memoryStore)
        increment(to: version)
    }
    
    private func processSchemaAction<Key: Hashable>(for data: StickySchemaData<Key>) -> SchemaUpdateResult {
        guard data.action == .renameEntity,
            let oldName = data.node.key as? String,
            let newName = data.node.value as? String
            else {
                return .error("Unable to process entity file rename from \"\(data.node.key)\" to \"\(data.node.value)\"")
        }
        return processRenameEntity(from: oldName, to: newName)
    }
    
    private func collectionFromMemory(for entity: StickyEntity, from dataStore: [StickyEntity: StickyEntityCollection]) -> StickyEntityCollection? {
        return dataStore[entity]
    }
    
    private func collectionFromDisk(for entity: StickyEntity) -> StickyEntityCollection? {
        return readStickyJsonFile(for: entity)
    }
    
    private func stored(for entity: StickyEntity, memoryStore: [StickyEntity: StickyEntityCollection]) -> StickyEntityCollection? {
        if let memory = collectionFromMemory(for: entity, from: memoryStore) {
            return memory
        } else if let disk = collectionFromDisk(for: entity) {
            return disk
        } else {
            stickyLog("Data file for \"\(entity)\" does not exist")
            return nil
        }
    }
//    private func stickySchemaData<Key: Hashable>(for stickyDataNode: StickyDataMap<Key>) -> SchemaUpdateResult<[StickySchemaData<Key>]> {
//        print(stickyDataNode)
//        var stickySchemaData: [StickySchemaData<Key>] = []
//        for (actionName, entityData) in stickyDataNode {
//            if let action = StickySchemaAction(actionName) {
//                print(action)
//                if let entity = entityData as? StickyDataMap<Key> {
//                    for (entityName, propertyData) in entity {
//                        if let properties = propertyData as? StickyDataMap<Key>, let entityName = entityName as? String {
//                            parseKeys(for: properties, nodes: [], path: []).forEach {
//                                stickySchemaData.append(StickySchemaData(action: action, entity: entityName, node: $0))
//                            }
//                        } else if action == .renameEntity, let entityName = entityName as? String {
//                            let node: Node<Key> = Node(path: [], key: entityName, value: propertyData) as! Node<Key>
//                            stickySchemaData.append(StickySchemaData<Key>(action: action, entity: entityName, node: node))
//                        }
//                    }
//                } else {
//                    return .error("Entity data for action \"\(actionName)\" is malformed")
//                }
//            } else {
//                return .error("\"\(actionName)\" doesn't match any available actions")
//            }
//        }
//        return .success(stickySchemaData)
//    }
    
    private func parseSchema<Key: Hashable>(from schema: StickyDataMap<Key>) -> [StickySchemaData<Key>]? {
        let nodes = parseKeys(for: schema, nodes: [], path: [])
        var returnSchemaData: [StickySchemaData<Key>] = []
        for node in nodes {
            guard let schemaData = schemaData(for: node) else { return nil }
            returnSchemaData.append(schemaData)
        }
        return returnSchemaData
    }
    
    private func schemaData<Key: Hashable>(for node: Node<Key>) -> StickySchemaData<Key>? {
        var path = node.path
        
        guard let actionName = parseFirst(from: &path) else {
                stickyLog("Malformed or empty schema file", logAction: .error)
                return nil
        }
        
        guard let action = StickySchemaAction(actionName) else {
                stickyLog("Invalid action \"\(actionName)\"", logAction: .error)
                return nil
        }
        
        guard let entityName = entityName(for: action, nodeKey: node.key, path: &path) else {
            stickyLog("Unable to parse entity name for action \"\(action.rawValue)\"")
            return nil
        }
        
        let returnNode = Node(path: path, key: node.key, value: node.value)
        return StickySchemaData(action: action, entity: entityName, node: returnNode)
    }
    
    private func entityName<Key: Hashable>(for action: StickySchemaAction<Key>, nodeKey: Key, path: inout [Key]) -> String? {
        // If path is empty, assign key to entityName
        if path.isEmpty, let keyEntityName = nodeKey as? String {
            return keyEntityName
        } else if let pathEntityName = parseFirst(from: &path) as? String {
            return pathEntityName
        } else {
            return nil
        }
    }
    
    private func parseFirst<Key: Hashable>(from list: inout [Key]) -> Key? {
        guard !list.isEmpty else { return nil }
        return list.removeFirst()
    }
    
    private func increment(to version: Int) {
        Sticky.shared.changeSchemaVersion(to: version)
    }
    
    private func schemaData(from file: StickySchemaFile) -> Data? {
        do {
            let data = try Data(contentsOf: file.fileUrl)
            return data
        }
        catch {
            stickyLog("Unable to process schema file \(file.fileUrl)", logAction: .error)
            return nil
        }
    }
    
    private func json(from data: Data) -> JSON? {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return json
        }
        catch {
            stickyLog("Unable to parse json for \(stickySchemaFile.fileUrl)", logAction: .error)
            return nil
        }
    }
    
    private func dictionary(from json: JSON) -> StickyDataMap<String>? {
        guard let dict = json as? [String: Any] else {
            stickyLog("Can not parse JSON file", logAction: .error)
            return nil
        }
        return dict
    }
    
    // Method to parse schema properties returning all key/values
    // with respective paths. Output will be used later to traverse
    // stored json files and perform change operations
    func parseKeys<Key: Hashable>(for dict: [Key: Any], nodes: [Node<Key>], path: [Key]) -> [Node<Key>] {
        let availableKeys = Array(dict.keys)
        var result = nodes
        var path = path
        
        for key in availableKeys {
            if let childNode = dict[key] {
                // Drop invalid keys from path
                if let last = path.last, dict[last] != nil {
                    _ = path.popLast()
                }
                // Check if children are nodes
                if let parseable = childNode as? [Key: Any] {
                    // add key to path and recurse
                    path.append(key)
                    result = parseKeys(for: parseable, nodes: result, path: path)
                } else {
                    // create result node from key/value and path
                    result.append(Node(path: path, key: key, value: childNode))
                }
            }
        }
        return result
    }
    
    // Takes a dictionary, keypath (array), and operation
    // Searches dictionary for given keypath, then performs operation
    // on that node, returning an updated node to replace existing.
    // Will be used to update Sticky json files as
    // data "schema" changes are required
    func performOperation<Key: Hashable>(on dictionary: [Key: Any], at path: [Key], with operation: ([Key: Any]) -> [Key: Any]) -> [Key: Any] {
        var result = dictionary
        
        if path.isEmpty { return operation(result) }
        
        var queue: [[Key: Any]] = []
        queue.append(result)
        
        // Traverse dictionary path and perform operation on node
        for key in path {
            if var currentNode = queue.last {
                if let nestedNode = currentNode[key] as? [Key: Any] {
                    let updatedNode = operation(nestedNode)
                    queue.append(updatedNode)
                }
            }
        }
        
        // Build up result dictionary with updated values
        if var last = queue.popLast() {
            for key in path.reversed() {
                if var node = queue.popLast() {
                    node.updateValue(last, forKey: key)
                    last = node
                }
            }
            result = last
        }
        
        return result
    }
    
    func renameKey<Key: Hashable>(from oldKey: Key, to newKey: Key) -> ([Key: Any]) -> [Key: Any] {
        return { dict in
            var result = dict
            if let value = dict[oldKey] {
                result.removeValue(forKey: oldKey)
                result.updateValue(value, forKey: newKey)
            }
            return result
        }
    }
    
    func removeKeys<Key: Hashable>(_ keys: [Key]) -> ([Key: Any]) -> [Key: Any] {
        return { dict in
            var result = dict
            for key in keys {
                result.removeValue(forKey: key)
            }
            return result
        }
    }
    
    func newNode<Key: Hashable>(_ node: Any, for key: Key) -> ([Key: Any]) -> [Key: Any] {
        return { dict in
            var result = dict
            result.updateValue(node, forKey: key)
            return result
        }
    }
    
//    func applyAction(_ schema: StickyDataNode, with stored: StickyDataNode, apply action: StickySchemaAction) -> SchemaUpdateResult<StickyDataNode> {
//        var result = stored
//        // Loop through properties for update action on entity
//        for schemaProperty in schema {
//            if let storedProperty = stored[schemaProperty.key] {
//                if let nestedSchemaProperty = schemaProperty.value as? StickyDataNode, let storedProperty = storedProperty as? StickyDataNode {
//                    _ = applyAction(nestedSchemaProperty, with: storedProperty, apply: action)
//                } else {
//                    // No nested property in schema
//                    switch action {
//                    case .renameProperty:
//                        if let newName = schemaProperty.value as? String, let property = stored[schemaProperty.key] {
//                            result.removeValue(forKey: schemaProperty.key)
//                            result.updateValue(property, forKey: newName)
//                            return .success(result)
//                        } else {
//                            return .error("Could not rename property")
//                        }
//                    case .removeProperty:
//                        if let removeList = schemaProperty.value as? [String], var storedProperty = storedProperty as? StickyDataNode {
//                            for itemToRemove in removeList {
//                                if storedProperty.removeValue(forKey: itemToRemove) == nil {
//                                    return .error("Property to remove does not exist")
//                                }
//                                result.updateValue(storedProperty, forKey: schemaProperty.key)
//                            }
//                            return .success(result)
//                        }
//                    default:
//                        return .error("Could not apply update")
//                    }
//                }
//            } else {
//                // Property doesn't exist in stored
//                if action == .newProperty {
//                    result.updateValue(schemaProperty.value, forKey: schemaProperty.key)
//                    return .success(result)
//                } else {
//                    return .error("No new property available")
//                }
//            }
//        }
//        return .success(result)
//    }
}

// MARK: Process action methods

extension StickySchemaUpdater {
    private func processRenameEntity(from oldName: String, to newName: String) -> SchemaUpdateResult {
        let fileResult = FileHandler.renameFile(from: oldName, to: newName)
        switch fileResult {
        case .success:
            stickyLog("Entity changed from \(oldName) to \(newName)")
        case .error(let error):
            return .error(error.localizedDescription)
        }
        return .success
    }
//
//    private func processRenameProperty(for data: [String: Any]) -> SchemaUpdateResult {
//        let resultMap: [SchemaUpdateResult] = data.map { entity in
//            if let properties = entity.value as? [String: String] {
//                for (oldName, newName) in properties {
//                    return renameProperty(for: entity.key, from: oldName, to: newName)
//                }
//            }
//            return .error("Unable to process file")
//        }
//        return resultMap.first(where: {$0 != .success}) ?? .success
//    }
//
//    private func processNewProperty(for data: [String: Any]) -> SchemaUpdateResult {
//        let resultMap: [SchemaUpdateResult] = data.map { entity in
//            if let properties = entity.value as? [String: Any] {
//                for (name, defaultValue) in properties {
//                    return addProperty(name, for: entity.key, with: defaultValue)
//                }
//            }
//            return .error("Unable to process file for \(data)")
//        }
//        return resultMap.first(where: {$0 != .success}) ?? .success
//    }
//
//    private func processRemoveProperty(for data: [String: Any]) -> SchemaUpdateResult {
//        let resultMap: [SchemaUpdateResult] = data.map { entity in
//            if let properties = entity.value as? [String] {
//                for propertyToRemove in properties {
//                    return removeProperty(propertyToRemove, from: entity.key)
//                }
//            }
//            return .error("Unable to process file")
//        }
//        return resultMap.first(where: {$0 != .success}) ?? .success
//    }
}

// MARK: Process action helper methods

//extension StickySchemaUpdater {
//
//    private func renameProperty(for entityName: String, from oldName: String, to newName: String) -> SchemaUpdateResult {
//        guard let storedEntities = readStickyJsonFile(for: entityName) else { return .error("Unable to parse") }
//
//        var result: StickyEntityCollection = []
//        for var item in storedEntities {
//            if let property = item[oldName] {
//                item.removeValue(forKey: oldName)
//                item.updateValue(property, forKey: newName)
//                stickyLog("Changed \(entityName) property name from \"\(oldName)\" to \"\(newName)\"")
//            } else {
//                return .error("ERROR: Couldn't rename \"\(oldName)\" in \"\(entityName)\" because property doesn't exist.")
//            }
//            result.append(item)
//        }
//
//        return writeJsonFile(for: result, to: entityName)
//    }
//
//    private func addProperty(_ newPropertyName: String, for entityName: String, with defaultValue: Any) -> SchemaUpdateResult {
//        guard let storedEntities = readStickyJsonFile(for: entityName) else { return .error("Unable to parse") }
//
//        var result: StickyEntityCollection = []
//        for var item in storedEntities {
//            // Do nothing if property already exists
//            if let _ = item[newPropertyName] {
//                return .error("ERROR: Couldn't add \"\(newPropertyName)\" to \"\(entityName)\" because property already exists")
//            } else {
//                item.updateValue(defaultValue, forKey: newPropertyName)
//                result.append(item)
//                stickyLog("Added property \"\(newPropertyName)\" to \(entityName) with default value of \"\(defaultValue)\"")
//            }
//        }
//
//        return writeJsonFile(for: result, to: entityName)
//    }
//
//    private func removeProperty(_ removedProperty: String, from entityName: String) -> SchemaUpdateResult {
//        guard let storedEntities = readStickyJsonFile(for: entityName) else { return .error("Unable to parse") }
//
//        var result: StickyEntityCollection = []
//        for var item in storedEntities {
//            if let _ = item[removedProperty] {
//                item.removeValue(forKey: removedProperty)
//                stickyLog("Removed property \"\(removedProperty)\" from \"\(entityName)\"")
//            } else {
//                return .error("Couldn't remove \"\(removedProperty)\" in \"\(entityName)\" because property doesn't exist.")
//            }
//            result.append(item)
//        }
//        return writeJsonFile(for: result, to: entityName)
//    }
//}

// MARK: File access methods

extension StickySchemaUpdater {
    
    private func readStickyJsonFile(for entityName: String) -> StickyEntityCollection? {
        let filePath = FileHandler.url(for: entityName).path
        guard let data = FileHandler.read(from: filePath) else {
            stickyLog("ERROR: Could not read JSON file data for \(filePath)", logAction: .error)
            return nil
        }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let result = json as? StickyEntityCollection else {
                stickyLog("ERROR: Can not parse JSON file \(filePath)", logAction: .error)
                return nil
            }
            return result
        }
        catch {
            stickyLog(error.localizedDescription)
        }
        return nil
    }
    
    private func writeJsonFile(for entityCollection: StickyEntityCollection, to entityName: String) -> SchemaUpdateResult {
        let filePath = FileHandler.url(for: entityName).path
        do {
            let newData = try JSONSerialization.data(withJSONObject: entityCollection, options: [])
            let fileResult = FileHandler.write(data: newData, to: filePath)
            switch fileResult {
            case .success: return .success
            case .error(let error): return .error(error.localizedDescription)
            }
        }
        catch {
            return .error(error.localizedDescription)
        }
    }
    

}
