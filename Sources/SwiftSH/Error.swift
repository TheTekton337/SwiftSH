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

public protocol DescriptiveError: Error {
    func description() -> String
}

public enum SSHError: Error {
    case unknown(detail:String)

    case bannerReceive
    case bannerSend
    case invalidMessageAuthenticationCode
    case decrypt
    case methodNone(detail:String)
    case requestDenied(detail:String)
    case methodNotSupported(detail:String)
    case invalid(detail:String)
    case agentProtocol(detail:String)
    case encrypt

    // Common
    case allocation(detail:String)
    case timeout(detail:String)
    case `protocol`(detail:String)
    case again
    case bufferTooSmall(detail:String)
    case badUse(detail:String)
    case compress
    case outOfBoundary(detail:String)

    // Connection
    case alreadyConnected
    case hostResolutionFailed
    case keyExchangeFailure(detail:String)
    case hostkey(detail:String)
    case hostkeySign(detail:String)

    // Authentication
    case authenticationFailed(detail:String)
    case passwordExpired
    case publicKeyUnverified(detail:String)
    case publicKeyProtocol(detail:String)
    case publicKeyFile(detail:String)
    case unsupportedAuthenticationMethod
    case knownHosts

    // Socket
    public enum Socket: Error {
        case write
        case read
        case disconnected
        case timeout
        case invalid
    }

    // Channel
    public enum Channel: Error {
        case unknown
        case alreadyOpen
        case invalid
        case outOfOrder
        case failure
        case requestDenied
        case windowExceeded
        case packetExceeded
        case closed
        case sentEndOfFile
    }

    // SFTP
    public enum SFTP: Error {
        case unknown
        case invalidSession
        case endOfFile
        case noSuchFile
        case permissionDenied
        case failure
        case badMessage
        case noConnection
        case connectionLost
        case operationUnsupported
        case invalidHandle
        case noSuchPath
        case fileAlreadyExists
        case writeProtect
        case noMedia
        case noSpaceOnFilesystem
        case quotaExceeded
        case unknownPrincipal
        case lockConflict
        case directoryNotEmpty
        case notADirectory
        case invalidFilename
        case linkLoop
    }

    // SCP
    public enum SCP: Error {
        case unknown(detail:String)
        case `protocol`(detail:String)
        case fileRead(detail: String)
        case invalidPath(detail: String)
        case uploadVerification(detail: String)
        case fileInfoUnavailable
    }

    // Command
    public enum Command: Error {
        case execError(String?, Data)
    }
}

public enum SSHDisconnectionCode: Int {
    case hostNotAllowedToConnect = 1
    case protocolError = 2
    case keyExchangeFailed = 3
    case reserved = 4
    case macError = 5
    case compressionError = 6
    case serviceNotAvailable = 7
    case protocolVersionNotSupported = 8
    case hostKeyNotVerifiable = 9
    case connectionLost = 10
    case byApplication = 11
    case tooManyConnections = 12
    case authenticationCancelledByUser = 13
    case noMoreAuthenticationMethodsAvailable = 14
    case illegalUserName = 15
}

extension SSHError: DescriptiveError {
    public func description() -> String {
        switch self {
        case .unknown(detail: let detail):
            return "Unknown Error: \(detail)"
        case .bannerReceive:
            return "Error Receiving Banner"
        case .bannerSend:
            return "Error Sending Banner"
        case .invalidMessageAuthenticationCode:
            return "Invalid MAC Received"
        case .decrypt:
            return "Error Decrypting Data"
        case .methodNone(detail: let detail):
            return "No Method Specified: \(detail)"
        case .requestDenied(detail: let detail):
            return "Request Denied: \(detail)"
        case .methodNotSupported(detail: let detail):
            return "Method Not Supported: \(detail)"
        case .invalid(detail: let detail):
            return "Invalid Operation: \(detail)"
        case .agentProtocol(detail: let detail):
            return "Agent Protocol Error: \(detail)"
        case .encrypt:
            return "Error Encrypting Data"
        case .allocation(detail: let detail):
            return "Allocation Error: \(detail)"
        case .timeout(detail: let detail):
            return "Operation Timed Out: \(detail)"
        case .protocol(detail: let detail):
            return "Protocol Error: \(detail)"
        case .again:
            return "Operation Should Be Retried"
        case .bufferTooSmall(detail: let detail):
            return "Buffer Too Small: \(detail)"
        case .badUse(detail: let detail):
            return "Improper Use of API: \(detail)"
        case .compress:
            return "Compression Error"
        case .outOfBoundary(detail: let detail):
            return "Out of Boundary Error: \(detail)"
        case .alreadyConnected:
            return "Already Connected to Host"
        case .hostResolutionFailed:
            return "Failed to Resolve Host"
        case .keyExchangeFailure(detail: let detail):
            return "Key Exchange Failed: \(detail)"
        case .hostkey(detail: let detail):
            return "Host Key Error: \(detail)"
        case .hostkeySign(detail: let detail):
            return "Host Key Signature Error: \(detail)"
        case .passwordExpired:
            return "Password Expired"
        case .publicKeyUnverified(detail: let detail):
            return "Public Key Unverified: \(detail)"
        case .publicKeyProtocol(detail: let detail):
            return "Public Key Protocol Error: \(detail)"
        case .publicKeyFile(detail: let detail):
            return "Public Key File Error: \(detail)"
        case .unsupportedAuthenticationMethod:
            return "Unsupported Authentication Method"
        case .knownHosts:
            return "Known Hosts Error"
        case .authenticationFailed(detail: let detail):
            return "Authentication Failed: \(detail)"
        }
    }
}

extension SSHError.Socket: DescriptiveError {
    public func description() -> String {
        switch self {
        case .write:
            return "Socket write error."
        case .read:
            return "Socket read error."
        case .disconnected:
            return "Socket disconnected."
        case .timeout:
            return "Socket operation timed out."
        case .invalid:
            return "Invalid socket operation."
        }
    }
}

extension SSHError.Channel: DescriptiveError {
    public func description() -> String {
        switch self {
        case .unknown:
            return "Unknown channel error."
        case .alreadyOpen:
            return "Channel is already open."
        case .invalid:
            return "Invalid channel operation."
        case .outOfOrder:
            return "Channel operation out of order."
        case .failure:
            return "Channel failure."
        case .requestDenied:
            return "Channel request denied."
        case .windowExceeded:
            return "Channel window size exceeded."
        case .packetExceeded:
            return "Channel packet size exceeded."
        case .closed:
            return "Channel closed."
        case .sentEndOfFile:
            return "End of file sent on channel."
        }
    }
}

extension SSHError.SFTP: DescriptiveError {
    public func description() -> String {
        switch self {
        case .unknown:
            return "Unknown SFTP error."
        case .invalidSession:
            return "Invalid SFTP session."
        case .endOfFile:
            return "SFTP end of file reached."
        case .noSuchFile:
            return "SFTP no such file found."
        case .permissionDenied:
            return "SFTP permission denied."
        case .failure:
            return "SFTP failure."
        case .badMessage:
            return "SFTP bad message received."
        case .noConnection:
            return "SFTP no connection."
        case .connectionLost:
            return "SFTP connection lost."
        case .operationUnsupported:
            return "SFTP operation unsupported."
        case .invalidHandle:
            return "SFTP invalid handle."
        case .noSuchPath:
            return "SFTP no such path found."
        case .fileAlreadyExists:
            return "SFTP file already exists."
        case .writeProtect:
            return "SFTP write protect error."
        case .noMedia:
            return "SFTP no media present."
        case .noSpaceOnFilesystem:
            return "SFTP no space left on filesystem."
        case .quotaExceeded:
            return "SFTP quota exceeded."
        case .unknownPrincipal:
            return "SFTP unknown principal."
        case .lockConflict:
            return "SFTP lock conflict."
        case .directoryNotEmpty:
            return "SFTP directory not empty."
        case .notADirectory:
            return "SFTP not a directory."
        case .invalidFilename:
            return "SFTP invalid filename."
        case .linkLoop:
            return "SFTP link loop detected."
        }
    }
}


extension SSHError.SCP: DescriptiveError {
    public func description() -> String {
        switch self {
        case .unknown(let detail):
            return "Unknown error: \(detail)"
        case .fileInfoUnavailable:
            return "File info unavailable"
        case .fileRead(let detail):
            return "File read error: \(detail)"
        case .invalidPath(let detail):
            return "Invalid path: \(detail)"
        case .protocol(let detail):
            return "Protocol error: \(detail)"
        case .uploadVerification(let detail):
            return "Failed to verify upload: \(detail)"
        }
    }
}

extension SSHError.Command: DescriptiveError {
    public func description() -> String {
        switch self {
        case .execError(let optionalMessage, let data):
            let message = optionalMessage ?? "Unknown error"
            if let dataString = String(data: data, encoding: .utf8) {
                return "Execution Error: \(message) with data: \(dataString)"
            } else {
                return "Execution Error: \(message) with non-text data of size \(data.count) bytes"
            }
        }
    }
}

extension SSHDisconnectionCode: DescriptiveError {
    public func description() -> String {
        switch self {
        case .hostNotAllowedToConnect:
            return "Host is not allowed to connect."
        case .protocolError:
            return "Protocol error encountered."
        case .keyExchangeFailed:
            return "Key exchange failed."
        case .reserved:
            return "Reserved."
        case .macError:
            return "Message Authentication Code (MAC) error."
        case .compressionError:
            return "Compression error."
        case .serviceNotAvailable:
            return "Service is not available."
        case .protocolVersionNotSupported:
            return "Protocol version not supported."
        case .hostKeyNotVerifiable:
            return "Host key not verifiable."
        case .connectionLost:
            return "Connection lost."
        case .byApplication:
            return "Disconnected by application."
        case .tooManyConnections:
            return "Too many simultaneous connections."
        case .authenticationCancelledByUser:
            return "Authentication cancelled by user."
        case .noMoreAuthenticationMethodsAvailable:
            return "No more authentication methods are available."
        case .illegalUserName:
            return "Illegal username used."
        }
    }
}
