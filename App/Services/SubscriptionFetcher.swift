import Foundation

/// Fetches a subscription while handling redirects by hand, so a 307 to a
/// non-http launcher link (hiddify://import/<url>) is unwrapped instead of failing.
enum SubscriptionFetcher {
    enum FetchError: LocalizedError {
        case tooManyRedirects
        case badRedirect(String)
        var errorDescription: String? {
            switch self {
            case .tooManyRedirects: return String(localized: "Too many redirects.")
            case .badRedirect(let target): return String(format: String(localized: "Unsupported redirect target: %@"), target)
            }
        }
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func fetch(_ urlString: String, maxHops: Int = 6) async throws -> (Data, HTTPURLResponse, String) {
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var current = urlString
        for _ in 0..<maxHops {
            guard let url = URL(string: current) else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("SkyRay/0.2 (iOS) v2rayNG/1.9 Hiddify", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if (300..<400).contains(http.statusCode), let location = http.value(forHTTPHeaderField: "Location") {
                let absolute = URL(string: location, relativeTo: url)?.absoluteString ?? location
                if let resolved = SubscriptionLinkResolver.resolve(absolute) {
                    current = resolved.url
                    continue
                }
                throw FetchError.badRedirect(String(absolute.prefix(80)))
            }
            return (data, http, current)
        }
        throw FetchError.tooManyRedirects
    }
}
