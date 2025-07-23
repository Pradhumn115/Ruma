import SwiftUI

struct CleanupView: View {
    @ObservedObject var appState: AppState
    @State private var showingCleanupAlert = false
    @State private var selectedDownload: FailedDownload?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Storage Cleanup")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    Task {
                        await appState.loadFailedDownloads()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(appState.isLoadingFailedDownloads)
            }
            
            if appState.isLoadingFailedDownloads {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading failed downloads...")
                        .foregroundColor(.secondary)
                }
            } else if appState.failedDownloads.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("No failed downloads to clean up")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Failed Downloads (\(appState.failedDownloads.count))")
                            .font(.headline)
                        
                        Spacer()
                        
                        let totalSize = appState.failedDownloads.reduce(0) { $0 + $1.total_partial_size }
                        Text("Total: \(appState.formatBytes(totalSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(appState.failedDownloads) { download in
                                FailedDownloadRow(
                                    download: download,
                                    appState: appState,
                                    onCleanup: { selectedDownload in
                                        self.selectedDownload = selectedDownload
                                        self.showingCleanupAlert = true
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    
                    HStack {
                        Button(action: {
                            selectedDownload = nil
                            showingCleanupAlert = true
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Clean All")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                    }
                }
            }
            
            if !appState.cleanupMessage.isEmpty {
                Text(appState.cleanupMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .padding()
        
        .onAppear {
            Task {
                await appState.loadFailedDownloads()
            }
        }
        .alert("Confirm Cleanup", isPresented: $showingCleanupAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clean Up", role: .destructive) {
                Task {
                    if let download = selectedDownload {
                        await appState.cleanupSingleDownload(download.unique_id)
                    } else {
                        await appState.cleanupAllDownloads()
                    }
                }
            }
        } message: {
            if let download = selectedDownload {
                Text("This will permanently delete \(download.partial_files.count) partial files (\(appState.formatBytes(download.total_partial_size))) for \(download.model_id). This action cannot be undone.")
            } else {
                let totalFiles = appState.failedDownloads.flatMap { $0.partial_files }.count
                let totalSize = appState.failedDownloads.reduce(0) { $0 + $1.total_partial_size }
                Text("This will permanently delete \(totalFiles) partial files (\(appState.formatBytes(totalSize))) from \(appState.failedDownloads.count) failed downloads. This action cannot be undone.")
            }
        }
    }
}

struct FailedDownloadRow: View {
    let download: FailedDownload
    @ObservedObject var appState: AppState
    let onCleanup: (FailedDownload) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(download.model_id)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                
                HStack {
                    StatusBadge(status: download.status)
                    
                    Text("\(download.partial_files.count) files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(appState.formatBytes(download.total_partial_size))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let errorMessage = download.error_message, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Button(action: {
                onCleanup(download)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct StatusBadge: View {
    let status: String
    
    var body: some View {
        Text(status.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(textColor)
            .cornerRadius(4)
    }
    
    private var backgroundColor: Color {
        switch status.lowercased() {
        case "cancelled":
            return Color.orange.opacity(0.2)
        case "error":
            return Color.red.opacity(0.2)
        default:
            return Color.gray.opacity(0.2)
        }
    }
    
    private var textColor: Color {
        switch status.lowercased() {
        case "cancelled":
            return Color.orange
        case "error":
            return Color.red
        default:
            return Color.gray
        }
    }
}

#Preview {
    CleanupView(appState: AppState())
        .frame(width: 400, height: 500)
}
