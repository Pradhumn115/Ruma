import Foundation
import SwiftUI

@MainActor
class SimpleUpdateViewModel: ObservableObject {
    @Published var currentVersion = "0.1.0"
    @Published var updateInfo: UpdateInfo?
    @Published var isCheckingForUpdates = false
    @Published var isDownloadingUpdate = false
    @Published var downloadProgress: Double = 0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var autoUpdateEnabled = false
    @Published var canResumeDownload = false
    @Published var isPaused = false
    @Published var downloadedFilePath: String?
    @Published var updateMessage = ""
    @Published var updateState: UpdateState = .idle
    @Published var isCancelling = false
    
    enum UpdateState: Equatable {
        case idle
        case checkingForUpdates
        case updateAvailable
        case downloading
        case paused
        case downloadComplete
        case installing
        case installComplete
        case error(String)
        
        var description: String {
            switch self {
            case .idle: return "Ready"
            case .checkingForUpdates: return "Checking for updates..."
            case .updateAvailable: return "Update available"
            case .downloading: return "Downloading..."
            case .paused: return "Download paused"
            case .downloadComplete: return "Download complete"
            case .installing: return "Installing..."
            case .installComplete: return "Install complete"
            case .error(let message): return "Error: \(message)"
            }
        }
        
        var canCheckForUpdates: Bool {
            switch self {
            case .idle, .updateAvailable, .error, .installComplete: return true
            default: return false
            }
        }
        
        var canDownload: Bool {
            switch self {
            case .updateAvailable: return true
            default: return false
            }
        }
        
        var canPause: Bool {
            switch self {
            case .downloading: return true
            default: return false
            }
        }
        
        var canResume: Bool {
            switch self {
            case .paused: return true
            default: return false
            }
        }
        
        var canInstall: Bool {
            switch self {
            case .downloadComplete: return true
            default: return false
            }
        }
        
        var canCancel: Bool {
            switch self {
            case .downloading, .paused: return true
            default: return false
            }
        }
    }
    
    private var baseURL: String {
        return serverConfig.currentServerURL
    }
    private var progressTimer: Timer?
    
    struct UpdateInfo: Codable {
        let updateAvailable: Bool
        let currentVersion: String
        let latestVersion: String?
        let downloadUrl: String?
        let downloadSize: Int64?
        let releaseNotes: String?
        
        enum CodingKeys: String, CodingKey {
            case updateAvailable = "update_available"
            case currentVersion = "current_version"
            case latestVersion = "latest_version"
            case downloadUrl = "download_url"
            case downloadSize = "download_size"
            case releaseNotes = "release_notes"
        }
    }
    
    struct DownloadProgress: Codable {
        let progress: Double
        let downloaded: Int64
        let totalSize: Int64
        let status: String
        let canResume: Bool
        let isComplete: Bool
        let path: String?
        
        enum CodingKeys: String, CodingKey {
            case progress, downloaded, status, path
            case totalSize = "total_size"
            case canResume = "can_resume"
            case isComplete = "is_complete"
        }
    }
    
//    init() {
//        startProgressMonitoring()
//    }
//    
//    deinit {
//        stopProgressMonitoring()
//    }
    
    func checkForUpdates() async {
        updateState = .checkingForUpdates
        isCheckingForUpdates = true
        updateMessage = ""
        
        do {
            let url = URL(string: "\(baseURL)/check_updates")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
            
            updateInfo = info
            currentVersion = info.currentVersion
            
            if info.updateAvailable {
                updateState = .updateAvailable
                updateMessage = "Update available: v\(info.latestVersion ?? "unknown")"
            } else {
                updateState = .idle
                updateMessage = "You're running the latest version"
            }
        } catch {
            updateState = .error(error.localizedDescription)
            updateMessage = "Failed to check for updates: \(error.localizedDescription)"
        }
        
        isCheckingForUpdates = false
    }
    
    func downloadUpdate() async {
        guard let updateInfo = updateInfo,
              let downloadUrl = updateInfo.downloadUrl else {
            updateState = .error("No download URL available")
            updateMessage = "No download URL available"
            return
        }
        
        updateState = .downloading
        isDownloadingUpdate = true
        updateMessage = "Starting download..."
        
        // Start progress monitoring when download begins
        startProgressMonitoring()
        
        do {
            let url = URL(string: "\(baseURL)/download_update")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = [
                "download_url": downloadUrl,
                "auto_install": autoUpdateEnabled
            ] as [String : Any]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                updateMessage = "Download started"
            } else {
                updateState = .error("Failed to start download")
                updateMessage = "Failed to start download"
                isDownloadingUpdate = false
            }
        } catch {
            updateState = .error(error.localizedDescription)
            updateMessage = "Download error: \(error.localizedDescription)"
            isDownloadingUpdate = false
        }
    }
    
    func installUpdate() async {
        guard let filePath = downloadedFilePath else {
            updateState = .error("No file to install")
            updateMessage = "No file to install"
            return
        }
        
        updateState = .installing
        updateMessage = "Installing update..."
        
        do {
            let url = URL(string: "\(baseURL)/install_update")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = [
                "file_path": filePath,
                "auto_install": true
            ] as [String : Any]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let success = result?["success"] as? Bool, success {
                    updateState = .installComplete
                    updateMessage = "Update installed successfully. App will restart automatically."
                    
                    // Clear download state after successful installation
                    downloadedFilePath = nil
                    downloadProgress = 0
                    downloadedBytes = 0
                    totalBytes = 0
                } else if let error = result?["error"] as? String {
                    updateState = .error(error)
                    updateMessage = "Installation failed: \(error)"
                }
            } else {
                updateState = .error("Installation request failed")
                updateMessage = "Installation request failed"
            }
        } catch {
            updateState = .error(error.localizedDescription)
            updateMessage = "Installation error: \(error.localizedDescription)"
            
            // Keep download file available for retry
            // Don't clear downloadedFilePath so user can try again
        }
    }
    
    func pauseDownload() async {
        do {
            let url = URL(string: "\(baseURL)/pause_update_download")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let (_, _) = try await URLSession.shared.data(for: request)
            updateState = .paused
            updateMessage = "Download paused"
        } catch {
            updateState = .error("Failed to pause download")
            updateMessage = "Failed to pause download"
        }
    }
    
    func resumeDownload() async {
        do {
            let url = URL(string: "\(baseURL)/resume_update_download")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let (_, _) = try await URLSession.shared.data(for: request)
            updateState = .downloading
            updateMessage = "Download resumed"
            
            // Start progress monitoring when resuming download
            startProgressMonitoring()
        } catch {
            updateState = .error("Failed to resume download")
            updateMessage = "Failed to resume download"
        }
    }
    
    func ensureProgressMonitoring() {
        // Ensure progress monitoring is active for downloads and paused states
        // But don't start if we're currently cancelling
        if (updateState == .downloading || updateState == .paused) && progressTimer == nil && !isCancelling {
            startProgressMonitoring()
        }
    }
    
    func cancelDownload() async {
        // Set cancelling flag to prevent race conditions
        isCancelling = true
        
        do {
            let url = URL(string: "\(baseURL)/cancel_update_download")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let (_, _) = try await URLSession.shared.data(for: request)
            
            // Stop progress monitoring immediately
            stopProgressMonitoring()
            
            // Reset state completely
            updateState = updateInfo?.updateAvailable == true ? .updateAvailable : .idle
            isDownloadingUpdate = false
            downloadProgress = 0
            downloadedBytes = 0
            totalBytes = 0
            canResumeDownload = false
            isPaused = false
            downloadedFilePath = nil
            updateMessage = "Download cancelled"
            
            // Wait a moment to ensure backend processes the cancel
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
        } catch {
            updateState = .error("Failed to cancel download")
            updateMessage = "Failed to cancel download"
        }
        
        // Clear cancelling flag
        isCancelling = false
    }
    
    func unifiedUpdateAction() async {
        if downloadedFilePath != nil {
            // File already downloaded, install it
            await installUpdate()
        } else {
            // Download first
            await downloadUpdate()
        }
    }
    
    func startProgressMonitoring() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                await self.loadDownloadProgress()
            }
        }
    }
    
    func stopProgressMonitoring() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    func loadDownloadProgress() async {
        do {
            let url = URL(string: "\(baseURL)/download_progress")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let progress = try JSONDecoder().decode(DownloadProgress.self, from: data)
            
            downloadProgress = progress.progress
            downloadedBytes = progress.downloaded
            totalBytes = progress.totalSize
            canResumeDownload = progress.canResume
            isPaused = progress.status == "paused"
            
            // Update state based on progress
            if progress.isComplete {
                updateState = .downloadComplete
                isDownloadingUpdate = false
                downloadedFilePath = progress.path
                updateMessage = "Download complete. Ready to install."
                
                // Stop monitoring since download is complete
                if progressTimer != nil {
                    stopProgressMonitoring()
                }
            } else if progress.status == "downloading" {
                updateState = .downloading
                isDownloadingUpdate = true
                updateMessage = "Downloading... \(Int(progress.progress * 100))%"
            } else if progress.status == "paused" {
                updateState = .paused
                isDownloadingUpdate = false
                updateMessage = "Download paused at \(Int(progress.progress * 100))%"
                // Keep monitoring for paused downloads
            } else if progress.status == "none" || progress.progress == 0 {
                // No download in progress, reset state
                updateState = updateInfo?.updateAvailable == true ? .updateAvailable : .idle
                isDownloadingUpdate = false
                downloadedFilePath = nil
                updateMessage = ""
            }
        } catch {
            // Handle network errors gracefully
            if updateState == .downloading || updateState == .paused {
                // Keep current state if we're in the middle of something
                print("Progress update failed, keeping current state: \(error)")
            } else {
                // Reset state only if we're not actively downloading
                updateState = updateInfo?.updateAvailable == true ? .updateAvailable : .idle
                updateMessage = ""
            }
        }
    }
    
    private func checkAutoInstallStatus() async {
        // Wait a moment for auto-install to potentially complete
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Check if auto-install completed by looking for installation success
        if autoUpdateEnabled && updateState == .downloadComplete {
            updateState = .installComplete
            updateMessage = "Update installed automatically. Please restart the app."
            
            // Stop progress monitoring when installation completes
            stopProgressMonitoring()
        }
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // App Backup Management
    @Published var availableBackups: [AppBackup] = []
    @Published var backupMessage = ""
    @Published var isLoadingBackups = false
    @Published var isRestoringBackup = false
    
    struct AppBackupsResponse: Codable {
        let success: Bool
        let backups: [AppBackup]
        let totalBackups: Int
        
        enum CodingKeys: String, CodingKey {
            case success, backups
            case totalBackups = "total_backups"
        }
    }
    
    struct AppBackup: Codable, Identifiable {
        let id = UUID()
        let appName: String
        let backupPath: String
        let backupName: String
        let timestamp: String
        let timestampDisplay: String
        let sizeMb: Double
        let backupType: String?
        
        enum CodingKeys: String, CodingKey {
            case appName = "app_name"
            case backupPath = "backup_path"
            case backupName = "backup_name"
            case timestamp
            case timestampDisplay = "timestamp_display"
            case sizeMb = "size_mb"
            case backupType = "backup_type"
        }
    }
    
    func loadAvailableBackups() async {
        isLoadingBackups = true
        backupMessage = ""
        
        do {
            let url = URL(string: "\(baseURL)/app_backups")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AppBackupsResponse.self, from: data)
            
            if response.success {
                availableBackups = response.backups
                backupMessage = response.backups.isEmpty ? "No backups available" : "\(response.totalBackups) backup(s) available"
            } else {
                backupMessage = "Failed to load backups"
            }
        } catch {
            backupMessage = "Failed to load backups: \(error.localizedDescription)"
        }
        
        isLoadingBackups = false
    }
    
    func restoreFromBackup(_ backup: AppBackup) async {
        isRestoringBackup = true
        backupMessage = "Restoring from backup..."
        
        do {
            let url = URL(string: "\(baseURL)/restore_backup")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = ["backup_name": backup.backupName]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let success = result?["success"] as? Bool, success {
                backupMessage = result?["message"] as? String ?? "Backup restored successfully"
                updateState = .installComplete
                updateMessage = "App restored from backup. Please restart the app."
            } else if let error = result?["error"] as? String {
                backupMessage = "Restore failed: \(error)"
            }
        } catch {
            backupMessage = "Restore error: \(error.localizedDescription)"
        }
        
        isRestoringBackup = false
    }
    
    func deleteBackup(_ backup: AppBackup) async {
        do {
            let url = URL(string: "\(baseURL)/delete_backup")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = ["backup_name": backup.backupName]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let success = result?["success"] as? Bool, success {
                backupMessage = result?["message"] as? String ?? "Backup deleted successfully"
                // Refresh backup list
                await loadAvailableBackups()
            } else if let error = result?["error"] as? String {
                backupMessage = "Delete failed: \(error)"
            }
        } catch {
            backupMessage = "Delete error: \(error.localizedDescription)"
        }
    }
}
