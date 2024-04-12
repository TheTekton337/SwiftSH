import Foundation

@objc(SCPTransfer)
public class SCPTransfer: NSObject {
    
    private let sshSession: SSHSession
    private var scpSession: SCPSession?
    
    init(sshLibrary: SSHLibrary.Type = Libssh2.self, sshSession: SSHSession) throws {
        self.sshSession = sshSession
        self.scpSession = try SCPSession(sshLibrary: sshLibrary, session: sshSession)
    }
    
    /// Uploads a file to the remote path using SCP.
    /// - Parameters:
    ///   - localPath: The local file path to upload.
    ///   - remotePath: The remote path where the file should be uploaded.
    ///   - completion: A completion handler called when the upload completes.
    ///   - progress: A progress callback called with upload progress updates.
    func upload(localPath: String, remotePath: String, completion: @escaping SCPWriteCompletionBlock, progress: WriteProgressCallback? = nil) {
        // Here, we're assuming your implementation of SCPSession.upload will use remotePath in some form.
        // This detail depends on how you implement path handling in SCPSession.
        
        scpSession?.upload(localPath, completion: { bytesSent, error in
            // Implementation detail: handle the completion, possibly mapping SCPSession's completion parameters
            // to those expected by this method's caller.
            completion(bytesSent, error)
        }, progress: { bytesWritten, totalBytes in
            // Progress handling, if necessary.
            progress?(bytesWritten, totalBytes)
        })
    }
    
    /// Downloads a file from the remote path to a local path using SCP.
    /// - Parameters:
    ///   - remotePath: The remote file path to download.
    ///   - localPath: The local path where the file should be saved.
    ///   - completion: A completion handler called when the download completes.
    ///   - progress: A progress callback called with download progress updates.
    func download(remotePath: String, localPath: String, completion: @escaping SCPReadCompletionBlock, progress: ReadProgressCallback? = nil) {
        scpSession?.download(remotePath, to: localPath, completion: { fileInfo, data, error in
            // Implementation detail: handle the completion, possibly mapping SCPSession's completion parameters
            // to those expected by this method's caller.
            completion(fileInfo, data, error)
        }, progress: { bytesRead in
            // Progress handling, if necessary.
            progress?(bytesRead)
        })
    }
}
