//
// The MIT License (MIT)
//
// Copyright (c) 2017 Tommaso Madonia
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
import Foundation

@_implementationOnly import CSSH
import CSwiftSH
//@_implementationOnly import CSwiftSH

public class SCPSession: SSHChannel {
    private let sshSession: SSHSession
    private var transferSessions: [String: TransferSession] = [:]

    private struct TransferSession {
//        TODO: Test multiple concurrent ssh sessions, channels etc.
        var scpChannel: SSHLibraryChannel?
        var transferId: String
        var isTransferring: Bool = true
        var fileInfo: FileInfo? = nil
        var startTime: Date? = Date()
        var endTime: Date?
        var downloadSession: DownloadSession? = nil
    }
    
    private struct DownloadSession {
        var stream: OutputStream?
        var totalBytesRead: Double = 0
        var completionCallback: TransferEndBlock? = nil
        var progressCallback: TransferProgressCallback? = nil
    }
    
    public override init(sshLibrary: SSHLibrary.Type = Libssh2.self, session: SSHSession, environment: [Environment] = [], terminal: Terminal? = nil, queueType: QueueType = .general) throws {
        self.sshSession = session
        try super.init(sshLibrary: sshLibrary, session: session, environment: environment, terminal: terminal, queueType: queueType)
    }
    
    public init(sshLibrary: SSHLibrary.Type = Libssh2.self, session: SSHSession, queueType: QueueType = .general) throws {
        self.sshSession = session
        try super.init(sshLibrary: sshLibrary, session: sshSession, queueType: queueType)
    }
    
    deinit {
        session.generalQueue.async {
            self.transferSessions.forEach { (_, session) in
                self.finishDownload(transferId: session.transferId)
                do {
                    if let channel = session.scpChannel {
                        try channel.closeChannel()
                    }
                } catch {}
            }
        }
    }
    
    // MARK: - Resource Management

    public override func close() {
        session.generalQueue.async {
            self.transferSessions.forEach { (_, session) in
                self.finishDownload(transferId: session.transferId)
            }
            let prevBlockingMode = super.session.session.blocking
            super.close()
            super.session.session.blocking = prevBlockingMode
        }
    }
    
    // MARK: Channel Data Available
    
    public override func notifyDataAvailable() {
        self.transferSessions.forEach { (_, session) in
            if session.isTransferring {
                self.readDownload(transferId: session.transferId)
            }
        }
    }
    
    private func readDownload(transferId: String) {
        session.generalQueue.async {
//            TODO: Fix guard statements to throw an exception or send an error to RTN
            guard var session = self.transferSessions[transferId] else { return }
            guard var downloadSession = session.downloadSession else { return }
            
            let completion = downloadSession.completionCallback
            let progress = downloadSession.progressCallback
            
            guard let fileInfo = session.fileInfo, let scpChannel = session.scpChannel, let stream = downloadSession.stream else {
                self.finishDownload(transferId: transferId)
                completion?(SSHError.SCP.fileRead(detail: "SCP socket read event unable to initialize"))
                return
            }
            
            do {
                let data = try scpChannel.read(expectedFileSize: UInt64(fileInfo.fileSize))
                if (data.count == 0) {
//                    No payload this read
                    return
                }
                
                // TODO: review types below and find out where the final packet's null byte comes from.
                let expectedFileSize = Double(fileInfo.fileSize)
                let packetSize = Double(data.count)
                let nextTotalBytesRead = downloadSession.totalBytesRead + packetSize
                
                let writeLength: Int
                if (nextTotalBytesRead > expectedFileSize) {
                    let diff = nextTotalBytesRead - expectedFileSize
                    let fixedPacketSized = packetSize - diff
                    writeLength = Int(fixedPacketSized)
                } else {
                    writeLength = Int(packetSize)
                }
                
                let writeResult = data.withUnsafeBytes {
                    let result = stream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: writeLength)
                    if (result < 0) {
                        self.finishDownload(transferId: transferId)
//                        TODO: Does this complete w/error correctly?
                        completion?(SSHError.SCP.unknown(detail: "Stream error: \(downloadSession.stream?.streamError?.localizedDescription ?? "unknown")"))
                    }
                    return result
                }
                
                if (writeResult < 0) {
                    return
                }
//                TODO: There's a race condition or something... we're in the queue block, strange.
//                      This issue didn't occur before refactoring, so should be able to ID root cause based on changes.
                downloadSession.totalBytesRead += Double(writeResult)
                
                session.downloadSession = downloadSession
                self.transferSessions[transferId] = session
                
                if (downloadSession.totalBytesRead == expectedFileSize) {
                    completion?(nil)
                } else if (downloadSession.totalBytesRead > expectedFileSize) {
                    completion?(SSHError.SCP.fileRead(detail: "Received too much data"))
                } else if (!stream.hasSpaceAvailable) {
                    completion?(SSHError.SCP.fileRead(detail: "No space available"))
                } else {
                    let elapsedTime = session.startTime.map { Date().timeIntervalSince($0) } ?? 0
                    let transferRate = elapsedTime > 0 ? Double(downloadSession.totalBytesRead) / elapsedTime : 0
                    
                    progress?(downloadSession.totalBytesRead, transferRate)
                }
            } catch {
                self.finishDownload(transferId: transferId)
                completion?(error)
            }
        }
    }

    // MARK: - Download

    /// Initiates a download from a specified remote path to a local file path without a completion callback.
    /// - Parameters:
    ///   - transferId: The transfer identifer.
    ///   - from: The remote path of the file to download.
    ///   - to: The local file path where the downloaded file will be saved.
    /// - Returns: Self, to allow for method chaining.
    @discardableResult
    public func download(_ transferId: String, from: String, to path: String) -> Self {
        self.download(transferId, from: from, to: path, start: nil, completion: nil, progress: nil)
        return self
    }

    /// Initiates a download from a specified remote path to a local file path with an optional completion callback.
    /// The completion callback provides details about the file and any error that occurred.
    /// - Parameters:
    ///   - transferId: The transfer identifer.
    ///   - from: The remote path of the file to download.
    ///   - to: The local file path where the downloaded file will be saved.
    ///   - start: A start block that provides the download FileInfo.
    ///   - completion: An optional SCPReadCompletionBlock that is called upon completion of the download operation.
    ///                 The callback provides fileInfo, file data (if any), and an error (if any).
    ///   - progress: An optional ReadProgressCallback that is called on progress updates.
    ///                 The callback provides bytesTransferred.
    public func download(_ transferId: String, from: String, to path: String, start: TransferStartBlock?, completion: TransferEndBlock?, progress: TransferProgressCallback?) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            do {
                try fileManager.removeItem(atPath: path)
            } catch {
                completion?(SSHError.SCP.unknown(detail: "Failed to truncate file to download"))
                return
            }
        }
        if let stream = OutputStream(toFileAtPath: path, append: true) {
            stream.open()
            self.download(transferId, from: from, to: stream, start: start, completion: completion, progress: progress)
        } else {
            completion?(SSHError.SCP.unknown(detail: "Unable to open file stream for download path \(path)"))
        }
    }

    /// Initiates a download from a specified remote path to an OutputStream without a completion callback.
    /// - Parameters:
    ///   - transferId: The transfer identifer.
    ///   - from: The remote path of the file to download.
    ///   - to: The OutputStream to which the downloaded file will be written.
    /// - Returns: Self, to allow for method chaining.
    @discardableResult
    public func download(_ transferId: String, from: String, to stream: OutputStream) -> Self {
        self.download(transferId, from: from, to: stream, start: nil, completion: nil, progress: nil)
        return self
    }
    
    /// Initiates a download from a specified remote path and provides the downloaded data via a completion callback.
    /// This method uses an in-memory OutputStream to hold the downloaded data.
    /// - Parameters:
    ///   - transferId: The transfer identifer.
    ///   - from: The remote path of the file to download.
    ///   - start: A TransferStartBlock that provides the upload FileInfo.
    ///   - completion: A TransferEndBlock that is called upon completion of the upload operation.
    ///                 The callback provides an error (if any).
    ///   - progress: A TransferProgressCallback that is called on progress updates.
    ///                 The callback provides bytesTransferred and transferRate.
    public func download(_ transferId: String, from: String, start: @escaping TransferStartBlock, completion: @escaping TransferEndBlock, progress: @escaping TransferProgressCallback) {
        let stream = OutputStream.toMemory()
        stream.open()
        self.download(transferId, from: from, to: stream) { fileInfo in
            start(fileInfo)
        } completion: { error in
            if stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) is Data {
                completion(error)
            } else {
                completion(error ?? SSHError.SCP.unknown (detail: "Unable to read download stream"))
            }
        } progress: { fileInfo, bytesRead in
            progress(fileInfo, bytesRead)
        }
    }

    /// Initiates a download from a specified remote path to an OutputStream with an optional completion callback.
    /// The completion callback provides details about the file, and any error that occurred.
    /// This method asynchronously reads the data from the SCP channel and writes it to the provided OutputStream.
    /// - Parameters:
    ///   - transferId: The transfer identifer.
    ///   - from: The remote path of the file to download.
    ///   - to: The OutputStream to which the downloaded file data will be written.
    ///   - start: An optional TransferStartBlock that provides the upload FileInfo.
    ///   - completion: An optional TransferEndBlock that is called upon completion of the upload operation.
    ///                 The callback provides an error (if any).
    ///   - progress: An optional TransferProgressCallback that is called on progress updates.
    ///                 The callback provides bytesTransferred and transferRate.
    public func download(_ transferId: String, from: String, to stream: OutputStream, start: TransferStartBlock?, completion: TransferEndBlock?, progress: TransferProgressCallback?) {
        let completionWrapper: TransferEndBlock = { error in
            completion?(error)
            self.finishDownload(transferId: transferId)
        }
        
        let newDownloadSession = DownloadSession(stream: stream, completionCallback: completionWrapper, progressCallback: progress)
        let newSession = TransferSession(scpChannel: self.channel, transferId: transferId, downloadSession: newDownloadSession)
        
        self.transferSessions[transferId] = newSession

        self.openSCPChannelForDownload(transferId: transferId, remotePath: from, start: { fileInfo in
            var session = self.transferSessions[transferId]
            session?.fileInfo = fileInfo
            start?(fileInfo)
        }, completion: { [weak self] fileInfo, error in
            guard let self = self else {
                completion?(SSHError.SCP.unknown(detail: "SCP is not initialized"))
                return
            }
            
            guard let fileInfo = fileInfo, error == nil else {
                completion?(error)
                self.finishDownload(transferId: transferId)
                return
            }
            
            self.transferSessions[transferId]?.fileInfo = fileInfo
        })
    }
    
    /// Finishes a download
    /// - Parameters:
    ///   - transferId: The transfer identifer.
    func finishDownload(transferId: String) {
        if let session = self.transferSessions[transferId] {
//            TODO: Fix guard statements to throw an exception or send an error to RTN
            guard let downloadSession = session.downloadSession else { return }
            
//            TODO: Do we only need isTransferring/endTime if we're tracking transfer history?
//            session.isTransferring = false
//            session.endTime = Date()
            
            if let stream = downloadSession.stream {
                stream.close()
            }
            
//            TODO: Do we need transfer history for any reason? If so, make removeValue optional.
            self.transferSessions.removeValue(forKey: transferId)
        }
    }

    // MARK: - Upload
    
    /// Initiates an upload from a local file path without requiring a completion callback.
    /// - Parameters:
    ///   - transferId: The transfer identifer.
    ///   - from: The local path of the file to upload.
    ///   - to: The remote path to which the uploaded file will be written.
    /// - Returns: Self, to allow for method chaining.
    @discardableResult
    public func upload(_ transferId: String, from: String, to: String) -> Self {
        self.upload(transferId, from: from, to: to, start: nil, completion: nil, progress: nil)
        return self
    }

    /// Initiates an upload from a local file path with an optional completion callback.
    /// - Parameters:
    ///   - transferId: The transfer identifer.
    ///   - from: The local path of the file to upload.
    ///   - to: The remote path to which the uploaded file will be written.
    ///   - start: An optional TransferStartBlock that provides the upload FileInfo.
    ///   - completion: An optional TransferEndBlock that is called upon completion of the upload operation.
    ///                 The callback provides an error (if any).
    ///   - progress: An optional TransferProgressCallback that is called on progress updates.
    ///                 The callback provides bytesTransferred and transferRate.
    public func upload(_ transferId: String, from: String, to: String, start: TransferStartBlock?, completion: TransferEndBlock?, progress: TransferProgressCallback?) {
        do {
            var newSession = TransferSession(scpChannel: self.channel, transferId: transferId)
            
            let fileURL = URL(fileURLWithPath: from)
            
            let fileData = try Data(contentsOf: fileURL)
            let fileSize = UInt64(fileData.count)

            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let posixPermissions = attributes[.posixPermissions] as? NSNumber {
                let permissionsString = String(format:"%o", posixPermissions.uintValue)
                print("File permissions: \(permissionsString)")
                
                let modificationDate = attributes[.modificationDate] as? Date ?? Date()
                let modificationTimeInterval = modificationDate.timeIntervalSince1970
                let fileInfo = FileInfo(fileSize: Int64(fileSize), modificationTime: modificationTimeInterval, accessTime: nil, permissions: UInt16(truncating: posixPermissions))
                
                newSession.fileInfo = fileInfo
                
                start?(fileInfo)
            } else {
//                TODO: If transfer history is supported, we will need to update transferSessions on all errors (use a helper func).
                completion?(SSHError.SCP.fileRead(detail: "Permissions not found for file to upload."))
                return
            }
            
            self.transferSessions[transferId] = newSession
            
            self.openSCPChannelForUpload(transferId: transferId, localPath: from, remotePath: to, completion: { error in
                guard error == nil else {
                    completion?(error)
                    return
                }
                
                self.session.generalQueue.async {
                    let session = self.transferSessions[transferId]
                    
                    guard let scpChannel = session?.scpChannel else {
                        self.finishDownload(transferId: transferId)
                        completion?(SSHError.SCP.fileRead(detail: "SCP upload channel unavailable"))
                        return
                    }
                    
                    do {
                        let result = scpChannel.write(fileData, progress: progress)
                        
                        let isUploadSuccessful = result.bytesSent == fileSize
                        if !isUploadSuccessful {
                            completion?(SSHError.SCP.uploadVerification(detail: "Upload verification failed file size."))
                            return
                        }
                        
                        try scpChannel.closeChannel()
                        
                        self.transferSessions[transferId] = session
                        
                        completion?(result.error)
                    } catch {
                        self.finishDownload(transferId: transferId)
                        completion?(error)
                    }
                }
            })
        } catch {
            completion?(error)
        }
    }
    
    /// Finishes an upload
    /// - Parameters:
    ///   - transferId: The transfer identifer.
    func finishUpload(transferId: String) {
        if var session = self.transferSessions[transferId] {
            session.isTransferring = false
            session.endTime = Date()
            
//            TODO: Review close() behavior
//            self.close()
            
            self.transferSessions.removeValue(forKey: transferId)
        }
    }
}

extension SCPSession {
    /// Opens an SCP channel for downloading
    /// - Parameters:
    ///   - transferId: The transfer identifer.
    ///   - remotePath: The remote path to download.
    ///   - start: A TransferStartBlock that provides the download FileInfo.
    ///   - completion: A TransferEndBlock that is called upon completion of the download operation.
    ///                 The callback provides the FileInfo (if any) and an error (if any).
    public func openSCPChannelForDownload(transferId: String, remotePath: String, start: @escaping (FileInfo) -> Void, completion: @escaping (FileInfo?, Error?) -> Void) {
        session.generalQueue.async(completion: { (error: Error?) in
            if let error = error {
                self.finishDownload(transferId: transferId)
                completion(nil, error)
            }
        }, block: {
            do {
                var transferSession = self.transferSessions[transferId]
                
                let scpChannel = self.sshSession.session.makeChannel()
                
                let fileInfo = try scpChannel.openSCPChannel(remotePath: remotePath)
                
                transferSession?.scpChannel = scpChannel
                
                start(fileInfo)
                
                transferSession?.isTransferring = true
                
                self.transferSessions[transferId] = transferSession
                
//            TODO: Add a prop for scp max file size
//            if fileInfo.fileSize > MAX_FILE_SIZE {
//                completion(nil, NSError(domain: "SCPSession", code: 102, userInfo: [NSLocalizedDescriptionKey: "File is too large for download."]))
//                return
//            }
                
                if (fileInfo.permissions & S_IRUSR) == 0 {
                    self.finishDownload(transferId: transferId)
                    completion(nil, SSHError.SCP.fileRead(detail: "Permission denied: You do not have read access to the specified file on the remote host."))
                    return
                }
                
                completion(fileInfo, nil)
            } catch {
                self.finishDownload(transferId: transferId)
                completion(nil, error)
            }
        })
    }
    
    /// Opens an SCP channel for uploading
    /// - Parameters:
    ///   - transferId: The transfer identifer.
    ///   - localPath: The local path to upload from.
    ///   - remotePath: The remote path to upload to.
    ///   - completion: A TransferEndBlock that is called upon completion of the upload operation.
    ///                 The callback provides an error (if any).
    public func openSCPChannelForUpload(transferId: String, localPath: String, remotePath: String, completion: @escaping (Error?) -> Void) {
        session.generalQueue.async(completion: { (error: Error?) in
            if let error = error {
                self.finishUpload(transferId: transferId)
                completion(error)
            }
        }, block: {
            do {
                var transferSession = self.transferSessions[transferId]
                
                let fileInfo = try FileInfo.init(fromLocalPath: localPath)
                
                transferSession?.scpChannel = self.sshSession.session.makeChannel()
                
                try transferSession?.scpChannel?.openSCPChannel(localPath: remotePath, mode: Int32(fileInfo.permissions), fileSize: UInt64(fileInfo.fileSize), mtime: fileInfo.modificationTime, atime: fileInfo.accessTime)
                
                self.transferSessions[transferId] = transferSession
                                
                completion(nil)
            } catch {
                completion(error)
            }
        })
    }
}
