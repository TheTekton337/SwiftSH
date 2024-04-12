//
//  FileInfo.swift
//  SwiftSH
//
//  Created by TJ on 4/9/24.
//  Copyright © 2024 Miguel de Icaza. All rights reserved.
//

import Foundation

@objcMembers public class FileInfo: NSObject {
    let fileSize: Int32
    let modificationTime: TimeInterval
    let accessTime: TimeInterval
    let permissions: UInt16
    
    init(fileSize: Int32, modificationTime: TimeInterval, accessTime: TimeInterval, permissions: UInt16) {
        self.fileSize = fileSize
        self.modificationTime = modificationTime
        self.accessTime = accessTime
        self.permissions = permissions
    }
    
    convenience init(fromStat statInfo: stat) {
        self.init(
            fileSize: Int32(statInfo.st_size),
            modificationTime: TimeInterval(statInfo.st_mtimespec.tv_sec),
            accessTime: TimeInterval(statInfo.st_atimespec.tv_sec),
            permissions: UInt16(statInfo.st_mode)
        )
    }
    
    convenience init(fromLocalPath localPath: String) throws {
        let fileManager = FileManager.default
        
        let attributes = try fileManager.attributesOfItem(atPath: localPath)
        let fileSize = attributes[.size] as? Int32 ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date.init()
        let accessDate = attributes[.creationDate] as? Date ?? Date.init()
        let permissions = attributes[.posixPermissions] as? UInt16 ?? 0
        
        self.init(
            fileSize: fileSize,
            modificationTime: modificationDate.timeIntervalSince1970,
            accessTime: accessDate.timeIntervalSince1970,
            permissions: permissions
        )
    }
}

extension FileInfo {
    @objc
    public func toData() -> Data {
        var data = Data()
        
        // FileSize (Int32)
        var fileSize = Int64(self.fileSize)
        data.append(Data(bytes: &fileSize, count: MemoryLayout.size(ofValue: fileSize)))
        
        // ModificationTime (TimeInterval -> Double -> Int32 for simplicity)
        var modTime = Double(self.modificationTime)
        data.append(Data(bytes: &modTime, count: MemoryLayout.size(ofValue: modTime)))
        
        // AccessTime (TimeInterval -> Double -> Int32 for simplicity)
        var accTime = Double(self.accessTime)
        data.append(Data(bytes: &accTime, count: MemoryLayout.size(ofValue: accTime)))
        
        // Permissions (Int16)
        var perms = Int16(self.permissions)
        data.append(Data(bytes: &perms, count: MemoryLayout.size(ofValue: perms)))
        
        return data
    }
}
