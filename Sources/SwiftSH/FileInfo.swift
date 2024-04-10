//
//  FileInfo.swift
//  SwiftSH
//
//  Created by TJ on 4/9/24.
//  Copyright © 2024 Miguel de Icaza. All rights reserved.
//

import Foundation

@objcMembers public class FileInfo: NSObject {
    let fileSize: Int64
    let modificationTime: TimeInterval
    let accessTime: TimeInterval
    let permissions: UInt16
    
    init(fileSize: Int64, modificationTime: TimeInterval, accessTime: TimeInterval, permissions: UInt16) {
        self.fileSize = fileSize
        self.modificationTime = modificationTime
        self.accessTime = accessTime
        self.permissions = permissions
    }
    
    convenience init(fromStat statInfo: stat) {
        self.init(
            fileSize: Int64(statInfo.st_size),
            modificationTime: TimeInterval(statInfo.st_mtimespec.tv_sec),
            accessTime: TimeInterval(statInfo.st_atimespec.tv_sec),
            permissions: UInt16(statInfo.st_mode)
        )
    }
    
    convenience init(fromLocalPath localPath: String) throws {
        let fileManager = FileManager.default
        
        let attributes = try fileManager.attributesOfItem(atPath: localPath)
        let fileSize = attributes[.size] as? Int64 ?? 0
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
    func toData() -> Data {
        var data = Data()
        
        // FileSize (Int64)
        var fileSize = self.fileSize
        data.append(Data(bytes: &fileSize, count: MemoryLayout.size(ofValue: fileSize)))
        
        // ModificationTime (TimeInterval -> Double -> Int64 for simplicity)
        var modTime = Int64(self.modificationTime)
        data.append(Data(bytes: &modTime, count: MemoryLayout.size(ofValue: modTime)))
        
        // AccessTime (TimeInterval -> Double -> Int64 for simplicity)
        var accTime = Int64(self.accessTime)
        data.append(Data(bytes: &accTime, count: MemoryLayout.size(ofValue: accTime)))
        
        // Permissions (Int32)
        var perms = self.permissions
        data.append(Data(bytes: &perms, count: MemoryLayout.size(ofValue: perms)))
        
        return data
    }
}
