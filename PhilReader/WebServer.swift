import Foundation
import Network

/// The start of an HTTP request: method, path and headers (keys lowercased).
struct HTTPRequestHead: Equatable {
    var method: String
    var path: String
    var headers: [String: String]

    var contentLength: Int? { headers["content-length"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } }

    enum ParseResult: Equatable {
        /// More bytes are needed.
        case incomplete
        case malformed
        /// The head, and the offset in the data where the body starts.
        case complete(HTTPRequestHead, bodyOffset: Int)
    }

    static func parse(_ data: Data) -> ParseResult {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        guard let text = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return .malformed }
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/") else { return .malformed }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .malformed }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let path = String(requestLine[1]).components(separatedBy: "?")[0]
        let head = HTTPRequestHead(method: String(requestLine[0]).uppercased(), path: path, headers: headers)
        return .complete(head, bodyOffset: end.upperBound - data.startIndex)
    }

    /// The uploaded file's name from the `X-File-Name` header, reduced to a safe
    /// last path component, or `nil` if it isn't a comic PhilReader can import.
    var uploadFileName: String? {
        guard let raw = headers["x-file-name"], let decoded = raw.removingPercentEncoding else { return nil }
        let name = (decoded as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), name != "/",
              let format = ComicFormat(url: URL(fileURLWithPath: "/upload/" + name, isDirectory: false)), format != .folder else { return nil }
        return name
    }
}

/// Serves an upload page on the local network so comics can be sent from a computer's browser.
@MainActor
final class WebServer: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    struct Upload: Identifiable, Equatable {
        enum Status: Equatable {
            case receiving
            case importing
            case imported
            case failed(String)
        }

        let id = UUID()
        let name: String
        var status: Status
    }

    static let port: UInt16 = 8080

    @Published private(set) var state: State = .stopped
    @Published private(set) var uploads: [Upload] = []

    private let library: LibraryManager
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]
    private let queue = DispatchQueue(label: "PhilReader.WebServer")

    init(library: LibraryManager = .shared) {
        self.library = library
    }

    /// Where to point a browser, e.g. `http://192.168.1.20:8080`.
    var address: String? {
        guard state == .running, let host = Self.localAddress() else { return nil }
        return "http://\(host):\(Self.port)"
    }

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: port)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            self.listener = listener
            state = .starting
            listener.start(queue: queue)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections = [:]
        state = .stopped
    }

    private func listenerChanged(_ newState: NWListener.State) {
        switch newState {
        case .ready:
            state = .running
        case .failed(let error):
            state = .failed(error.localizedDescription)
            listener?.cancel()
            listener = nil
        case .cancelled:
            if case .failed = state { return }
            state = .stopped
        default:
            break
        }
    }

    private func accept(_ nwConnection: NWConnection) {
        let connection = HTTPConnection(connection: nwConnection, queue: queue)
        let key = ObjectIdentifier(connection)
        connection.onUploadStarted = { [weak self] name in
            Task { @MainActor in self?.uploads.insert(Upload(name: name, status: .receiving), at: 0) }
        }
        connection.onUploadFinished = { [weak self] name, file, reply in
            Task { @MainActor in
                guard let self else { return reply(false, "The server stopped.") }
                let result = await self.importUpload(named: name, at: file)
                reply(result == nil, result ?? "Imported")
            }
        }
        connection.onUploadFailed = { [weak self] name in
            Task { @MainActor in self?.setStatus(.failed("The upload was interrupted."), for: name) }
        }
        connection.onClose = { [weak self] in
            Task { @MainActor in self?.connections[key] = nil }
        }
        connections[key] = connection
        connection.start()
    }

    /// Imports a received file; returns an error message on failure.
    private func importUpload(named name: String, at file: URL) async -> String? {
        setStatus(.importing, for: name)
        let countBefore = library.comics.count
        await library.importComic(from: file)
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        // Uploads report errors on this screen, not with the library's import alert.
        let error = library.importError
        library.importError = nil
        if library.comics.count > countBefore {
            setStatus(.imported, for: name)
            return nil
        }
        let message = error ?? "PhilReader couldn't read this file."
        setStatus(.failed(message), for: name)
        return message
    }

    private func setStatus(_ status: Upload.Status, for name: String) {
        guard let index = uploads.firstIndex(where: { $0.name == name && $0.status != .imported }) else { return }
        uploads[index].status = status
    }

    /// The device's Wi-Fi IPv4 address, if it has one.
    nonisolated static func localAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var fallback: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let name = String(cString: interface.ifa_name)
            let ip = String(cString: host)
            if name == "en0" { return ip }
            if fallback == nil, name.hasPrefix("en") || name.hasPrefix("bridge") { fallback = ip }
        }
        return fallback
    }
}

/// One browser connection: serves the upload page, or streams one uploaded file to disk.
private final class HTTPConnection {
    var onUploadStarted: (String) -> Void = { _ in }
    /// Called with the file on disk and a reply callback taking success and a message.
    var onUploadFinished: (String, URL, @escaping (Bool, String) -> Void) -> Void = { _, _, _ in }
    var onUploadFailed: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private var upload: (name: String, url: URL, handle: FileHandle, expected: Int, received: Int)?
    private var isDone = false
    /// The whole file has arrived and is being imported; the reply comes once that finishes.
    private var awaitingReply = false

    private static let maxHeadSize = 64 * 1024

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func start() {
        connection.start(queue: queue)
        receive()
    }

    func cancel() {
        queue.async { self.finish() }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty { handle(data) }
            guard !isDone, !awaitingReply else { return }
            if error != nil || isComplete {
                finish()
            } else {
                receive()
            }
        }
    }

    private func handle(_ data: Data) {
        if upload != nil {
            write(data)
            return
        }
        buffer.append(data)
        switch HTTPRequestHead.parse(buffer) {
        case .incomplete:
            if buffer.count > Self.maxHeadSize { respond(status: "431 Request Header Fields Too Large") }
        case .malformed:
            respond(status: "400 Bad Request")
        case .complete(let head, let bodyOffset):
            let body = buffer.subdata(in: buffer.startIndex + bodyOffset..<buffer.endIndex)
            buffer = Data()
            route(head, body: body)
        }
    }

    private func route(_ head: HTTPRequestHead, body: Data) {
        switch (head.method, head.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            respond(status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(WebServerPage.html.utf8))
        case ("POST", "/upload"):
            guard let name = head.uploadFileName else {
                return respond(status: "415 Unsupported Media Type",
                               json: ["ok": false, "message": "PhilReader reads CBZ, CBR, CB7, PDF and EPUB files."])
            }
            guard let length = head.contentLength, length > 0 else {
                return respond(status: "411 Length Required", json: ["ok": false, "message": "The file is empty."])
            }
            beginUpload(name: name, length: length, expectsContinue: head.headers["expect"]?.lowercased() == "100-continue")
            if !body.isEmpty { write(body) }
        default:
            respond(status: "404 Not Found", contentType: "text/plain", body: Data("Not found".utf8))
        }
    }

    private func beginUpload(name: String, length: Int, expectsContinue: Bool) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Uploads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            upload = (name, url, try FileHandle(forWritingTo: url), length, 0)
        } catch {
            return respond(status: "500 Internal Server Error", json: ["ok": false, "message": "Couldn't save the file."])
        }
        onUploadStarted(name)
        if expectsContinue {
            connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { _ in })
        }
    }

    private func write(_ data: Data) {
        guard var current = upload else { return }
        let slice = data.prefix(current.expected - current.received)
        current.handle.write(slice)
        current.received += slice.count
        upload = current
        guard current.received >= current.expected else { return }
        try? current.handle.close()
        awaitingReply = true
        let name = current.name
        onUploadFinished(name, current.url) { [weak self] ok, message in
            guard let self else { return }
            self.queue.async {
                self.upload = nil
                self.respond(status: ok ? "200 OK" : "422 Unprocessable Content", json: ["ok": ok, "message": message])
            }
        }
    }

    private func respond(status: String, json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        respond(status: status, contentType: "application/json", body: body)
    }

    private func respond(status: String, contentType: String = "text/plain", body: Data = Data()) {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n" +
            "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { [weak self] _ in
            self?.queue.async { self?.finish() }
        })
    }

    private func finish() {
        guard !isDone else { return }
        isDone = true
        if let upload, upload.received < upload.expected {
            try? upload.handle.close()
            try? FileManager.default.removeItem(at: upload.url.deletingLastPathComponent())
            onUploadFailed(upload.name)
        }
        upload = nil
        connection.cancel()
        onClose()
    }
}
