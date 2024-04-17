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
    
    private var scpChannel: SSHLibraryChannel?
    
    private var isDownloading: Bool = false
    
    private var readStream: OutputStream?
    private var totalBytesRead = 0
    private var readFileInfo: FileInfo?
    private var readCompletionCallback: SCPReadCompletionBlock?
    private var readProgressCallback: ReadProgressCallback?
    
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
            self.finishDownload()
            
            do {
                if (self.channel != nil) {
                    try self.channel.closeChannel()
                }
            } catch {}
        }
    }
    
    // MARK: - Resource Management

    public override func close() {
        session.generalQueue.async {
            self.finishDownload()
            let prevBlockingMode = super.session.session.blocking
            super.close()
            super.session.session.blocking = prevBlockingMode
        }
    }
    
    // MARK: Channel Data Available
    
    public override func notifyDataAvailable() {
        if (self.isDownloading) {
            self.readDownload()
        }
    }
    
    private func readDownload() {
        session.generalQueue.async {
            let completion = self.readCompletionCallback
            let progress = self.readProgressCallback
            
            guard let fileInfo = self.readFileInfo, let scpChannel = self.scpChannel, let stream = self.readStream else {
                self.finishDownload()
                completion?(nil, nil, SSHError.SCP.fileRead(detail: "SCP socket read event unable to initialize"))
                return
            }
            
            do {
                let data = try scpChannel.read(expectedFileSize: UInt64(fileInfo.fileSize), progress: progress)
                if (data.count == 0) {
//                    No payload this read
                    return
                }
                
                // TODO: find out where the final packet's null byte comes from.
                let expectedFileSize = Int(fileInfo.fileSize)
                let packetSize = data.count
                let nextTotalBytesRead = self.totalBytesRead + packetSize
                
                let writeLength: Int
                if (nextTotalBytesRead > expectedFileSize) {
                    let diff = nextTotalBytesRead - expectedFileSize
                    let fixedPacketSized = packetSize - diff
                    writeLength = fixedPacketSized
                } else {
                    writeLength = packetSize
                }
                
                let writeResult = data.withUnsafeBytes {
                    let result = stream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: writeLength)
                    if (result < 0) {
                        self.finishDownload()
                        completion?(nil, nil, SSHError.SCP.unknown(detail: "Stream error: \(self.readStream?.streamError?.localizedDescription ?? "unknown")"))
                    }
                    return result
                }
                
                if (writeResult < 0) {
                    return
                }
                self.totalBytesRead += writeResult
                
                if (self.totalBytesRead == expectedFileSize) {
                    completion?(fileInfo, data, nil)
                } else if (self.totalBytesRead > expectedFileSize) {
                    completion?(nil, nil, SSHError.SCP.fileRead(detail: "Received too much data"))
                } else if (!stream.hasSpaceAvailable) {
                    completion?(nil, nil, SSHError.SCP.fileRead(detail: "No space available"))
                }
            } catch {
                self.finishDownload()
                completion?(fileInfo, nil, error)
            }
        }
    }
    
    func finishDownload() {
        self.isDownloading = false
        
        if (readStream != nil) {
            readStream?.close()
        }
    }

    // MARK: - Download

    /// Initiates a download from a specified remote path to a local file path without a completion callback.
    /// - Parameters:
    ///   - from: The remote path of the file to download.
    ///   - to: The local file path where the downloaded file will be saved.
    /// - Returns: Self, to allow for method chaining.
    @discardableResult
    public func download(_ from: String, to path: String) -> Self {
        self.download(from, to: path, completion: nil, progress: nil)
        return self
    }

    /// Initiates a download from a specified remote path to a local file path with an optional completion callback.
    /// The completion callback provides details about the file and any error that occurred.
    /// - Parameters:
    ///   - from: The remote path of the file to download.
    ///   - to: The local file path where the downloaded file will be saved.
    ///   - completion: An optional SCPReadCompletionBlock that is called upon completion of the download operation.
    ///                 The callback provides fileInfo, file data (if any), and an error (if any).
    ///   - progress: An optional ReadProgressCallback that is called on progress updates.
    ///                 The callback provides bytesTransferred
    public func download(_ from: String, to path: String, completion: SCPReadCompletionBlock?, progress: ReadProgressCallback?) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            do {
                try fileManager.removeItem(atPath: path)
            } catch {
                completion?(nil, nil, SSHError.SCP.unknown(detail: "Failed to truncate file to download"))
                return
            }
        }
        if let stream = OutputStream(toFileAtPath: path, append: true) {
            stream.open()
            self.download(from, to: stream, completion: completion, progress: progress)
        } else {
            completion?(nil, nil, SSHError.SCP.unknown(detail: "Unable to open file stream for download path \(path)"))
        }
    }

    /// Initiates a download from a specified remote path to an OutputStream without a completion callback.
    /// - Parameters:
    ///   - from: The remote path of the file to download.
    ///   - to: The OutputStream to which the downloaded file will be written.
    /// - Returns: Self, to allow for method chaining.
    @discardableResult
    public func download(_ from: String, to stream: OutputStream) -> Self {
        self.download(from, to: stream, completion: nil, progress: nil)
        return self
    }
    
    /// Initiates a download from a specified remote path and provides the downloaded data via a completion callback.
    /// This method uses an in-memory OutputStream to hold the downloaded data.
    /// - Parameters:
    ///   - from: The remote path of the file to download.
    ///   - completion: A completion block that provides the downloaded data (if any) and an error (if any).
    public func download(_ from: String, completion: @escaping SCPReadCompletionBlock, progress: @escaping ReadProgressCallback) {
        let stream = OutputStream.toMemory()
        stream.open()
        self.download(from, to: stream) { fileInfo, data, error in
            if let data = stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data {
                completion(fileInfo, data, error)
            } else {
                completion(nil, nil, error ?? SSHError.SCP.unknown (detail: "Download lacks the data"))
            }
        } progress: { bytesRead in
            progress(bytesRead)
        }
    }

    /// Initiates a download from a specified remote path to an OutputStream with an optional completion callback.
    /// The completion callback provides details about the file, and any error that occurred.
    /// This method asynchronously reads the data from the SCP channel and writes it to the provided OutputStream.
    /// - Parameters:
    ///   - from: The remote path of the file to download.
    ///   - to: The OutputStream to which the downloaded file data will be written.
    ///   - completion: An optional SCPReadCompletionBlock that is called upon completion of the download operation.
    ///                 The callback provides fileInfo, file data (if any), and an error (if any).
    ///   - progress: An optional ReadProgressCallback that is called on progress updates.
    ///                 The callback provides bytesTransferred
    public func download(_ from: String, to stream: OutputStream, completion: SCPReadCompletionBlock?, progress: ReadProgressCallback?) {
        let completionWrapper: SCPReadCompletionBlock = { fileInfo, dat, error in
            completion?(fileInfo, dat, error)
            self.finishDownload()
        }
        self.readCompletionCallback = completionWrapper
        self.readProgressCallback = progress
        self.readStream = stream
        
        self.openSCPChannelForDownload(remotePath: from, completion: { [weak self] fileInfo, error in
            guard let self = self else {
                completion?(nil, nil, SSHError.SCP.unknown(detail: "SCP is not initialized"))
                return
            }
            
            guard let fileInfo = fileInfo, error == nil else {
                completion?(fileInfo, nil, error)
                self.finishDownload()
                return
            }
            
            self.readFileInfo = fileInfo
        })
    }

    // MARK: - Upload

    /// Initiates an upload from a local file path without requiring a completion callback.
    /// - Parameter localPath: The path to the local file to be uploaded.
    /// - Returns: Self, to allow for method chaining.
    @discardableResult
    public func upload(_ localPath: String, remotePath: String) -> Self {
        self.upload(localPath, remotePath: remotePath, completion: nil, progress: nil)
        return self
    }

    /// Initiates an upload from a local file path with an optional completion callback.
    /// - Parameters:
    ///   - localPath: The path to the local file to be uploaded.
    ///   - completion: An optional SCPWriteCompletionBlock to handle the upload result.
    public func upload(_ localPath: String, remotePath: String, completion: SCPWriteCompletionBlock?, progress: WriteProgressCallback?) {
        do {
            let fileURL = URL(fileURLWithPath: localPath)
            let fileData = try Data(contentsOf: fileURL)
            let fileSize = UInt64(fileData.count)
            
            self.openSCPChannelForUpload(localPath: localPath, remotePath: remotePath, completion: { error in
                guard error == nil else {
                    completion?(nil, error)
                    return
                }
                
                self.session.generalQueue.async {
                    guard let scpChannel = self.scpChannel else {
                        self.finishDownload()
                        completion?(nil, SSHError.SCP.fileRead(detail: "SCP upload channel unavailable"))
                        return
                    }
                    
                    do {
                        let result = scpChannel.write(fileData, progress: progress)
                        
                        let isUploadSuccessful = result.bytesSent == fileSize
                        if !isUploadSuccessful {
                            completion?(nil, SSHError.SCP.uploadVerification(detail: "Upload verification failed file size."))
                            return
                        }
                        
                        try scpChannel.closeChannel()
                        
                        completion?(result.bytesSent, result.error)
                    } catch {
                        self.finishDownload()
                        completion?(nil, error)
                    }
                }
            })
        } catch {
            completion?(nil, error)
        }
    }
}

extension SCPSession {
    public func openSCPChannelForDownload(remotePath: String, completion: @escaping (FileInfo?, Error?) -> Void) {
        session.generalQueue.async(completion: { (error: Error?) in
            if let error = error {
                self.close()
                self.isDownloading = false
                completion(nil, error)
            }
        }, block: {
            do {
                self.scpChannel = self.sshSession.session.makeChannel()
                
                let fileInfo = try self.scpChannel?.openSCPChannel(remotePath: remotePath)
                
                guard let fileInfo = fileInfo else {
                    self.isDownloading = false
                    completion(nil, SSHError.SCP.fileInfoUnavailable)
                    return
                }
                
                self.isDownloading = true
                
//            TODO: Add a prop for scp max file size
//            if fileInfo.fileSize > MAX_FILE_SIZE {
//                completion(nil, NSError(domain: "SCPSession", code: 102, userInfo: [NSLocalizedDescriptionKey: "File is too large for download."]))
//                return
//            }
                
                if (fileInfo.permissions & S_IRUSR) == 0 {
                    completion(nil, SSHError.SCP.fileRead(detail: "Permission denied: You do not have read access to the specified file on the remote host."))
                    return
                }
                
                completion(fileInfo, nil)
            } catch {
                self.isDownloading = false
                completion(nil, error)
            }
        })
    }
    
    public func openSCPChannelForUpload(localPath: String, remotePath: String, completion: @escaping (Error?) -> Void) {
        session.generalQueue.async(completion: { (error: Error?) in
            if let error = error {
                self.close()
                completion(error)
            }
        }, block: {
            do {
                let fileInfo = try FileInfo.init(fromLocalPath: localPath)
                
                self.scpChannel = self.sshSession.session.makeChannel()
                
                try self.scpChannel?.openSCPChannel(localPath: remotePath, mode: Int32(fileInfo.permissions), fileSize: UInt64(fileInfo.fileSize), mtime: fileInfo.modificationTime, atime: fileInfo.accessTime)
                                
                completion(nil)
            } catch {
                completion(error)
            }
        })
    }
}
