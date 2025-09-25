import SwiftUI

struct WorkflowDetailView: View {
    @EnvironmentObject var settings: SettingsStore
    let workflow: N8NClient.WorkflowSummary
    @StateObject private var vm = WorkflowDetailViewModel()

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Workflow")) {
                    Text(workflow.name ?? "Untitled").font(.title3)
                    HStack {
                        Text("ID:")
                        Spacer()
                        Text("\(workflow.id)")
                    }
                    HStack {
                        Text("Active:")
                        Spacer()
                        Text((workflow.active ?? false) ? "Yes" : "No")
                    }
                }
                Section(header: HStack {
                    Text("Executions")
                    Spacer()
                    Button(action: { Task { await vm.fetchExecutions(settings: settings, workflowId: workflow.id) } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }) {
                    if vm.isLoading {
                        ProgressView()
                    } else {
                        if vm.executions.isEmpty {
                            Text("No recent executions found.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(vm.executions) { e in
                                VStack(alignment: .leading) {
                                    Text("ID: \(e.id)")
                                        .font(.caption)
                                    HStack {
                                        Text(e.status ?? "—")
                                        Spacer()
                                        Text(e.startedAt ?? "")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(workflow.name ?? "Workflow")
        .task {
            await vm.fetchExecutions(settings: settings, workflowId: workflow.id)
        }
        .alert(item: $vm.errorMessage) { msg in
            Alert(title: Text("Error"), message: Text(msg.value), dismissButton: .default(Text("OK")))
        }
    }
}
