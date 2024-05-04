import Foundation

public class SSHCommand: SSHChannel {
    
    // MARK: - Type aliases
    
    public typealias CompletionHandler = (String, Data?, Error?) -> Void
    public typealias StringCompletionHandler = (String, String?, Error?) -> Void
    
    // MARK: - Internal variables
    
    private var timeoutSource: DispatchSourceTimer?
    
    // MARK: - Initialization

    public override init(sshLibrary: SSHLibrary.Type = Libssh2.self, host: String, port: UInt16 = 22, environment: [Environment] = [], terminal: Terminal? = nil, queueType: QueueType = .general) throws {
        try super.init(sshLibrary: sshLibrary, host: host, port: port, environment: environment, terminal: terminal, queueType: queueType)
    }

    public override init(sshLibrary: SSHLibrary.Type = Libssh2.self, session: SSHSession, environment: [Environment] = [], terminal: Terminal? = nil, queueType: QueueType = .general) throws {
        try super.init(sshLibrary: sshLibrary, session: session, environment: environment, terminal: terminal, queueType: queueType)
    }

    deinit {
        self.cancelSources()
    }
    
    // MARK: - Resource Management
    
    private func cancelSources() {
        if (timeoutSource != nil) {
            timeoutSource?.cancel()
        }
    }

    public override func close() {
        self.cancelSources()
        session.generalQueue.async {
            let prevBlockingMode = super.session.session.blocking
            super.close()
            super.session.session.blocking = prevBlockingMode
        }
    }
    
    // MARK: - Command Execution
    
    private var command: String?
    private var completion: CompletionHandler?
    
    private var response: Data?
    private var error: Data?

    public func execute(_ command: String, completion: (CompletionHandler)?) {
        self.command = command
        self.completion = completion
        self.prepareForExecution(command: command) { (cmd, data, error) in
            completion?(cmd, data, error)
        }
    }

    public func execute(_ command: String, completion: (StringCompletionHandler)?) {
        self.execute(command) { (cmd: String, data: Data? , error: Error?) in
            let resultString = data.flatMap { String(data: $0, encoding: .utf8) }
            completion?(cmd, resultString, error)
        }
    }
    
    // MARK: - Execution Helpers
    
    private var readTimer: DispatchSourceTimer?

    private func prepareForExecution(command: String, completion: @escaping CompletionHandler) {
        session.generalQueue.async(completion: { (error: Error?) in
            if let error = error {
                self.close()
                completion(command, nil, error)
            }
        }, block: {
            self.response = nil
            self.error = nil
            
            try self.open(channelType: "session")
            try self.setupTimeoutSource(command: command, completion: completion)
            self.session.session.blocking = true
            try self.channel.exec(command)
            self.session.session.blocking = false
            self.timeoutSource?.resume()
            self.session.log.debug("Exec called for command: \(command)")
            
            self.readTimer = DispatchSource.makeTimerSource(queue: self.session.generalQueue.queue)
            self.readTimer?.schedule(deadline: .now(), repeating: .milliseconds(50))
            self.readTimer?.setEventHandler { [weak self] in
                guard let self = self else {
                    print("readTimer event init fail")
                    return
                }
                self.handleReadDataEvent()
            }
            self.readTimer?.resume()
        })
    }
    
    private func setupTimeoutSource(command: String, completion: @escaping CompletionHandler) throws {
        self.timeoutSource = DispatchSource.makeTimerSource(queue: self.session.generalQueue.queue)
        self.timeoutSource?.schedule(deadline: .now() + self.session.timeout, repeating: .never)
        self.timeoutSource?.setEventHandler(handler: { [weak self] in
            self?.handleTimeout(command: command, completion: completion)
        })
    }
    
    // MARK: Channel Data Available
    
    override func notifyDataAvailable() {
        super.notifyDataAvailable()
        handleReadDataEvent()
    }

    private func handleReadDataEvent() {
        guard let timeoutSource = self.timeoutSource else {
            print("handleSocketEvent: timeoutSource cannot be nil")
            return
        }

        timeoutSource.suspend()
        defer { timeoutSource.resume() }

        self.readChannelData()
        
        if self.shouldCompleteOperation() {
            self.finishOperation()
        }
    }

    private func handleTimeout(command: String, completion: @escaping (String, Data?, Error?) -> Void) {
        self.cancelSources()
        let error = SSHError.timeout(detail: "Command execution timed out.")
        completion(command, nil, error)
    }

    private func readChannelData() {
        session.generalQueue.async {
            do {
                self.session.session.blocking = false
                let data = try self.channel.read(expectedFileSize: nil)
                if self.response == nil {
                    self.response = Data()
                }
                self.response?.append(data)
                if self.channel.receivedEOF {
                    self.readTimer?.cancel()
                }
            } catch {
                self.session.log.error("[STD] readChannelData: \(error)")
            }
            
            do {
                let errorData = try self.channel.readError()
                if !errorData.isEmpty {
                    if self.error == nil {
                        self.error = Data()
                    }
                    self.error?.append(errorData)
                }
            } catch {
                self.session.log.error("[ERR] readChannelData: \(error)")
            }
        }
    }

    private func shouldCompleteOperation() -> Bool {
        return self.channel.receivedEOF || self.channel.exitStatus() != nil
    }
    
    private func finishOperation() {
        guard let completion = self.completion, let command = self.command else {
            self.session.log.debug("finishOperation fail")
            return
        }
        
        let error = self.error.map { SSHError.Command.execError(String(data: $0, encoding: .utf8), $0) }
        completion(command, self.response, error)
        
        self.session.generalQueue.async {
            self.cancelSources()
            self.close()
        }
        
        self.completion = nil
        self.command = nil
    }
}
