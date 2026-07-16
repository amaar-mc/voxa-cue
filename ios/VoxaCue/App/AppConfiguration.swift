import Foundation
import VoxaRuntime

struct AppConfiguration {
    let apiBaseURL: URL?
    let demoAPIToken: String
    let demoMode: Bool

    init(bundle: Bundle, arguments: [String]) {
        let rawURL = bundle.object(forInfoDictionaryKey: "VoxaAPIBaseURL") as? String ?? ""
        let token = bundle.object(forInfoDictionaryKey: "VoxaDemoAPIToken") as? String ?? ""
        let parsedURL = URL(string: rawURL)
        if let parsedURL,
           parsedURL.scheme == "https",
           let host = parsedURL.host,
           !host.isEmpty,
           host != "example.invalid" {
            self.apiBaseURL = parsedURL
        } else {
            self.apiBaseURL = nil
        }
        self.demoAPIToken = token
        self.demoMode = arguments.contains("-demoScenario")
    }

    func makeAPIClient(session: URLSession) -> VoxaAPIClient? {
        guard let apiBaseURL, demoAPIToken.count >= 32 else { return nil }
        return VoxaAPIClient(baseURL: apiBaseURL, bearerToken: demoAPIToken, session: session)
    }
}
