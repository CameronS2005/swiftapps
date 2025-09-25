import SwiftUI

struct MainView: View {
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var vm = MainViewModel()
    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading workflows...")
                        .padding()
                } else {
                    List {
                        Section {
                            ForEach(vm.workflows) { wf in
                                NavigationLink(value: wf) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(wf.name ?? "Untitled")
                                                .font(.headline)
                                            Text("ID: \(wf.id)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Toggle(isOn: Binding(
                                            get: { wf.active ?? false },
                                            set: { newVal in
                                                Task {
                                                    await vm.setActive(wf: wf, active: newVal)
                                                }
                                            })) {
                                            Text("")
                                        }
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                        .disabled(vm.togglingIds.contains(wf.id))
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text("Workflows")
                                Spacer()
                                Button(action: { Task { await vm.refresh(settings: settings) } }) {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("n8n Manager")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: SettingsView().environmentObject(settings)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: N8NClient.WorkflowSummary.self) { wf in
                WorkflowDetailView(workflow: wf).environmentObject(settings)
            }
            .onAppear {
                Task {
                    await vm.refresh(settings: settings)
                }
            }
            .alert(item: $vm.errorMessage) { msg in
                Alert(title: Text("Error"), message: Text(msg), dismissButton: .default(Text("OK")))
            }
        }
    }
}
