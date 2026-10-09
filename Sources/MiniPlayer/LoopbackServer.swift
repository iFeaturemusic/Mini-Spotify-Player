import Foundation
import Network

/// Minimal HTTP server on 127.0.0.1 that only runs during login to receive the OAuth redirect.
final class LoopbackServer {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private var timeout: DispatchWorkItem?

    func waitForCallback(port: UInt16, onReady: @escaping () -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)

                let listener = try NWListener(using: params)
                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        onReady()
                    case .failed(let error):
                        self?.finish(.failure(AuthError("Port \(port) ist belegt: \(error.localizedDescription)")))
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.start(queue: .main)
                self.listener = listener

                let work = DispatchWorkItem { [weak self] in
                    self?.finish(.failure(AuthError("Zeitüberschreitung bei der Anmeldung.")))
                }
                timeout = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: work)
            } catch {
                finish(.failure(error))
            }
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let requestLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = requestLine.split(separator: " ")
            let target = parts.count >= 2 ? String(parts[1]) : ""

            guard target.hasPrefix("/callback"), let url = URL(string: "http://127.0.0.1" + target) else {
                self.respond(connection, status: "404 Not Found", body: "")
                return
            }
            self.respond(connection, status: "200 OK", body: Self.page(success: !target.contains("error=")))
            self.finish(.success(url))
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let bodyData = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + bodyData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<URL, Error>) {
        timeout?.cancel()
        timeout = nil
        listener?.cancel()
        listener = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private static func page(success: Bool) -> String {
        let title = success ? "Angemeldet ✓" : "Anmeldung abgebrochen"
        let text = success
            ? "Du kannst diesen Tab schließen und den Player oben in der Menüleiste benutzen."
            : "Versuche es im Player erneut."
        return """
        <!doctype html><html lang="de"><meta charset="utf-8"><title>MiniPlayer</title>
        <body style="margin:0;height:100vh;display:grid;place-items:center;background:#121212;color:#fff;font-family:-apple-system,system-ui,sans-serif">
        <div style="text-align:center"><h1 style="color:#1DB954;font-size:28px">\(title)</h1>
        <p style="color:#b3b3b3">\(text)</p></div></body></html>
        """
    }
}
