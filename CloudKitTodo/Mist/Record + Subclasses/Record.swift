//
//  Record.swift
//  CloudKitTodo
//
//  Created by Matthew McCroskey on 11/30/16.
//  Copyright © 2016 Less But Better. All rights reserved.
//

import Foundation
import CloudKit


typealias RecordValue = CKRecordValue

internal struct RelatedRecordData {
    
    let identifier: RecordIdentifier
    let action: CKReferenceAction
    
}

class Record: Hashable {
    
    
    // MARK: - Static Convenience Functions
    
    static func fetch(_ identifier:RecordIdentifier, from:StorageScope, fetchDepth:Int = -1, finished:((RecordOperationResult, Record?) -> Void)) {
        Mist.fetch(identifier, from: from, fetchDepth: fetchDepth, finished: finished)
    }
    
    static func fetch(_ identifiers:Set<RecordIdentifier>, from:StorageScope, fetchDepth:Int = -1, finished:((RecordOperationResult, [Record]?) -> Void)) {
        Mist.fetch(identifiers, from: from, fetchDepth: fetchDepth, finished: finished)
    }
    
    static func find(where filter:FilterClosure, within:StorageScope, sortedBy:SortClosure?=nil, fetchDepth:Int = -1, finished:((RecordOperationResult, [Record]?) -> Void)) {
        Mist.find(recordsOfType: self, where: filter, within: within, fetchDepth: fetchDepth, finished: finished)
    }
    
    static func find(where predicate:NSPredicate, within:StorageScope, sortedBy:SortClosure?=nil, fetchDepth:Int = -1, finished:((RecordOperationResult, [Record]?) -> Void)) {
        Mist.find(recordsOfType: self, where: predicate, within: within, fetchDepth: fetchDepth, finished: finished)
    }
    
    
    // MARK: - Initializer
    
    init(className: String) {
        
        self.className = className
        self.identifier = UUID().uuidString as RecordIdentifier
        
        let recordID = CKRecordID(recordName: self.identifier)
        self.backingRemoteRecord = CKRecord(recordType: self.className, recordID: recordID)
        
    }
    
    init(backingRemoteRecord:CKRecord) {
        
        self.backingRemoteRecord = backingRemoteRecord
        
        self.className = self.backingRemoteRecord.recordType
        self.identifier = self.backingRemoteRecord.recordID.recordName
        
        for key in self.backingRemoteRecord.allKeys() {
            
            if let reference = self.backingRemoteRecord.object(forKey: key) as? CKReference {
                
                let relatedRecordData = RelatedRecordData(identifier: reference.recordID.recordName, action: reference.referenceAction)
                self.relatedRecordDataSetKeyPairs[key] = relatedRecordData
                
            }
            
        }
        
    }
    
    
    // MARK: - Public Properties
    
    let identifier: RecordIdentifier
    
    var parent: Record? {
        
        willSet {
            
            if let parent = newValue {
                
                Record.ensureDatabasesAndRecordZonesMatch(between: parent, and: self)
                parent.children.insert(self)
                
            }
            
        }
        
    }
    
    private(set) var children: Set<Record> = []
    
    
    // MARK: - Protected Properties
    
    internal let className: String
    
    internal var scope: CKDatabaseScope?
    internal var recordZone: RecordZone?
    internal var share: CKShare?
    
    internal let backingRemoteRecord: CKRecord
    
    internal var relatedRecordsCache: [String : Record] = [:]
    internal var relatedRecordDataSetKeyPairs: [String : RelatedRecordData] = [:]
    
    
    // MARK: - Private Properties
    
    internal var typeString: String {
        
        let mirror = Mirror(reflecting: self)
        let selfType = mirror.subjectType as! Record.Type
        let selfTypeString = String(describing: selfType)
        
        return selfTypeString
        
    }
    
    
    // MARK: - Interacting with Record Properties
    
    func propertyValue(forKey key:String) -> RecordValue? {
        
        if let propertyValue = self.backingRemoteRecord.object(forKey: key) {
            
            guard !(propertyValue is CKReference) else {
                
                fatalError(
                    "Do not fetch relationships using object(forKey:) -- use " +
                    "relatedRecord(forKey:) instead. Here are the object and key in question:\n" +
                    "OBJECT: \(self)\n" +
                    "KEY: \(key)"
                )
                
            }
            
            return propertyValue
            
        }

        return nil
        
    }
    
    func setPropertyValue(_ propertyValue:RecordValue?, forKey key:String) {
        
        guard !(propertyValue is CKReference) else {
            
            fatalError(
                "Do not set relationships using setObject(forKey:) -- use " +
                 "setRelatedRecord(forKey:withReferenceAction:) instead. Here are the object and key in question:\n" +
                 "OBJECT: \(self)\n" +
                 "KEY: \(key)"
            )
            
        }
        
        self.backingRemoteRecord.setObject(propertyValue, forKey: key)
        
    }
    
    
    // MARK: - Interacting with Record Relationships
    
    func relatedRecord(forKey key:String) -> Record? {
        return self.relatedRecordsCache[key]
    }
    
    func setRelatedRecord(_ relatedRecord:Record?, forKey key:String, withRelationshipDeleteBehavior behavior:RelationshipDeleteBehavior? = nil) {
        
        func configureReference() {
            
            if let relatedRecord = relatedRecord {
                
                let relationshipBehavior = behavior ?? .none
                let newReference = CKReference(record: relatedRecord.backingRemoteRecord, action: relationshipBehavior)
                self.backingRemoteRecord.setObject(newReference, forKey: key)
                
            } else {
                
                self.backingRemoteRecord.setObject(nil, forKey: key)
                
            }
            
        }
        
        if let relatedRecord = relatedRecord {
            
            if let extantObject = self.backingRemoteRecord.object(forKey: key) {
                
                guard let extantReference = extantObject as? CKReference else {
                    
                    fatalError(
                        "ERROR: You're attempting to store a Record (aka a relation) " +
                        "under a key where a non-relation is currently stored. This is " +
                        "not allowed. Here are the relevant details:\n" +
                        "KEY: \(key)\n" +
                        "CURRENT VALUE: \(extantObject)\n" +
                        "PROPOSED NEW OBJECT: \(relatedRecord)\n" +
                        "RECORD BEING MODIFIED: \(self)\n"
                    )
                    
                }
                
                if extantReference.recordID.recordName != relatedRecord.backingRemoteRecord.recordID.recordName {
                    configureReference()
                }
                
            } else {
                configureReference()
            }
            
            Record.ensureDatabasesAndRecordZonesMatch(between: self, and: relatedRecord)
            
            self.relatedRecordsCache[key] = relatedRecord
            
        } else {
            
            // Remove the CKReference if it exists
            configureReference()
            
            // Remove it from our internal cache of related Records
            self.relatedRecordsCache.removeValue(forKey: key)
            
        }
        
    }
    
    
    // MARK: - Internal Functions
    
    internal static func ensureDatabasesAndRecordZonesMatch(between providingRecord:Record, and dependentRecord:Record) {
        
        func mismatchFatalError(with typeName:String) -> Never {
            
            fatalError(
                "ERROR: A dependent Record must be in the same \(typeName) as the Record on which it is dependent. " +
                "Here are the Records (and respective \(typeName)s) between which you've attempted to create a dependency:" +
                "PROVIDING RECORD: \(providingRecord)\n" +
                "PROVIDING \(typeName.uppercased()): \(providingRecord.scope)\n" +
                "DEPENDENT RECORD: \(dependentRecord)\n" +
                "DEPENDENT \(typeName.uppercased()): \(dependentRecord.scope)\n"
            )
            
        }
        
        if dependentRecord.scope == nil {
            dependentRecord.scope = providingRecord.scope
        } else {
            guard dependentRecord.scope == providingRecord.scope else { mismatchFatalError(with: "database") }
        }
        
        if dependentRecord.recordZone == nil {
            dependentRecord.recordZone = providingRecord.recordZone
        } else {
            guard dependentRecord.recordZone == providingRecord.recordZone else { mismatchFatalError(with: "record zone") }
        }
        
    }
    
    
    // MARK: - Protocol Conformance
    
    var hashValue: Int {
        return self.backingRemoteRecord.hashValue
    }
    
    static func ==(left:Record, right:Record) -> Bool {
        return left.backingRemoteRecord == right.backingRemoteRecord
    }
    
}
