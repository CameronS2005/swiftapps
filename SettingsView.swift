import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var tempHost = ""
    @State private var tempPort = ""
    @State private var tempApiKey = ""
    @State private var useHTTPS = true
    var body: some View {
        Form {
            Section(header: Text("Server")) {
                TextField("Host (example: n8n.example.com or 192.168.1.10)", text: $tempHost)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Port (leave empty for default)", text: $tempPort)
                    .keyboardType(.numberPad)
                Toggle("Use HTTPS", isOn: $useHTTPS)
            }
            Section(header: Text("Authentication")) {
                SecureField("X-N8N-API-KEY", text: $tempApiKey)
                Text("The app sends the API key with header `X-N8N-API-KEY`. For some self-hosted setups older `/rest` endpoints might require login/JWT instead; check docs if you get 401/403.").font(.footnote)
            }
            Section {
                Button("Save & Test Connection") {
                    settings.host = tempHost
                    settings.port = tempPort
                    settings.useHTTPS = useHTTPS
                    settings.apiKey = tempApiKey
                    // no async here; main view will run refresh
                }
                .buttonStyle(.borderedProminent)
            }
            if let lastErr = settings.lastError {
                Section(header: Text("Last error")) {
                    Text(lastErr).foregroundColor(.red).font(.caption)
                }
            }
            Section(header: Text("Notes")) {
                Text("This app will try common n8n API base paths such as `/rest` and `/api/v1`. If your instance behaves differently see the n8n API docs.").font(.footnote)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            tempHost = settings.host
            tempPort = settings.port
            tempApiKey = settings.apiKey
            useHTTPS = settings.useHTTPS
        }
    }
}
