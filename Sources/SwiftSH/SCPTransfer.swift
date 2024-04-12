import Foundation

@objc(SCPTransfer)
public class SCPTransfer: NSObject {
    
    private let sshSession: SSHSession
    private var scpSession: SCPSession?
    
    public init(sshLibrary: SSHLibrary.Type = Libssh2.self, sshSession: SSHSession) throws {
        self.sshSession = sshSession
        self.scpSession = try SCPSession(sshLibrary: sshLibrary, session: sshSession)
    }
    
    /// Uploads a file to the remote path using SCP.
    /// - Parameters:
    ///   - localPath: The local file path to upload, can be relative to the app's documents directory or absolute.
    ///   - remotePath: The remote path where the file should be uploaded.
    ///   - completion: A completion handler called when the upload completes.
    ///   - progress: A progress callback called with upload progress updates.
    public func upload(localPath: String, remotePath: String, completion: @escaping SCPWriteCompletionBlock, progress: WriteProgressCallback? = nil) {
        let resolvedPath = self.resolvePath(localPath)
        scpSession?.upload(resolvedPath, completion: { bytesSent, error in
            completion(bytesSent, error)
        }, progress: { bytesWritten, totalBytes in
            progress?(bytesWritten, totalBytes)
        })
    }
    
    /// Downloads a file from the remote path to a local path using SCP.
    /// - Parameters:
    ///   - remotePath: The remote file path to download.
    ///   - localPath: The local path where the file should be saved, can be relative to the app's documents directory or absolute.
    ///   - completion: A completion handler called when the download completes.
    ///   - progress: A progress callback called with download progress updates.
    public func download(remotePath: String, localPath: String, completion: @escaping SCPReadCompletionBlock, progress: ReadProgressCallback? = nil) {
        let resolvedPath = self.resolvePath(localPath)
        scpSession?.download(remotePath, to: resolvedPath, completion: { fileInfo, data, error in
            completion(fileInfo, data, error)
        }, progress: { bytesRead in
            progress?(bytesRead)
        })
    }
    
    /// Resolves the given file path to an absolute path.
    /// If the path is relative, it resolves it relative to the app's documents directory.
    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        } else {
            return self.documentsPath(for: path)
        }
    }
    
    /// Constructs the full path within the app's documents directory for a given filename.
    private func documentsPath(for fileName: String) -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentsDirectory = paths[0]
        return (documentsDirectory as NSString).appendingPathComponent(fileName)
    }
}
