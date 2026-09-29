#if DEBUG
import WebKit

/// Development only: what Google itself sees from this app while connected. It opens Google in a
/// web view (the same kind of view the ad uses, a separate WebKit process) over the tunnel and
/// logs Google's own verdict on the country (the `gl` it redirects with, and any location line on
/// the page) next to what the view reports for language and time zone.
@MainActor
final class SignalCheck: NSObject, WKNavigationDelegate {
    static let shared = SignalCheck()
    private var webView: WKWebView?
    private var urls: [String] = []

    func run() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: config)
        view.navigationDelegate = self
        webView = view
        urls = []
        ProfileStore.shared.appendTunnelLine("[signal] opening Google over the tunnel")
        view.load(URLRequest(url: URL(string: "https://www.google.com/search?q=what+is+my+ip")!))
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url?.absoluteString { urls.append(url) }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        (function() {
          var text = document.body ? document.body.innerText : '';
          var lines = text.split('\\n').filter(function(l) {
            return /Germany|Deutschland|United States|Iran|Your location|From your IP|IP address|Update location|Standort/i.test(l);
          }).slice(0, 8);
          return JSON.stringify({
            language: navigator.language, languages: navigator.languages,
            timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
            offsetMinutes: new Date().getTimezoneOffset(),
            page: location.href, lines: lines
          });
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, error in
            let redirectGL = self?.urls.compactMap { URLComponents(string: $0)?.queryItems?.first { $0.name == "gl" }?.value }.first ?? "-"
            ProfileStore.shared.appendTunnelLine("[signal] Google's country from the redirect (gl): \(redirectGL)")
            ProfileStore.shared.appendTunnelLine("[signal] web view: \(result as? String ?? error?.localizedDescription ?? "-")")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        ProfileStore.shared.appendTunnelLine("[signal] failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        ProfileStore.shared.appendTunnelLine("[signal] failed: \(error.localizedDescription)")
    }
}
#endif
