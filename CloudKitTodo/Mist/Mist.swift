//
//  Mist.swift
//  CloudKitTodo
//
//  Created by Matthew McCroskey on 12/1/16.
//  Copyright © 2016 Less But Better. All rights reserved.
//

import Foundation
import CloudKit


typealias StorageScope = CKDatabaseScope
typealias RecordIdentifier = String
typealias RecordZoneIdentifier = String
typealias RelationshipDeleteBehavior = CKReferenceAction
typealias FilterClosure = ((Record) throws -> Bool)
typealias SortClosure = ((Record,Record) throws -> Bool)


struct Configuration {
    
    var `public`: Scoped
    var `private`: Scoped
    
    struct Scoped {
        
        var pullsRecordsMatchingDescriptors: [RecordDescriptor]?
        
    }
    
}

struct RecordDescriptor {
    
    let type: Record.Type
    let descriptor: NSPredicate
    
}


class Mist {
    
    
    // MARK: - Configuration Properties
    
    static var config: Configuration = Configuration(
        public: Configuration.Scoped(pullsRecordsMatchingDescriptors: nil),
        private: Configuration.Scoped(pullsRecordsMatchingDescriptors: nil)
    )
    
    
    // MARK: - Public Properties
    
    // TODO: Implement code to keep this up to date
    static var currentUser: CloudKitUser? = nil
    
    
    // MARK: - Fetching Items
    
    static func get(_ identifier:RecordIdentifier, from:StorageScope, fetchDepth:Int = -1, finished:((RecordOperationResult, Record?) -> Void)) {
        
        guard self.currentUser != nil else {
            
            finished(RecordOperationResult(succeeded: false, error: self.noCurrentUserError.errorObject()), nil)
            return
            
        }
        
        self.localDataCoordinator.retrieveRecord(matching: identifier, fromStorageWithScope: from, fetchDepth: fetchDepth, retrievalCompleted: finished)
        
    }
    
    static func find(
        recordsOfType type:Record.Type, where filter:FilterClosure, within:StorageScope,
        sortedBy:SortClosure?=nil, fetchDepth:Int = -1, finished:((RecordOperationResult, [Record]?) -> Void)
    ) {
        
        guard self.currentUser != nil else {
            
            finished(RecordOperationResult(succeeded: false, error: self.noCurrentUserError.errorObject()), nil)
            return
            
        }
        
        self.localDataCoordinator.retrieveRecords(withType:type, matching: filter, inStorageWithScope: within, fetchDepth: fetchDepth, retrievalCompleted: finished)
        
    }
    
    static func find(
        recordsOfType type:Record.Type, where predicate:NSPredicate, within:StorageScope,
        sortedBy:SortClosure?=nil, fetchDepth:Int = -1, finished:((RecordOperationResult, [Record]?) -> Void)
    ) {
        
        guard self.currentUser != nil else {
            
            finished(RecordOperationResult(succeeded: false, error: self.noCurrentUserError.errorObject()), nil)
            return
            
        }
        
        self.localDataCoordinator.retrieveRecords(withType:type, matching: predicate, inStorageWithScope: within, fetchDepth:fetchDepth, retrievalCompleted: finished)
        
    }
    
    
    // MARK: - Modifying Items
    
    static func add(_ record:Record, to:StorageScope, finished:((RecordOperationResult) -> Void)?=nil) {
        
        guard self.currentUser != nil else {
            
            if let finished = finished {
                finished(RecordOperationResult(succeeded: false, error: self.noCurrentUserError.errorObject()))
            }
            
            return
            
        }
        
        self.localDataCoordinator.addRecord(record, toStorageWith: to, finished: finished)
        
    }
    
    static func add(_ records:Set<Record>, to:StorageScope, finished:((RecordOperationResult) -> Void)?=nil) {
        
        guard self.currentUser != nil else {
            
            if let finished = finished {
                finished(RecordOperationResult(succeeded: false, error: self.noCurrentUserError.errorObject()))
            }
            
            return
            
        }
        
        self.localDataCoordinator.addRecords(records, toStorageWith: to, finished: finished)
        
    }
    
    static func remove(_ record:Record, from:StorageScope, finished:((RecordOperationResult) -> Void)?=nil) {
        
        guard self.currentUser != nil else {
            
            if let finished = finished {
                finished(RecordOperationResult(succeeded: false, error: self.noCurrentUserError.errorObject()))
            }
            
            return
            
        }
        
        self.localDataCoordinator.removeRecord(record, fromStorageWith: from, finished: finished)
        
    }
    
    static func remove(_ records:Set<Record>, from:StorageScope, finished:((RecordOperationResult) -> Void)?=nil) {
        
        guard self.currentUser != nil else {
            
            if let finished = finished {
                finished(RecordOperationResult(succeeded: false, error: self.noCurrentUserError.errorObject()))
            }
            
            return
            
        }
        
        self.localDataCoordinator.removeRecords(records, fromStorageWith: from, finished: finished)
        
    }
    
    
    // MARK: - Syncing Items
    
    static func sync(_ qOS:QualityOfService?=QualityOfService.default, finished:((SyncSummary) -> Void)?=nil) {
        
        // TODO: Guard sync against having no user
//        guard self.currentUser != nil else {
//            
//            if let finished = finished {
//                finished(RecordOperationResult(succeeded: false, error: self.noCurrentUserError.errorObject()))
//            }
//            
//            return
//            
//        }
        
        self.synchronizationCoordinator.sync(qOS, finished: finished)
        
    }
    
    
    // MARK: - Internal Properties
    
    internal static let localRecordsQueue = Queue()
    internal static let localMetadataQueue = Queue()
    internal static let localCachedRecordChangesQueue = Queue()
    
    internal static let localDataCoordinator = LocalDataCoordinator()
    internal static let remoteDataCoordinator = RemoteDataCoordinator()
    internal static let synchronizationCoordinator = SynchronizationCoordinator()
    
    internal static let noCurrentUserError = ErrorStruct(
        code: 401, title: "User Not Authenticated",
        failureReason: "The user is not currently logged in to iCloud. The user must be logged in in order for us to save data to the private or shared scopes.",
        description: "Get the user to log in and try this request again."
    )
    
}

