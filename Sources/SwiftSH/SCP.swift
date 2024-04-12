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

struct SCPConstants {
    static let scpErrorDomain = "SCPErrorDomain"
    static let uploadErrorDomain = "UploadErrorDomain"
    static let fileReadError = "File is not readable."
    static let invalidPathError = "Invalid path."
    static let uploadVerificationFailedError = "Upload verification failed."
    static let fileInfoNilError = "FileInfo is nil."
    
    // Error codes
    static let verificationErrorCode = 1001
    static let invalidPathErrorCode = 101
    static let fileTooLargeErrorCode = 102
    static let fileNotReadableErrorCode = 103
}

public class SCPSession: SSHChannel {
    private let sshSession: SSHSession
    
    private var scpChannel: SSHLibraryChannel?
    
    public override init(sshLibrary: SSHLibrary.Type = Libssh2.self, session: SSHSession, environment: [Environment] = [], terminal: Terminal? = nil) throws {
        self.sshSession = session
        try super.init(sshLibrary: sshLibrary, session: session, environment: environment, terminal: terminal)
    }
    
    public init(sshLibrary: SSHLibrary.Type = Libssh2.self, session: SSHSession) throws {
        self.sshSession = session
        try super.init(sshLibrary: sshLibrary, session: sshSession)
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
        if let stream = OutputStream(toFileAtPath: path, append: false) {
            stream.open()
            defer { stream.close() }
            self.download(from, to: stream, completion: completion, progress: progress)
        } else {
            completion?(nil, nil, SSHError.SCP.invalidPath)
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
        session.queue.async {
            self.openSCPChannelForDownload(remotePath: from, completion: { fileInfo, error in
                guard let fileInfo = fileInfo, error == nil else {
                    completion?(fileInfo, nil, error)
                    return
                }
                
                do {
                    let data = try self.scpChannel?.read(progress: progress)
                    
                    if let data = data {
                        _ = data.withUnsafeBytes {
                            stream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count)
                        }
                    }
                    
                    try self.scpChannel?.closeChannel()

                    completion?(fileInfo, nil, nil)
                } catch {
                    completion?(fileInfo, nil, error)
                }
            })
        }
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
                completion(nil, nil, error ?? SSHError.unknown (detail: "Download lacks the data"))
            }
            stream.close()
        } progress: { bytesRead in
            progress(bytesRead)
        }
    }

    // MARK: - Upload

    /// Initiates an upload from a local file path without requiring a completion callback.
    /// - Parameter localPath: The path to the local file to be uploaded.
    /// - Returns: Self, to allow for method chaining.
    @discardableResult
    public func upload(_ localPath: String) -> Self {
        self.upload(localPath, completion: nil, progress: nil)
        return self
    }

    /// Initiates an upload from a local file path with an optional completion callback.
    /// - Parameters:
    ///   - localPath: The path to the local file to be uploaded.
    ///   - completion: An optional SCPWriteCompletionBlock to handle the upload result.
    public func upload(_ localPath: String, completion: SCPWriteCompletionBlock?, progress: WriteProgressCallback?) {
        session.queue.async {
            do {
                let fileURL = URL(fileURLWithPath: localPath)
                let fileData = try Data(contentsOf: fileURL)
                let fileSize = UInt64(fileData.count)
                
                self.openSCPChannelForUpload(localPath: localPath, completion: { error in
                    guard error == nil else {
                        completion?(nil, error)
                        return
                    }
                    
                    do {
                        guard let result = self.scpChannel?.write(fileData, progress: progress) else {
                            let error = NSError(domain: SCPConstants.uploadErrorDomain, code: SCPConstants.verificationErrorCode, userInfo: [NSLocalizedDescriptionKey: SCPConstants.uploadVerificationFailedError])
                            completion?(nil, error)
                            return
                        }

                        let isUploadSuccessful = result.bytesSent == fileSize
                        if !isUploadSuccessful {
                            let verificationError = NSError(domain: SCPConstants.uploadErrorDomain, code: SCPConstants.verificationErrorCode, userInfo: [NSLocalizedDescriptionKey: SCPConstants.uploadVerificationFailedError])
                            completion?(nil, verificationError)
                            return
                        }
                        
                        try self.scpChannel?.closeChannel()

                        completion?(result.bytesSent, result.error)
                    } catch {
                        completion?(nil, error)
                    }
                })
            } catch {
                completion?(nil, error)
            }
        }
    }


    // MARK: - Additional methods as needed
}

extension SCPSession {
    public func openSCPChannelForUpload(localPath: String, completion: @escaping (Error?) -> Void) {
        do {
            let fileInfo = try FileInfo.init(fromLocalPath: localPath)
            
            self.scpChannel = self.sshSession.session.makeChannel()
            
            try self.scpChannel?.openSCPChannel(localPath: localPath, mode: Int32(fileInfo.permissions), fileSize: UInt64(fileInfo.fileSize), mtime: fileInfo.modificationTime, atime: fileInfo.accessTime)
            
            completion(nil)
        } catch {
            completion(error)
        }
    }
    
    public func openSCPChannelForDownload(remotePath: String, completion: @escaping (FileInfo?, Error?) -> Void) {
        do {
            self.scpChannel = self.sshSession.session.makeChannel()
            
            let fileInfo = try self.scpChannel?.openSCPChannel(remotePath: remotePath)
            
            guard let fileInfo = fileInfo else {
                completion(nil, NSError(domain: SCPConstants.scpErrorDomain, code: SCPConstants.invalidPathErrorCode, userInfo: [NSLocalizedDescriptionKey: SCPConstants.fileInfoNilError]))
                return
            }
            
//            TODO: Add a prop for scp max file size
//            if fileInfo.fileSize > MAX_FILE_SIZE {
//                completion(nil, NSError(domain: "SCPSession", code: 102, userInfo: [NSLocalizedDescriptionKey: "File is too large for download."]))
//                return
//            }
            
            // Check for read permissions (assuming UNIX permission bits)
            if (fileInfo.permissions & S_IRUSR) == 0 {
                completion(nil, NSError(domain: SCPConstants.scpErrorDomain, code: SCPConstants.fileNotReadableErrorCode, userInfo: [NSLocalizedDescriptionKey: SCPConstants.fileReadError]))
                return
            }
            
            completion(fileInfo, nil)
        } catch {
            completion(nil, error)
        }
    }
}
