import SwiftUI

struct SimpleUpdatesView: View {
    @StateObject private var updateViewModel = SimpleUpdateViewModel()
    @State private var showInstallConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Updates")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Keep Ruma up to date")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await updateViewModel.checkForUpdates()
                    }
                }) {
                    HStack {
                        if updateViewModel.isCheckingForUpdates {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Check for Updates")
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!updateViewModel.updateState.canCheckForUpdates)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Current Version
                    Text("Current Version")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ruma")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                Text("Version \(updateViewModel.currentVersion)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("Installed")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        // Update Available Section
                        if let updateInfo = updateViewModel.updateInfo {
                            Divider()
                            
                            if updateInfo.updateAvailable {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundColor(.orange)
                                        Text("Update Available")
                                            .font(.headline)
                                            .foregroundColor(.orange)
                                    }
                                    
                                    if let latestVersion = updateInfo.latestVersion {
                                        Text("Version \(latestVersion) is now available")
                                            .font(.subheadline)
                                    }
                                    
                                    if let downloadSize = updateInfo.downloadSize {
                                        Text("Download size: \(updateViewModel.formatBytes(downloadSize))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    if let releaseNotes = updateInfo.releaseNotes, !releaseNotes.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("What's New:")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            
                                            Text(releaseNotes)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.leading, 8)
                                        }
                                    }
                                    
                                    // Update Controls
                                    VStack(alignment: .leading, spacing: 16) {
                                        // Auto-Update Toggle
                                        HStack {
                                            Toggle("Automatically install updates", isOn: $updateViewModel.autoUpdateEnabled)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            Image(systemName: updateViewModel.autoUpdateEnabled ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(updateViewModel.autoUpdateEnabled ? .green : .secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(.secondary.opacity(0.1))
                                        .cornerRadius(8)
                                        
                                        // Download Progress
                                        if updateViewModel.isDownloadingUpdate || 
                                           updateViewModel.downloadProgress > 0 || 
                                           updateViewModel.updateState == .downloading ||
                                           updateViewModel.updateState == .paused ||
                                           updateViewModel.updateState == .downloadComplete {
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack {
                                                    Text(updateViewModel.updateState == .paused ? "Download Paused" : 
                                                         updateViewModel.updateState == .downloadComplete ? "Download Complete" :
                                                         updateViewModel.updateState == .installing ? "Installing..." :
                                                         "Downloading...")
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(
                                                            updateViewModel.updateState == .paused ? .orange :
                                                            updateViewModel.updateState == .downloadComplete ? .green :
                                                            updateViewModel.updateState == .installing ? .blue :
                                                            .primary
                                                        )
                                                    
                                                    Spacer()
                                                    
                                                    if updateViewModel.totalBytes > 0 {
                                                        Text("\(updateViewModel.formatBytes(updateViewModel.downloadedBytes)) / \(updateViewModel.formatBytes(updateViewModel.totalBytes))")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                
                                                ProgressView(value: updateViewModel.downloadProgress)
                                                    .progressViewStyle(.linear)
                                                    .tint(updateViewModel.updateState == .paused ? .orange :
                                                          updateViewModel.updateState == .downloadComplete ? .green : .blue)
                                                
                                                Text(updateViewModel.updateState == .downloadComplete ? "100% complete" :
                                                     updateViewModel.updateState == .paused ? "\(Int(updateViewModel.downloadProgress * 100))% paused" :
                                                     "\(Int(updateViewModel.downloadProgress * 100))% complete")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                
                                                // Download Control Buttons
                                                HStack(spacing: 8) {
                                                    if updateViewModel.updateState.canResume {
                                                        Button("Resume") {
                                                            Task { await updateViewModel.resumeDownload() }
                                                        }
                                                        .buttonStyle(.bordered)
                                                        .controlSize(.small)
                                                    }
                                                    
                                                    if updateViewModel.updateState.canPause {
                                                        Button("Pause") {
                                                            Task { await updateViewModel.pauseDownload() }
                                                        }
                                                        .buttonStyle(.bordered)
                                                        .controlSize(.small)
                                                    }
                                                    
                                                    if updateViewModel.updateState.canCancel {
                                                        Button("Cancel") {
                                                            Task { await updateViewModel.cancelDownload() }
                                                        }
                                                        .buttonStyle(.bordered)
                                                        .controlSize(.small)
                                                        .tint(.red)
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(.blue.opacity(0.1))
                                            .cornerRadius(8)
                                        }
                                        
                                        // Main Action Button
                                        if updateViewModel.updateState.canDownload || updateViewModel.updateState.canInstall {
                                            Button(action: {
                                                if updateViewModel.downloadedFilePath != nil {
                                                    // If auto-update is enabled, install directly without confirmation
                                                    // If auto-update is disabled, show confirmation dialog
                                                    if updateViewModel.autoUpdateEnabled {
                                                        Task {
                                                            await updateViewModel.installUpdate()
                                                        }
                                                    } else {
                                                        showInstallConfirmation = true
                                                    }
                                                } else {
                                                    Task {
                                                        await updateViewModel.unifiedUpdateAction()
                                                    }
                                                }
                                            }) {
                                                HStack {
                                                    if updateViewModel.downloadedFilePath != nil {
                                                        Image(systemName: "square.and.arrow.down.fill")
                                                        Text(updateViewModel.autoUpdateEnabled ? "Install Update (Auto)" : "Install Update")
                                                    } else {
                                                        Image(systemName: updateViewModel.autoUpdateEnabled ? "arrow.down.app.fill" : "arrow.down.circle.fill")
                                                        Text(updateViewModel.autoUpdateEnabled ? "Download & Install Update" : "Download Update")
                                                    }
                                                }
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(updateViewModel.downloadedFilePath != nil ? .green : (updateViewModel.autoUpdateEnabled ? .purple : .blue))
                                                .cornerRadius(10)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        
                                        // Help Text
                                        if updateViewModel.autoUpdateEnabled {
                                            Text("Updates will be downloaded and installed automatically")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("Updates will be downloaded only. You can install them manually when ready")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding()
                                .background(.orange.opacity(0.1))
                                .cornerRadius(12)
                            } else {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("You're running the latest version")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                                .padding()
                                .background(.green.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(20)
                    .background(.thickMaterial)
                    .cornerRadius(16)
                    .padding(.horizontal, 24)
                    
                    // App Version Backups Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Version Backups")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Button(action: {
                                Task {
                                    await updateViewModel.loadAvailableBackups()
                                }
                            }) {
                                HStack {
                                    if updateViewModel.isLoadingBackups {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Refresh")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(updateViewModel.isLoadingBackups)
                        }
                        
                        Text("Restore previous app versions if needed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if updateViewModel.availableBackups.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "archivebox")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("No backups available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Backups are created automatically when installing updates")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(updateViewModel.availableBackups) { backup in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(backup.appName)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                
                                                if let backupType = backup.backupType, backupType == "Before Restore" {
                                                    Text("(Before Restore)")
                                                        .font(.caption)
                                                        .foregroundColor(.orange)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(.orange.opacity(0.2))
                                                        .cornerRadius(4)
                                                }
                                            }
                                            
                                            Text(backup.timestampDisplay)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            Text("\(String(format: "%.1f", backup.sizeMb)) MB")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        HStack(spacing: 8) {
                                            Button("Restore") {
                                                Task {
                                                    await updateViewModel.restoreFromBackup(backup)
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .disabled(updateViewModel.isRestoringBackup)
                                            
                                            Button("Delete") {
                                                Task {
                                                    await updateViewModel.deleteBackup(backup)
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .tint(.red)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.secondary.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        
                        if !updateViewModel.backupMessage.isEmpty {
                            Text(updateViewModel.backupMessage)
                                .font(.caption)
                                .foregroundColor(updateViewModel.backupMessage.contains("failed") || updateViewModel.backupMessage.contains("error") ? .red : .secondary)
                        }
                    }
                    .padding(20)
                    .background(.thickMaterial)
                    .cornerRadius(16)
                    .padding(.horizontal, 24)
                }
            }
            
            // Status Message
            if !updateViewModel.updateMessage.isEmpty {
                Text(updateViewModel.updateMessage)
                    .font(.caption)
                    .foregroundStyle(
                        updateViewModel.updateMessage.contains("error") || 
                        updateViewModel.updateMessage.contains("failed") ||
                        updateViewModel.updateMessage.contains("Error") ||
                        updateViewModel.updateMessage.contains("Failed") ? .red : .secondary
                    )
                    .padding(.horizontal, 24)
            }
            
            Spacer()
        }
        .onAppear {
            Task {
                // First check if there's any existing download progress
                await updateViewModel.loadDownloadProgress()
                
                // Then check for updates
                await updateViewModel.checkForUpdates()
                await updateViewModel.loadAvailableBackups()
                
                // Start progress monitoring after loading progress state
                // But don't start if we're currently cancelling
                if !updateViewModel.isCancelling &&
                   (updateViewModel.isDownloadingUpdate || 
                    updateViewModel.downloadProgress > 0 || 
                    updateViewModel.updateState == .downloading ||
                    updateViewModel.updateState == .paused) {
                    updateViewModel.startProgressMonitoring()
                }
            }
        }
        .onDisappear {
            updateViewModel.stopProgressMonitoring()
        }
        .alert("Install Update", isPresented: $showInstallConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Install", role: .destructive) {
                Task {
                    await updateViewModel.installUpdate()
                }
            }
        } message: {
            Text("Installing this update will restart the application. Make sure all your work is saved before proceeding.")
        }
    }
}

#Preview {
    SimpleUpdatesView()
}
