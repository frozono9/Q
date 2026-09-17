import Foundation
import QSerialNative

public enum QTransportError: Error, LocalizedError, Equatable {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

/// Synchronous, bounded I/O; the CLI owns this object on one thread.
public protocol SerialIO: AnyObject {
    func read(timeoutMilliseconds: Int) throws -> Data
    func write(_ data: Data) throws
    func close()
}

public final class NativeSerialIO: SerialIO {
    private var port: OpaquePointer?

    public static func candidates() throws -> [String] {
        var paths = [CChar](repeating: 0, count: 16_384)
        var error = [CChar](repeating: 0, count: 512)
        guard q_serial_candidates(&paths, paths.count, &error, error.count) >= 0 else {
            throw QTransportError.message(String(cString: error))
        }
        return Array(Set(String(cString: paths).split(separator: "\n").map(String.init))).sorted()
    }

    public init(path: String) throws {
        var error = [CChar](repeating: 0, count: 512)
        port = path.withCString { q_serial_open($0, &error, error.count) }
        guard port != nil else { throw QTransportError.message(String(cString: error)) }
    }

    public func read(timeoutMilliseconds: Int) throws -> Data {
        guard let port else { throw QTransportError.message("Serial port is closed") }
        var bytes = [UInt8](repeating: 0, count: 4096)
        var error = [CChar](repeating: 0, count: 512)
        let count = q_serial_read(port, &bytes, bytes.count, Int32(min(max(timeoutMilliseconds, 1), 1000)), &error, error.count)
        guard count >= 0 else { throw QTransportError.message(String(cString: error)) }
        return Data(bytes.prefix(Int(count)))
    }

    public func write(_ data: Data) throws {
        guard let port else { throw QTransportError.message("Serial port is closed") }
        if data.isEmpty { return }
        var error = [CChar](repeating: 0, count: 512)
        let count = data.withUnsafeBytes { raw in
            q_serial_write(port, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &error, error.count)
        }
        guard count == data.count else { throw QTransportError.message(String(cString: error)) }
    }

    public func close() {
        if let port { q_serial_close(port) }
        port = nil
    }
    deinit { close() }
}
