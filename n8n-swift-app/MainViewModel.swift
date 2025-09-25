import Foundation
import SwiftUI

@MainActor
final class MainViewModel: ObservableObject {
    @Published var workflows: [N8NClient.WorkflowSummary] = []
    @Published var isLoading = false
    @Published var togglingIds: Set<Int> = []
    @Published var errorMessage: IdentifiableString?

    private var client: N8NClient?

    func refresh(settings: SettingsStore) async {
        isLoading = true
        client = N8NClient(settings: settings)
        do {
            let list = try await client!.listWorkflows()
            // sort
            self.workflows = list.sorted { ($0.name ?? "") < ($1.name ?? "") }
        } catch {
            self.errorMessage = IdentifiableString(id: UUID().uuidString, value: (error as? LocalizedError)?.errorDescription ?? "\(error.localizedDescription)")
        }
        isLoading = false
    }

    func setActive(wf: N8NClient.WorkflowSummary, active: Bool) async {
        guard let settings = client?.settings else { return }
        togglingIds.insert(wf.id)
        do {
            try await client?.setWorkflowActive(wf.id, active: active)
            // update local state
            if let idx = workflows.firstIndex(where: { $0.id == wf.id }) {
                var copy = workflows[idx]
                copy = N8NClient.WorkflowSummary(id: copy.id, name: copy.name, active: active)
                workflows[idx] = copy
            }
        } catch {
            self.errorMessage = IdentifiableString(id: UUID().uuidString, value: (error as? LocalizedError)?.errorDescription ?? "\(error.localizedDescription)")
        }
        togglingIds.remove(wf.id)
    }
}

struct IdentifiableString: Identifiable {
    let id: String
    let value: String
}
extension IdentifiableString: LocalizedError {
    var errorDescription: String? { value }
}
