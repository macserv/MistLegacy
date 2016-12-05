//
//  DataCoordinator.swift
//  CloudKitTodo
//
//  Created by Matthew McCroskey on 12/5/16.
//  Copyright © 2016 Less But Better. All rights reserved.
//

import Foundation

internal class DataCoordinator {
    
    
    // MARK: - Private Properties
    
    // TODO: Implement code to keep this up to date
    internal var currentUser: CloudKitUser? = CloudKitUser()
    
    private var typeString: String {
        
        let mirror = Mirror(reflecting: self)
        let selfType = mirror.subjectType as! Record.Type
        let typeString = String(describing: selfType)
        
        return typeString
        
    }
    
    
    // MARK: - Public Functions
    
    func metadata(forKey key:String, retrievalCompleted:((Any?) -> Void)) {
        
        var metadata: Any?
        
        let execution = {
            
            if let selfMetadata = Mist.localMetadataStorage.value(forKey: self.typeString) as? [String : Any?] {
                metadata = selfMetadata[key]
            }
            
            metadata = nil
            
        }
        
        let completion = { retrievalCompleted(metadata) }
        
        Mist.localMetadataQueue.addOperation(withExecutionBlock: execution, completionBlock: completion)
        
    }
    
    func setMetadata(_ metadata:Any?, forKey key:String) {
        
        Mist.localMetadataQueue.addOperation  {
            
            if var selfMetadata = Mist.localMetadataStorage.value(forKey: self.typeString) as? [String : Any?] {
                
                selfMetadata[key] = metadata
                Mist.localMetadataStorage.setValue(selfMetadata, forKey: self.typeString)
                
            }
            
        }
        
    }
    
}
