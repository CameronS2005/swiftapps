import Foundation
import Combine

final class SettingsStore: ObservableObject {
    @Published var host: String = ""
    @Published var port: String = ""
    @Published var useHTTPS: Bool = true
    @Published var apiKey: String = ""
    @Published var basePathPreference: String = "/rest" // user can set common base
    @Published var lastError: String?

    // computed baseURL
    var baseURL: URL? {
        var scheme = useHTTPS ? "https" : "http"
        var hostTrim = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostTrim.isEmpty else { return nil }
        var urlString = "\(scheme)://\(hostTrim)"
        if let p = Int(port.trimmingCharacters(in: .whitespaces)), p > 0 {
            urlString += ":\(p)"
        }
        // do not append base path here; N8NClient will append it as needed
        return URL(string: urlString)
    }
}
