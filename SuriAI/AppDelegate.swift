//
//  AppDelegate.swift
//  FloatingWindow2
//
//  Created by Pradhumn Gupta on 31/05/25.
//

import Foundation
import SwiftUI
import AppKit
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    var contentWindow: NSWindow?
    var setupWindow: SetupWindowController?
    var hotkey: HotKey?
    private let uiStateManager = UIStateManager.shared
    @StateObject private var dynamicPlacementManager = DynamicIslandPlacementManager.shared
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        setupHotkey()
        
        // Initialize UI state tracking
        print("🔍 UI State Manager initialized")
        
        // Check if this is first time setup or if backend needs setup
        let needsSetup = SimpleBackendSetup.shared.isBackendSetupRequired()
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "HasLaunchedBefore")
        
        // Welcome window will be automatically shown by SwiftUI when isFirstLaunch is true
        
        // Verify backend security if it exists
        if !needsSetup {
            DispatchQueue.global(qos: .background).async {
                let securityStatus = SimpleBackendSetup.shared.verifyBackendSecurity()
                if !securityStatus {
                    print("⚠️ Backend security verification failed on startup - attempting repair")
                    SimpleBackendSetup.shared.repairBackendPermissions()
                }
            }
        }
        
        if needsSetup || isFirstLaunch {
            // FIRST-TIME SETUP: Show full setup window with extraction + initialization
            showSetupWindow()
            
            // Perform setup in background
            DispatchQueue.global(qos: .userInitiated).async {
                self.performBackendSetup()
            }
        } else {
            // BACKEND LOADING: Show initialization-only window
            showInitializationWindow()
            
            // Backend already exists, just start it
            DispatchQueue.global(qos: .userInitiated).async {
                print("✅ Backend already setup, starting server...")
                DispatchQueue.main.async {
                    SetupProgressManager.shared.setInitializing(task: "Starting AI backend...")
                }
                PythonScriptRunner.shared.runPythonScript()
            }
        }
        
        // Mark as launched if first time
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "HasLaunchedBefore")
        }
        
        // Listen for setup window close
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(setupWindowClosed),
            name: NSNotification.Name("CloseSetupWindow"),
            object: nil
        )
        
        
        // Listen for retry setup
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(retrySetup),
            name: NSNotification.Name("RetryBackendSetup"),
            object: nil
        )
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Clean shutdown of Python backend
        PythonScriptRunner.shared.stopPythonScript()
    }
    
    // MARK: - Setup Window Management
    
    private func showSetupWindow() {
        DispatchQueue.main.async {
            self.setupWindow = SetupWindowController()
            self.setupWindow?.showWindow(nil)
            self.setupWindow?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func showInitializationWindow() {
        DispatchQueue.main.async {
            // Start directly in initialization mode (skip extraction)
            SetupProgressManager.shared.setInitializing(task: "Starting AI backend...")
            
            self.setupWindow = SetupWindowController()
            self.setupWindow?.showWindow(nil)
            self.setupWindow?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    
    @objc private func setupWindowClosed() {
        DispatchQueue.main.async {
            self.setupWindow?.closeWindow()
            self.setupWindow = nil
            
            // Mark as launched
            UserDefaults.standard.set(true, forKey: "HasLaunchedBefore")
        }
    }
    
    
    @objc private func retrySetup() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.performBackendSetup()
        }
    }
    
    private func performBackendSetup() {
        // Setup backend from bundle if needed
        if SimpleBackendSetup.shared.isBackendSetupRequired() {
            let success = SimpleBackendSetup.shared.setupBackendFromBundle()
            if success {
                print("✅ Backend setup completed, starting server...")
                // Start the Python script after successful setup
                PythonScriptRunner.shared.runPythonScript()
            } else {
                print("❌ Backend setup failed")
            }
        } else {
            print("✅ Backend already setup, starting server...")
            // Start the Python script
            PythonScriptRunner.shared.runPythonScript()
        }
    }
    
    
    
    private func setupHotkey() {
        let userSettings = UserSettings.shared
        updateHotkey(modifiers: userSettings.customHotkeyModifiers, keyCode: userSettings.customHotkeyKeyCode)
        
        // Listen for hotkey changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyDidChange),
            name: NSNotification.Name("HotkeyDidChange"),
            object: nil
        )
    }
    
    @objc private func hotkeyDidChange(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let modifiers = userInfo["modifiers"] as? NSEvent.ModifierFlags,
           let keyCode = userInfo["keyCode"] as? UInt16 {
            updateHotkey(modifiers: modifiers, keyCode: keyCode)
        }
    }
    
    private func updateHotkey(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        // Remove existing hotkey
        hotkey = nil
        
        // Create new hotkey with updated settings
        guard let key = Key(carbonKeyCode: UInt32(keyCode)) else {
            print("❌ Invalid key code: \(keyCode)")
            return
        }
        
        var hotKeyModifiers: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { hotKeyModifiers.insert(.command) }
        if modifiers.contains(.option) { hotKeyModifiers.insert(.option) }
        if modifiers.contains(.control) { hotKeyModifiers.insert(.control) }
        if modifiers.contains(.shift) { hotKeyModifiers.insert(.shift) }
        
        hotkey = HotKey(key: key, modifiers: hotKeyModifiers)
        hotkey?.keyDownHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.showContentPanel()
            }
        }
        
        print("✅ Hotkey updated to: \(UserSettings.shared.customHotkeyDisplay)")
    }
    
    
    func showContentPanel() {
        
        self.closeReviewWindow()
        
        // Check if we already have an active content window to prevent multiple instances
        if let existingWindow = contentWindow, existingWindow.isVisible {
            print("🔍 ContentPanel already active - bringing to front and focusing")
            existingWindow.makeKeyAndOrderFront(nil)
            if let contentPanel = existingWindow as? ContentPanel {
                contentPanel.focusTextField()
            }
            uiStateManager.forceUIActive()
            return
        }
        
        // Check if Dynamic Island is active and handle it properly
        if DynamicIslandPlacementManager.shared.isDynamicModeEnabled {
            print("🏝️ Dynamic Island mode active - handling window transition")
            // Use the dedicated method to handle hotkey during Dynamic Island mode
            DynamicIslandPlacementManager.shared.handleHotkeyWhileActive()
            // Re-enable focus on the existing window
            if let existingWindow = contentWindow, existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
                if let contentPanel = existingWindow as? ContentPanel {
                    contentPanel.focusTextField()
                }
            }
            uiStateManager.forceUIActive()
            return
        }
        
        let contentPanel = ContentPanel()
        
        contentWindow = contentPanel
        
        contentWindow?.makeKeyAndOrderFront(nil)
        
        contentPanel.makeKey()
        contentPanel.focusTextField()
        
        // UI becomes active when hotkey opens ContentView
        print("🟢🟢🟢 HOTKEY PRESSED - UI ACTIVE 🟢🟢🟢")
        uiStateManager.forceUIActive()
    }
    
    private func closeReviewWindow() {
        if let window = contentWindow {
            window.close()
            contentWindow = nil
        }
    }
    
}


class PythonScriptRunner {
    
    static let shared = PythonScriptRunner()
    private var task: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    
    // MARK: - Python Executable Discovery
    
    private func findPythonExecutable(in backendPath: String) -> String? {
        let fileManager = FileManager.default
        let binPath = backendPath + "/ruma-python/bin"
        
        // List of possible Python executable names to try
        let pythonNames = ["python3", "python", "python3.11"]
        
        print("🔍 Searching for Python executable in: \(binPath)")
        
        for pythonName in pythonNames {
            let pythonPath = binPath + "/" + pythonName
            if fileManager.fileExists(atPath: pythonPath) {
                // Check if it's executable
                if fileManager.isExecutableFile(atPath: pythonPath) {
                    print("✅ Found executable Python: \(pythonName)")
                    return pythonPath
                } else {
                    print("⚠️ Found Python file but not executable: \(pythonName)")
                }
            }
        }
        
        // If no standard names found, list all files in bin directory
        if fileManager.fileExists(atPath: binPath) {
            do {
                let binContents = try fileManager.contentsOfDirectory(atPath: binPath)
                print("📁 Available files in bin directory: \(binContents)")
                
                // Look for any file starting with "python"
                for file in binContents {
                    if file.lowercased().starts(with: "python") {
                        let fullPath = binPath + "/" + file
                        if fileManager.isExecutableFile(atPath: fullPath) {
                            print("✅ Found alternative Python executable: \(file)")
                            return fullPath
                        }
                    }
                }
            } catch {
                print("❌ Error reading bin directory: \(error)")
            }
        }
        
        print("❌ No Python executable found in backend")
        return nil
    }
    
    func runPythonScript() {
        // Stop any existing task first
        stopPythonScript()
        
        // Update progress: Starting initialization
        DispatchQueue.main.async {
            SetupProgressManager.shared.setInitializing(task: "Preparing AI backend...")
        }
        
        // Get backend path from SimpleBackendSetup
        guard let backendPath = SimpleBackendSetup.shared.getBackendPath() else {
            print("❌ Backend not found in Application Support directory")
            print("ℹ️ Make sure backend.zip was extracted properly")
            DispatchQueue.main.async {
                SetupProgressManager.shared.setError("Backend not found in Application Support directory")
            }
            return
        }
        
        // Update progress: Found backend
        DispatchQueue.main.async {
            SetupProgressManager.shared.setInitializing(task: "Locating Python environment...")
        }
        
        // Find available Python executable
        let pythonPath = findPythonExecutable(in: backendPath)
        let scriptPath = backendPath + "/crash_guardian.py"
        
        // Verify files exist
        let fileManager = FileManager.default
        guard let validPythonPath = pythonPath else {
            print("❌ No Python executable found in backend directory")
            print("ℹ️ Checked for python3, python, and python3.x variants")
            DispatchQueue.main.async {
                SetupProgressManager.shared.setError("Python executable not found")
            }
            return
        }
        
        print("✅ Using Python executable: \(validPythonPath)")
        
        guard fileManager.fileExists(atPath: scriptPath) else {
            print("❌ Python script not found at: \(scriptPath)")
            print("ℹ️ Expected path: \(scriptPath)")
            DispatchQueue.main.async {
                SetupProgressManager.shared.setError("Backend script not found")
            }
            return
        }

        // Update progress: Starting backend
        DispatchQueue.main.async {
            SetupProgressManager.shared.setInitializing(task: "Starting AI backend server...")
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: validPythonPath)
        task.arguments = [
            "crash_guardian.py",
            "--script", "unified_app.py", 
            "--max-restarts", "10",
            "--restart-delay", "3"
        ]
        
        // Set up working directory to backend path
        task.currentDirectoryURL = URL(fileURLWithPath: backendPath)
        
        // Set up environment variables
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = backendPath
        environment["PYTHONUNBUFFERED"] = "1"
        // Add the Python bin directory to PATH
        let pythonBinPath = backendPath + "/ruma-python/bin"
        if let currentPath = environment["PATH"] {
            environment["PATH"] = "\(pythonBinPath):\(currentPath)"
        } else {
            environment["PATH"] = pythonBinPath
        }
        task.environment = environment
        
        // Create separate pipes for output and error
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        task.standardInput = nil
        
        // Store pipes for cleanup
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        
        // Set up background monitoring without blocking the main thread
        self.setupBackgroundMonitoring(outputPipe: outputPipe, errorPipe: errorPipe)
        
        // Set termination handler
        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                print("🔄 Python backend process terminated with status: \(process.terminationStatus)")
                self?.cleanup()
            }
        }
        
        self.task = task
        
        do {
            print("🚀 Starting Python backend with:")
            print("   Executable: \(validPythonPath)")
            print("   Working directory: \(backendPath)")
            print("   Arguments: \(task.arguments ?? [])")
            print("   Python PATH: \(pythonBinPath)")
            
            try task.run()
            print("✅ Ruma Backend Server started successfully")
            print("📍 Backend location: \(backendPath)")
            print("🆔 Process ID: \(task.processIdentifier)")
        } catch {
            print("❌ Failed to run Python backend server: \(error)")
            print("   Error details: \(error.localizedDescription)")
            
            // Additional debugging
            let fileManager = FileManager.default
            print("🔍 Debug info:")
            print("   Python executable exists: \(fileManager.fileExists(atPath: validPythonPath))")
            print("   Script exists: \(fileManager.fileExists(atPath: scriptPath))")
            print("   Working directory exists: \(fileManager.fileExists(atPath: backendPath))")
            
            DispatchQueue.main.async {
                SetupProgressManager.shared.setError("Failed to start backend: \(error.localizedDescription)")
            }
            cleanup()
        }
    }
    
    private func setupBackgroundMonitoring(outputPipe: Pipe, errorPipe: Pipe) {
        // Monitor output in background
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("🐍 Backend: \(trimmedOutput)")
                    
                    // Check for initialization progress indicators
                    DispatchQueue.main.async {
                        if trimmedOutput.contains("Loading MLX model") {
                            SetupProgressManager.shared.setInitializing(task: "Loading AI model...")
                        } else if trimmedOutput.contains("Model loaded successfully") {
                            SetupProgressManager.shared.setInitializing(task: "Initializing memory systems...")
                        } else if trimmedOutput.contains("Smart Memory System initialized") {
                            SetupProgressManager.shared.setInitializing(task: "Starting server...")
                        } else if trimmedOutput.contains("Uvicorn running on") {
                            SetupProgressManager.shared.setInitializing(task: "Server started, finalizing setup...")
                            
                            // Wait a moment then mark as completed
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                SetupProgressManager.shared.setCompleted()
                                
                                // Close setup window after completion
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    NotificationCenter.default.post(name: NSNotification.Name("CloseSetupWindow"), object: nil)
                                }
                            }
                        } else if trimmedOutput.contains("Application startup complete") || 
                                  trimmedOutput.contains("Server starting") {
                            // Alternative completion indicators
                            SetupProgressManager.shared.setCompleted()
                            
                            // Close setup window immediately
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                NotificationCenter.default.post(name: NSNotification.Name("CloseSetupWindow"), object: nil)
                            }
                        }
                    }
                }
            }
        }
        
        // Monitor errors in background
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let error = String(data: data, encoding: .utf8) {
                    let trimmedError = error.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("⚠️ Backend Error: \(trimmedError)")
                    
                    // Check for critical errors
                    if trimmedError.contains("ModuleNotFoundError") || 
                       trimmedError.contains("ImportError") ||
                       trimmedError.contains("FileNotFoundError") {
                        DispatchQueue.main.async {
                            SetupProgressManager.shared.setError("Backend initialization failed: \(trimmedError)")
                        }
                    }
                    
                    // Check for database errors
                    if trimmedError.contains("unable to open database") ||
                       trimmedError.contains("database") ||
                       trimmedError.contains("sqlite") {
                        print("🗃️ Database Error Detected: \(trimmedError)")
                    }
                    
                    // Check for JSON/API errors
                    if trimmedError.contains("JSON") ||
                       trimmedError.contains("Unexpected character") ||
                       trimmedError.contains("Invalid argument") {
                        print("🔗 API/JSON Error Detected: \(trimmedError)")
                    }
                }
            }
        }
    }
    
    private func ensurePythonBackendExtracted(resourcePath: String) -> Bool {
        let fileManager = FileManager.default
        let pythonBackendPath = resourcePath + "/ruma-python"
        let zipPath = resourcePath + "/ruma-python.zip"
        
        // If ruma-python directory already exists, no need to extract
        if fileManager.fileExists(atPath: pythonBackendPath) {
            print("✅ Python backend already extracted")
            return true
        }
        
        // Check if zip file exists
        guard fileManager.fileExists(atPath: zipPath) else {
            print("❌ ruma-python.zip not found in app bundle")
            return false
        }
        
        print("🔄 First-time setup: Extracting Python backend...")
        
        do {
            // Extract the zip file
            let zipURL = URL(fileURLWithPath: zipPath)
            let destinationURL = URL(fileURLWithPath: resourcePath)
            
            try self.extractZip(at: zipURL, to: destinationURL)
            
            // Verify extraction was successful
            if fileManager.fileExists(atPath: pythonBackendPath) {
                print("✅ Python backend extracted successfully")
                
                // Set executable permissions on Python binaries
                self.setExecutablePermissions(pythonBackendPath: pythonBackendPath)
                
                return true
            } else {
                print("❌ Python backend extraction failed - directory not found after extraction")
                return false
            }
            
        } catch {
            print("❌ Failed to extract Python backend: \(error)")
            return false
        }
    }
    
    private func extractZip(at sourceURL: URL, to destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        
        coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &error) { (readingURL) in
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-q", readingURL.path, "-d", destinationURL.path]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus != 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("❌ Unzip failed with status \(process.terminationStatus): \(output)")
                }
                
            } catch {
                print("❌ Failed to run unzip process: \(error)")
            }
        }
        
        if let error = error {
            throw error
        }
    }
    
    private func setExecutablePermissions(pythonBackendPath: String) {
        let binPath = pythonBackendPath + "/bin"
        let fileManager = FileManager.default
        
        do {
            let binContents = try fileManager.contentsOfDirectory(atPath: binPath)
            
            for file in binContents {
                let fullPath = binPath + "/" + file
                
                // Set executable permission (755)
                let attributes = [FileAttributeKey.posixPermissions: 0o755]
                try fileManager.setAttributes(attributes, ofItemAtPath: fullPath)
            }
            
            print("✅ Set executable permissions for Python binaries")
            
        } catch {
            print("⚠️ Warning: Could not set executable permissions: \(error)")
        }
    }
    
    private func cleanup() {
        // Clean up pipe handlers
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        
        // Close pipes
        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()
        
        outputPipe = nil
        errorPipe = nil
        task = nil
    }
    
    func stopPythonScript() {
        guard let task = task else {
            print("No Python backend task to terminate.")
            return
        }
        
        if task.isRunning {
            print("🛑 Terminating Python backend process...")
            task.terminate()
            
            // Wait for termination with timeout
            DispatchQueue.global().async {
                let startTime = Date()
                while task.isRunning && Date().timeIntervalSince(startTime) < 5.0 {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                
                if task.isRunning {
                    print("⚠️ Force killing Python backend process...")
                    task.interrupt()
                }
                
                DispatchQueue.main.async {
                    self.cleanup()
                }
            }
        } else {
            print("Python backend task is not running.")
            cleanup()
        }
    }
    

    func runPostInstallScripts(){
        
        let resourcePath = Bundle.main.resourcePath
        
        print("Resource Path: \(resourcePath!)")
        
        
        let allArgs: [String] = [
            
            resourcePath! + "/suripython/app-suriai-app/postinstall.py",
            resourcePath! + "/suripython/framework-mlx-env/postinstall.py",
            resourcePath! + "/suripython/cpython@3.11/postinstall.py"
                            
        ]
        for arg in allArgs{
            
            let task = Process()
            let pipe = Pipe()
            
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.arguments = [arg]
            
            task.launchPath = resourcePath! + "/suripython/cpython@3.11/bin/python3"
            task.standardInput = nil
            task.launch()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: data, encoding: .utf8) ?? "No output"
            print(output,"Done Execution")
            
        }
       
        
    }




    
}
