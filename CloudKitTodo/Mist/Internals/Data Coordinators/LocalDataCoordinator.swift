//
//  LocalDataCoordinator.swift
//  CloudKitTodo
//
//  Created by Matthew McCroskey on 12/5/16.
//  Copyright © 2016 Less But Better. All rights reserved.
//

import Foundation
import CloudKit

internal class LocalDataCoordinator : DataCoordinator {
    
    
    // MARK: - Private Properties
    
    private enum RecordChangeType {
        case addition
        case removal
    }
    
    
    // MARK: - Fetching Locally-Cached Items
    
    private func associateRelatedRecords(for record:Record?, in scope:StorageScope, using fetchDepth:Int) {
        
        if let record = record, fetchDepth != 0 {
            
            for relatedRecordDataSetKeyPair in record.relatedRecordDataSetKeyPairs {
                
                let propertyName = relatedRecordDataSetKeyPair.key
                let identifier = relatedRecordDataSetKeyPair.value.identifier
                let action = relatedRecordDataSetKeyPair.value.action
                
                let newFetchDepth: Int
                if fetchDepth > 0 {
                    newFetchDepth = (fetchDepth - 1)
                } else {
                    newFetchDepth = fetchDepth
                }
                
                if let relatedRecord = self.retrieveRecord(matching: identifier, fromStorageWithScope: scope, fetchDepth: newFetchDepth) {
                    record.setRelatedRecord(relatedRecord, forKey: propertyName, withRelationshipDeleteBehavior: action)
                }
                
            }
            
        }
        
    }
    
    internal func userRecordExists(withIdentifier identifier:RecordIdentifier) -> Record? {
        
        let cacheForUserRecord = self.localCacheCoordinator.userCache(associatedWith: identifier)
        
        if let userRecord = cacheForUserRecord.publicCache.defaultRecordZone.cachedRecordWithIdentifier(identifier) {
            return userRecord
        } else {
            return nil
        }
        
    }
    
    internal func setCurrentUser(_ userRecord:CloudKitUser) {
        
        let userCache = self.localCacheCoordinator.userCache(associatedWith: userRecord.identifier)
        userCache.publicCache.defaultRecordZone.addCachedRecord(userRecord)
        
    }
    
    func retrieveRecord(matching identifier:RecordIdentifier, fromStorageWithScope scope:StorageScope, fetchDepth:Int) -> Record? {
        
        let record = self.currentUserCache.scopedCache(withScope: scope).defaultRecordZone.cachedRecordWithIdentifier(identifier)
        
        self.associateRelatedRecords(for: record, in: scope, using: fetchDepth)
        
        return record
        
    }
    
    func retrieveRecords(withType type:Record.Type?=nil, matching filter:((Record) throws -> Bool), inStorageWithScope scope:StorageScope, fetchDepth:Int) -> [Record] {
        
        let typeFilter: ((Record) throws -> Bool)?
        if let type = type {
            let typeString = String(describing: type)
            typeFilter = { $0.typeString == typeString }
        } else {
            typeFilter = nil
        }
        
        let records: [Record]
        
        do {
            
            let initialRecords = try self.currentUserCache.scopedCache(withScope: scope).defaultRecordZone.cachedRecords(matching: filter)
            
            let typeFilteredRecords: [Record]
            if let typeFilter = typeFilter {
                typeFilteredRecords = try initialRecords.filter(typeFilter)
            } else {
                typeFilteredRecords = initialRecords
            }
            
            records = typeFilteredRecords
            
            for record in records {
                self.associateRelatedRecords(for: record, in: scope, using: fetchDepth)
            }
            
        } catch let fetchError {
            
            fatalError("Record retrieval failed due to error: \(fetchError)")
            
        }
        
        return records
        
    }
    
    func retrieveRecords(withType type:Record.Type?=nil, matching predicate:NSPredicate, inStorageWithScope scope:StorageScope, fetchDepth:Int) -> [Record] {
        return self.retrieveRecords(withType: type, matching: { predicate.evaluate(with: $0) }, inStorageWithScope: scope, fetchDepth: fetchDepth)
    }
    
    
    // MARK: - Making Local Changes
    
    func addRecord(_ record:Record, toStorageWith scope:StorageScope) {
        self.addRecords(Set([record]), toStorageWith: scope)
    }
    
    func addRecords(_ records:Set<Record>, toStorageWith scope:StorageScope) {
        self.performChange(ofType: .addition, on: records, within: scope)
    }
    
    func removeRecord(_ record:Record, fromStorageWith scope:StorageScope) {
        self.removeRecords(Set([record]), fromStorageWith: scope)
    }
    
    func removeRecords(_ records:Set<Record>, fromStorageWith scope:StorageScope) {
        self.performChange(ofType: .removal, on: records, within: scope)
    }
    
    private func performChange(ofType changeType:RecordChangeType, on records:Set<Record>, within scope:StorageScope) {
        
        guard records.count > 0 else {
            return
        }
        
        switch changeType {
            
        case .addition:
            
            for record in records {
                
                guard ((record.scope == nil) || (record.scope == scope)) else {
                    fatalError("The Record cannot be saved to the \(scope) scope -- it's already saved in the \(record.scope) scope.")
                }
                
                record.scope = scope
                
                if record.recordZone == nil {
                    
                    switch scope {
                        
                    case .public:
                        record.recordZone = self.currentUserCache.scopedCache(withScope: .public).defaultRecordZone
                        
                    default:
                        
                        if let parent = record.parent, let parentRecordZone = parent.recordZone {
                            
                            record.recordZone = parentRecordZone
                            
                        } else {
                            
                            let recordZone = RecordZone(identifier: UUID().uuidString)
                            self.currentUserCache.scopedCache(withScope: scope).addCachedRecordZone(recordZone)
                            record.recordZone = recordZone
                            
                        }
                        
                    }
                    
                }
                
                switch scope {
                    
                case .public:
                    
                    guard record.share == nil else {
                        fatalError("Records with associated shares cannot be added to the public scope; the public scope doesn't support shares.")
                    }
                    
                case .shared:
                    
                    guard record.share != nil || record.parent != nil else {
                        fatalError("Every Record stored in the shared scope must have an associated share, or a parent, or both.")
                    }
                    
                case .private:
                    break
                    
                }
                
                let relatedRecords = Set(record.relatedRecordsCache.values)
                let children = record.children
                let associatedRecords = relatedRecords.union(children)
                for associatedRecord in associatedRecords {
                    
                    Record.ensureDatabasesAndRecordZonesMatch(between: record, and: associatedRecord)
                    
                    let identifier = associatedRecord.identifier
                    
                    let relatedRecord = self.retrieveRecord(matching: identifier, fromStorageWithScope: scope, fetchDepth: -1)
                    if relatedRecord == nil {
                        self.addRecord(associatedRecord, toStorageWith: scope)
                    }
                    
                }
                
                guard let recordZone = record.recordZone else {
                    fatalError("Record Zone should always be set for Record at this point.")
                }
                
                recordZone.addCachedRecord(record)
                self.currentUserCache.scopedCache(withScope: scope).addCachedRecordZone(recordZone)
                
            }
            
        case .removal:
            
            for record in records {
                
                // If a Record doesn't have a Record Zone, 
                // then it's never been added to anything, 
                // so there's nothing from which to remove it
                guard let recordZone = record.recordZone else {
                    return
                }
                
                recordZone.removeCachedRecordWithIdentifier(record.identifier)
                
            }
            
        }
        
    }
    
}
