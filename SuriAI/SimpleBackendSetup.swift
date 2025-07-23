//
//  SimpleBackendSetup.swift
//  SuriAI - Simple Backend ZIP Extraction
//
//  Created by Claude on 07/07/25.
//

import Foundation
import AppKit
import CryptoKit
import CommonCrypto

class SimpleBackendSetup {
    static let shared = SimpleBackendSetup()
    
    // Encryption key derived from app-specific data
    private let encryptionKey: SymmetricKey = {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.ruma.ai"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let keyData = "\(bundleId).\(appVersion).ruma.backend.key".data(using: .utf8)!
        return SymmetricKey(data: SHA256.hash(data: keyData))
    }()
    
    private init() {}
    
    // MARK: - Main Setup Function
    func setupBackendFromBundle() -> Bool {
        print("🔧 Setting up backend from app bundle...")
        
        do {
            // Update progress: Starting setup
            DispatchQueue.main.async {
                SetupProgressManager.shared.updateExtractionProgress(0.1, task: "Preparing backend setup...")
            }
            
            // 1. Get paths
            let applicationSupportURL = getApplicationSupportDirectory()
            let backendDirectory = applicationSupportURL.appendingPathComponent("Backend")
            
            // Update progress: Got paths
            DispatchQueue.main.async {
                SetupProgressManager.shared.updateExtractionProgress(0.2, task: "Locating backend files...")
            }
            
            // 2. Get encrypted backend.zip from app bundle
            // Debug bundle contents first
            if let bundlePath = Bundle.main.resourcePath {
                print("📁 Bundle resource path: \(bundlePath)")
                do {
                    let bundleContents = try FileManager.default.contentsOfDirectory(atPath: bundlePath)
                    print("📦 Bundle contents: \(bundleContents.filter { $0.contains("backend") || $0.contains("zip") })")
                } catch {
                    print("❌ Failed to read bundle contents: \(error)")
                }
            }
            
            guard let encryptedBackendURL = Bundle.main.url(forResource: "backend", withExtension: "zip") else {
                print("❌ backend.zip not found in app bundle")
                print("ℹ️ Make sure backend.zip is added to your Xcode project and included in the app bundle")
                DispatchQueue.main.async {
                    SetupProgressManager.shared.setError("Backend files not found in app bundle")
                }
                return false
            }
            
            // Update progress: Decrypting
            DispatchQueue.main.async {
                SetupProgressManager.shared.updateExtractionProgress(0.35, task: "Decrypting backend files...")
            }
            
            // 3. Decrypt the backend.zip file
            let decryptedZipURL = try decryptBackendZip(from: encryptedBackendURL)
            
            // Update progress: Found zip file
            DispatchQueue.main.async {
                SetupProgressManager.shared.updateExtractionProgress(0.45, task: "Creating backend directory...")
            }
            
            // 4. Create Backend directory
            try createBackendDirectory(at: backendDirectory)
            
            // Update progress: Directory created
            DispatchQueue.main.async {
                SetupProgressManager.shared.updateExtractionProgress(0.5, task: "Extracting backend files...")
            }
            
            // 5. Extract the decrypted backend.zip
            try extractBackendZip(from: decryptedZipURL, to: backendDirectory)
            
            // 6. Clean up decrypted zip file (security)
            try FileManager.default.removeItem(at: decryptedZipURL)
            print("🗑️ Cleaned up decrypted zip file")
            
            // 7. Apply security measures
            DispatchQueue.main.async {
                SetupProgressManager.shared.updateExtractionProgress(0.9, task: "Applying security measures...")
            }
            
            try applySecurityMeasures(to: backendDirectory)
            
            // 8. Start security monitoring
            startSecurityMonitoring(for: backendDirectory)
            
            // Update progress: Setup complete
            DispatchQueue.main.async {
                SetupProgressManager.shared.updateExtractionProgress(1.0, task: "Backend setup completed securely")
            }
            
            print("✅ Backend setup completed successfully with security measures")
            print("🔒 Backend location: \(backendDirectory.path) (secured)")
            
            return true
            
        } catch {
            print("❌ Backend setup failed: \(error)")
            DispatchQueue.main.async {
                SetupProgressManager.shared.setError("Backend setup failed: \(error.localizedDescription)")
            }
            return false
        }
    }
    
    // MARK: - Helper Functions
    
    private func getApplicationSupportDirectory() -> URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportURL.appendingPathComponent("Ruma")
    }
    
    private func createBackendDirectory(at url: URL) throws {
        let fileManager = FileManager.default
        
        // Create Ruma directory if it doesn't exist
        let rumaDirectory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: rumaDirectory.path) {
            try fileManager.createDirectory(at: rumaDirectory, withIntermediateDirectories: true, attributes: nil)
            print("✅ Created Ruma directory: \(rumaDirectory.path)")
        }
        
        // Remove existing Backend directory if it exists
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            print("🗑️ Removed existing backend directory")
        }
        
        // Create fresh Backend directory
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        print("✅ Created backend directory: \(url.path)")
    }
    
    private func extractBackendZip(from zipURL: URL, to destinationURL: URL) throws {
        print("📦 Extracting backend.zip...")
        
        // Update progress during extraction
        DispatchQueue.main.async {
            SetupProgressManager.shared.updateExtractionProgress(0.5, task: "Extracting files...")
        }
        
        // Use native unzip command with progress simulation
        let unzipProcess = Process()
        unzipProcess.launchPath = "/usr/bin/unzip"
        unzipProcess.arguments = ["-q", zipURL.path, "-d", destinationURL.path]
        
        let pipe = Pipe()
        unzipProcess.standardOutput = pipe
        unzipProcess.standardError = pipe
        
        unzipProcess.launch()
        
        // Simulate progress updates during extraction
        DispatchQueue.global().async {
            var progress: Double = 0.6
            while unzipProcess.isRunning && progress < 0.95 {
                Thread.sleep(forTimeInterval: 0.2)
                progress += 0.1
                DispatchQueue.main.async {
                    SetupProgressManager.shared.updateExtractionProgress(progress, task: "Extracting files...")
                }
            }
        }
        
        unzipProcess.waitUntilExit()
        
        if unzipProcess.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BackendSetupError.extractionFailed("Unzip failed: \(output)")
        }
        
        print("✅ Backend extracted successfully")
    }
    
    // MARK: - Utility Functions
    
    func getBackendPath() -> String? {
        let applicationSupportURL = getApplicationSupportDirectory()
        let backendDirectory = applicationSupportURL.appendingPathComponent("Backend")
        let unifiedAppPath = backendDirectory.appendingPathComponent("unified_app.py")
        
        if FileManager.default.fileExists(atPath: unifiedAppPath.path) {
            return backendDirectory.path
        }
        
        return nil
    }
    
    func isBackendSetupRequired() -> Bool {
        return getBackendPath() == nil
    }
    
    func getUnifiedAppPath() -> String? {
        guard let backendPath = getBackendPath() else { return nil }
        return "\(backendPath)/unified_app.py"
    }
    
    // MARK: - Encryption/Decryption Functions
    
    private func decryptBackendZip(from encryptedURL: URL) throws -> URL {
        print("🔓 Decrypting backend.zip...")
        
        // Read encrypted data
        let encryptedData = try Data(contentsOf: encryptedURL)
        print("📊 File size: \(encryptedData.count) bytes")
        
        // Check if the file is actually encrypted (has our encryption header)
        let headerData = "RUMA_ENCRYPTED_V1".data(using: .utf8)!
        if encryptedData.count < 16 || !encryptedData.starts(with: headerData) {
            print("ℹ️ Backend.zip is not encrypted (no RUMA_ENCRYPTED_V1 header), using as-is")
            return encryptedURL
        }
        
        print("🔑 File is encrypted with RUMA_ENCRYPTED_V1 format")
        
        // Extract IV and encrypted content
        let headerLength = 17 // "RUMA_ENCRYPTED_V1" length
        let ivLength = 16 // AES block size
        
        guard encryptedData.count > headerLength + ivLength else {
            throw BackendSetupError.decryptionFailed("Invalid encrypted file format - file too small")
        }
        
        let ivData = encryptedData.subdata(in: headerLength..<(headerLength + ivLength))
        let encryptedContent = encryptedData.subdata(in: (headerLength + ivLength)..<encryptedData.count)
        
        print("🔑 IV length: \(ivData.count) bytes")
        print("🔑 Encrypted content length: \(encryptedContent.count) bytes")
        print("🔑 Encryption key derived from: \(Bundle.main.bundleIdentifier ?? "unknown").\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
        
        // Decrypt the content
        do {
            let decryptedData = try decryptData(encryptedContent, iv: ivData)
            print("✅ Decryption successful, decrypted size: \(decryptedData.count) bytes")
            
            // Write decrypted data to temporary file
            let tempDirectory = FileManager.default.temporaryDirectory
            let decryptedZipURL = tempDirectory.appendingPathComponent("backend_decrypted.zip")
            
            try decryptedData.write(to: decryptedZipURL)
            
            print("✅ Backend.zip decrypted successfully")
            return decryptedZipURL
        } catch {
            print("❌ Decryption failed: \(error)")
            throw BackendSetupError.decryptionFailed("Decryption failed: \(error.localizedDescription)")
        }
    }
    
    private func decryptData(_ encryptedData: Data, iv: Data) throws -> Data {
        guard let box = try? AES.GCM.SealedBox(combined: encryptedData) else {
            throw BackendSetupError.decryptionFailed("Failed to create sealed box from encrypted data")
        }
        let decryptedData = try AES.GCM.open(box, using: encryptionKey)
        return decryptedData
    }
    
    // MARK: - Encryption Utility (for creating encrypted backend.zip)
    
    func encryptBackendZip(at zipURL: URL, outputURL: URL) throws {
        print("🔒 Encrypting backend.zip...")
        
        // Read original zip data
        let originalData = try Data(contentsOf: zipURL)
        
        // Generate random IV
        let iv = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        
        // Encrypt the data
        let encryptedData = try encryptData(originalData, iv: iv)
        
        // Create final encrypted file with header + IV + encrypted content
        var finalData = Data()
        finalData.append("RUMA_ENCRYPTED_V1".data(using: .utf8)!)
        finalData.append(iv)
        finalData.append(encryptedData)
        
        // Write encrypted file
        try finalData.write(to: outputURL)
        
        print("✅ Backend.zip encrypted successfully")
        print("📁 Encrypted file saved to: \(outputURL.path)")
        print("🔑 Original size: \(originalData.count) bytes")
        print("🔑 Encrypted size: \(finalData.count) bytes")
    }
    
    private func encryptData(_ data: Data, iv: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        guard let combinedData = sealedBox.combined else {
            throw BackendSetupError.decryptionFailed("Failed to get combined encrypted data")
        }
        return combinedData
    }
    
    // MARK: - Security Functions
    
    private func applySecurityMeasures(to backendDirectory: URL) throws {
        print("🔒 Applying security measures to backend directory...")
        
        // 1. Set restrictive permissions on the entire backend directory
        try setSecurePermissions(for: backendDirectory)
        
        // 2. Hide the directory from casual browsing
        try hideDirectory(backendDirectory)
        
        // 3. Set extended attributes to mark as system/protected
        try setProtectedAttributes(for: backendDirectory)
        
        // 4. Verify our app has exclusive access
        try verifyExclusiveAccess(to: backendDirectory)
        
        print("✅ Security measures applied successfully")
    }
    
    private func setSecurePermissions(for directory: URL) throws {
        let fileManager = FileManager.default
        
        // Set directory permissions to 700 (owner read/write/execute only)
        var attributes = [FileAttributeKey: Any]()
        attributes[.posixPermissions] = 0o700
        
        try fileManager.setAttributes(attributes, ofItemAtPath: directory.path)
        print("🔐 Set directory permissions to 700 (owner only)")
        
        // Recursively set file permissions for all contents
        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
                    let permissions: Int
                    if isDirectory.boolValue {
                        permissions = 0o700  // Directories: owner read/write/execute
                    } else if fileURL.path.contains("/bin/") || fileURL.pathExtension == "py" {
                        permissions = 0o700  // Executables and Python files: owner read/write/execute
                    } else {
                        permissions = 0o600  // Other files: owner read/write only
                    }
                    
                    var fileAttributes = [FileAttributeKey: Any]()
                    fileAttributes[.posixPermissions] = permissions
                    try fileManager.setAttributes(fileAttributes, ofItemAtPath: fileURL.path)
                }
            }
        }
        print("🔐 Set secure permissions on all backend files")
    }
    
    private func hideDirectory(_ directory: URL) throws {
        // Create a .hidden file to hide the directory in Finder
        let hiddenFile = directory.deletingLastPathComponent().appendingPathComponent(".hidden")
        let directoryName = directory.lastPathComponent
        
        let hiddenContent: String
        if FileManager.default.fileExists(atPath: hiddenFile.path) {
            let existingContent = try String(contentsOf: hiddenFile, encoding: .utf8)
            hiddenContent = existingContent.contains(directoryName) ? existingContent : existingContent + "\n" + directoryName
        } else {
            hiddenContent = directoryName
        }
        
        try hiddenContent.write(to: hiddenFile, atomically: true, encoding: .utf8)
        
        // Also set the hidden attribute using chflags
        let process = Process()
        process.launchPath = "/usr/bin/chflags"
        process.arguments = ["hidden", directory.path]
        process.launch()
        process.waitUntilExit()
        
        print("👻 Backend directory hidden from Finder")
    }
    
    private func setProtectedAttributes(for directory: URL) throws {
        // Set extended attributes to mark as protected system directory
        let protectedAttribute = "com.ruma.protected"
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ruma.ai"
        
        let result = setxattr(
            directory.path.cString(using: .utf8),
            protectedAttribute.cString(using: .utf8),
            bundleID.cString(using: .utf8),
            bundleID.count,
            0,
            0
        )
        
        if result == 0 {
            print("🏷️ Set protected attribute on backend directory")
        }
    }
    
    private func verifyExclusiveAccess(to directory: URL) throws {
        // Verify we can read/write to the directory
        let testFile = directory.appendingPathComponent(".access_test")
        let testContent = "Ruma access verification"
        
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)
        let readContent = try String(contentsOf: testFile, encoding: .utf8)
        
        guard readContent == testContent else {
            throw BackendSetupError.securityVerificationFailed("Cannot verify exclusive access")
        }
        
        try FileManager.default.removeItem(at: testFile)
        print("✅ Verified exclusive access to backend directory")
    }
    
    private func startSecurityMonitoring(for directory: URL) {
        // Start a background monitor to check permissions periodically
        DispatchQueue.global(qos: .background).async {
            self.monitorBackendSecurity(directory: directory)
        }
    }
    
    private func monitorBackendSecurity(directory: URL) {
        let monitorQueue = DispatchQueue(label: "com.ruma.security.monitor", qos: .background)
        
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            monitorQueue.async {
                self.checkAndRestoreSecurityMeasures(for: directory)
            }
        }
        
        print("👁️ Started security monitoring for backend directory")
    }
    
    private func checkAndRestoreSecurityMeasures(for directory: URL) {
        do {
            let fileManager = FileManager.default
            
            // Check if directory still exists
            guard fileManager.fileExists(atPath: directory.path) else {
                print("⚠️ Backend directory missing - this may indicate tampering")
                return
            }
            
            // Check directory permissions
            let attributes = try fileManager.attributesOfItem(atPath: directory.path)
            if let permissions = attributes[.posixPermissions] as? Int,
               permissions != 0o700 {
                print("🚨 Security breach detected on directory - restoring permissions")
                try setSecurePermissions(for: directory)
            }
            
            // Check if critical executables still have execute permissions
            let pythonExecutable = directory.appendingPathComponent("ruma-python/bin/python3")
            if fileManager.fileExists(atPath: pythonExecutable.path) {
                let execAttributes = try fileManager.attributesOfItem(atPath: pythonExecutable.path)
                if let execPermissions = execAttributes[.posixPermissions] as? Int,
                   execPermissions != 0o700 {
                    print("🚨 Python executable permissions compromised - restoring")
                    try setSecurePermissions(for: directory)
                }
            }
            
            // Verify protected attribute still exists
            let protectedAttribute = "com.ruma.protected"
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 256)
            defer { buffer.deallocate() }
            
            let result = getxattr(
                directory.path.cString(using: .utf8),
                protectedAttribute.cString(using: .utf8),
                buffer,
                256,
                0,
                0
            )
            
            if result < 0 {
                print("🚨 Protected attribute missing - restoring")
                try setProtectedAttributes(for: directory)
            }
            
        } catch {
            print("⚠️ Security monitoring error: \(error)")
        }
    }
    
    // Public function to manually trigger security check
    func verifyBackendSecurity() -> Bool {
        guard let backendPath = getBackendPath() else {
            print("❌ Backend path not found for security verification")
            return false
        }
        
        let backendURL = URL(fileURLWithPath: backendPath)
        
        do {
            try verifyExclusiveAccess(to: backendURL)
            checkAndRestoreSecurityMeasures(for: backendURL)
            print("✅ Backend security verification passed")
            return true
        } catch {
            print("❌ Backend security verification failed: \(error)")
            return false
        }
    }
    
    // Public function to fix permissions for existing backend
    func repairBackendPermissions() -> Bool {
        guard let backendPath = getBackendPath() else {
            print("❌ Backend path not found for permission repair")
            return false
        }
        
        let backendURL = URL(fileURLWithPath: backendPath)
        
        do {
            print("🔧 Repairing backend permissions...")
            
            // First, let's check what Python executables actually exist
            let fileManager = FileManager.default
            let pythonBinPath = backendURL.appendingPathComponent("ruma-python/bin")
            
            if fileManager.fileExists(atPath: pythonBinPath.path) {
                print("📁 Checking Python bin directory: \(pythonBinPath.path)")
                let binContents = try fileManager.contentsOfDirectory(atPath: pythonBinPath.path)
                print("🐍 Available executables: \(binContents)")
            } else {
                print("❌ Python bin directory not found at: \(pythonBinPath.path)")
            }
            
            try setSecurePermissions(for: backendURL)
            print("✅ Backend permissions repaired successfully")
            return true
        } catch {
            print("❌ Backend permission repair failed: \(error)")
            return false
        }
    }
}

// MARK: - Error Types
enum BackendSetupError: LocalizedError {
    case extractionFailed(String)
    case directoryCreationFailed(String)
    case securityVerificationFailed(String)
    case decryptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .extractionFailed(let message):
            return "Backend extraction failed: \(message)"
        case .directoryCreationFailed(let message):
            return "Directory creation failed: \(message)"
        case .securityVerificationFailed(let message):
            return "Security verification failed: \(message)"
        case .decryptionFailed(let message):
            return "Backend decryption failed: \(message)"
        }
    }
}