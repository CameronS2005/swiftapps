import Foundation

enum N8NError: Error, LocalizedError {
    case missingBaseURL
    case serverError(statusCode: Int, data: Data?)
    case decodingError(Error)
    case other(Error)
    case unsupportedEndpoint
    case authenticationRequired
    var errorDescription: String? {
        switch self {
        case .missingBaseURL: return "Base URL not configured."
        case .serverError(let code, _): return "Server returned HTTP \(code)."
        case .decodingError(let e): return "Decoding failed: \(e.localizedDescription)"
        case .other(let e): return e.localizedDescription
        case .unsupportedEndpoint: return "Endpoint not available on this server variant."
        case .authenticationRequired: return "Authentication required (401/403). Check API key or login."
        }
    }
}

final class N8NClient {
    private let settings: SettingsStore
    private let session: URLSession
    /// Candidate base path prefixes to try if not certain which one the instance uses.
    private let basePaths = ["/rest", "/api/v1", ""] // public API, older, fallback

    init(settings: SettingsStore, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil, basePath: String? = nil) throws -> URLRequest {
        guard let base = settings.baseURL else { throw N8NError.missingBaseURL }
        let bp = basePath ?? settings.basePathPreference
        var full = base.appendingPathComponent(bp).appendingPathComponent(path)
        // if user specified empty base path, ensure single slash behavior
        let url = full
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body = body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if !settings.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
            req.setValue(settings.apiKey, forHTTPHeaderField: "X-N8N-API-KEY")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    // Attempt a request with fallback base paths if the first path fails with 404/401.
    private func perform(path: String, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse, URL) {
        let candidatePaths = basePaths
        var lastError: Error?
        for bp in candidatePaths {
            do {
                // construct absolute url more robustly:
                guard let base = settings.baseURL else { throw N8NError.missingBaseURL }
                // build URL by hand to avoid double slashes
                var baseString = base.absoluteString
                if bp != "" {
                    baseString = baseString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    baseString += bp.hasPrefix("/") ? bp : "/" + bp
                }
                var urlString = baseString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/\(path)".trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let url = URL(string: urlString) {
                    var req = URLRequest(url: url)
                    req.httpMethod = method
                    if let body = body {
                        req.httpBody = body
                        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    }
                    if !settings.apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                        req.setValue(settings.apiKey, forHTTPHeaderField: "X-N8N-API-KEY")
                    }
                    req.setValue("application/json", forHTTPHeaderField: "Accept")

                    let (data, resp) = try await session.data(for: req)
                    guard let http = resp as? HTTPURLResponse else {
                        throw N8NError.other(NSError(domain: "n8n", code: -1, userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"]))
                    }
                    if http.statusCode == 401 || http.statusCode == 403 {
                        throw N8NError.authenticationRequired
                    }
                    if (200...299).contains(http.statusCode) {
                        return (data, http, url)
                    } else if (400...499).contains(http.statusCode) {
                        // not found or client error - try next basePath for 404
                        lastError = N8NError.serverError(statusCode: http.statusCode, data: data)
                        if http.statusCode == 404 || http.statusCode == 405 {
                            continue // try next base path
                        } else {
                            throw lastError!
                        }
                    } else {
                        throw N8NError.serverError(statusCode: http.statusCode, data: data)
                    }
                } else {
                    throw N8NError.other(NSError(domain: "n8n", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL built: \(urlString)"]))
                }
            } catch {
                lastError = error
                if case N8NError.authenticationRequired = error {
                    // stop trying other base paths if auth failed - same host likely
                    throw error
                }
                // otherwise continue trying other basePaths
            }
        }
        throw lastError ?? N8NError.unsupportedEndpoint
    }

    // MARK: - API methods

    struct WorkflowSummary: Identifiable, Codable {
        let id: Int
        let name: String?
        let active: Bool?
        // additional fields may exist; keep flexible by decoding unknown ones if needed
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case active
        }
    }

    struct ExecutionSummary: Codable, Identifiable {
        let id: String
        let workflowId: Int?
        let status: String?
        let startedAt: String?
        let stoppedAt: String?
        var identifier: String { id }
        var _id: String { id }
        enum CodingKeys: String, CodingKey {
            case id
            case workflowId
            case status
            case startedAt
            case stoppedAt
        }
    }

    /// List workflows
    func listWorkflows() async throws -> [WorkflowSummary] {
        // common endpoints: GET /workflows OR GET /workflows?limit=...
        let (data, _, _) = try await perform(path: "workflows")
        do {
            // some variants return a nested object; try a few decodes
            if let decoded = try? JSONDecoder().decode([WorkflowSummary].self, from: data) {
                return decoded
            }
            // sometimes API returns {"workflows": [...] }
            if let wrapper = try? JSONDecoder().decode([String: [WorkflowSummary]].self, from: data),
               let arr = wrapper["workflows"] ?? wrapper["data"] {
                return arr
            }
            // fallback: try decode array of dynamic dicts and map
            let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            let mapped = arr?.compactMap { dict -> WorkflowSummary? in
                guard let id = dict["id"] as? Int ?? (dict["id"] as? String).flatMap({ Int($0) }) else { return nil }
                return WorkflowSummary(id: id, name: dict["name"] as? String, active: dict["active"] as? Bool)
            } ?? []
            return mapped
        } catch {
            throw N8NError.decodingError(error)
        }
    }

    /// Activate workflow (attempt POST /workflows/{id}/activate or PUT /workflows/{id} with active flag)
    func setWorkflowActive(_ workflowId: Int, active: Bool) async throws {
        // try POST /workflows/{id}/activate and /deactivate first (some public APIs use that),
        // otherwise try PATCH/PUT to update workflow with {"active": true}
        let activatePath = "workflows/\(workflowId)/\(active ? "activate" : "deactivate")"
        do {
            _ = try await perform(path: activatePath, method: "POST")
            return
        } catch {
            if case N8NError.authenticationRequired = error { throw error }
            // try PUT update
            let payload = try JSONEncoder().encode(["active": active])
            // some APIs accept PUT /workflows/{id}
            do {
                _ = try await perform(path: "workflows/\(workflowId)", method: "PUT", body: payload)
                return
            } catch {
                // last attempt: PATCH
                _ = try await perform(path: "workflows/\(workflowId)", method: "PATCH", body: payload)
                return
            }
        }
    }

    /// List executions (global or for a specific workflow)
    func listExecutions(workflowId: Int? = nil, limit: Int = 10) async throws -> [ExecutionSummary] {
        var path = "executions?limit=\(limit)"
        if let wf = workflowId {
            // some APIs expose workflow-level executions: /workflows/{workflowId}/executions
            // try that first
            do {
                let (data, _, _) = try await perform(path: "workflows/\(wf)/executions")
                if let arr = try? JSONDecoder().decode([ExecutionSummary].self, from: data) {
                    return arr
                }
                // fallback parse
                return try JSONDecoder().decode([ExecutionSummary].self, from: data)
            } catch {
                // fallback to /executions?workflowId=
                path = "executions?workflowId=\(wf)&limit=\(limit)"
            }
        }
        let (data, _, _) = try await perform(path: path)
        do {
            if let arr = try? JSONDecoder().decode([ExecutionSummary].self, from: data) {
                return arr
            }
            if let wrapper = try? JSONDecoder().decode([String: [ExecutionSummary]].self, from: data),
               let arr = wrapper["executions"] ?? wrapper["data"] {
                return arr
            }
            // final fallback: parse as array of dicts
            let json = try JSONSerialization.jsonObject(with: data)
            if let arr = json as? [[String: Any]] {
                // map minimal fields
                return arr.compactMap { dict in
                    guard let id = dict["id"] as? String ?? (dict["id"] as? Int).map({ String($0) }) else { return nil }
                    let wfId = dict["workflowId"] as? Int
                    return ExecutionSummary(id: id, workflowId: wfId, status: dict["status"] as? String, startedAt: dict["startedAt"] as? String, stoppedAt: dict["stoppedAt"] as? String)
                }
            }
            throw N8NError.decodingError(NSError(domain: "n8n", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown executions response"]))
        } catch {
            throw N8NError.decodingError(error)
        }
    }
}
