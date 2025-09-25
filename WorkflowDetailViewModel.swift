import Foundation

@MainActor
final class WorkflowDetailViewModel: ObservableObject {
    @Published var executions: [N8NClient.ExecutionSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: IdentifiableString?

    func fetchExecutions(settings: SettingsStore, workflowId: Int) async {
        isLoading = true
        let client = N8NClient(settings: settings)
        do {
            let execs = try await client.listExecutions(workflowId: workflowId, limit: 20)
            self.executions = execs
        } catch {
            self.errorMessage = IdentifiableString(id: UUID().uuidString, value: (error as? LocalizedError)?.errorDescription ?? "\(error.localizedDescription)")
        }
        isLoading = false
    }
}
