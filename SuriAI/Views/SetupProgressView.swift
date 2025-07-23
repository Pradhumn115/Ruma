//
//  SetupProgressView.swift
//  SuriAI - Backend Setup Progress
//
//  Created by Claude on 08/07/25.
//

import SwiftUI

enum SetupStage: Equatable {
    case extracting
    case initializing
    case completed
    case error(String)
}

struct SetupProgressView: View {
    @StateObject private var setupManager = SetupProgressManager.shared
    @State private var shouldClose = false
    @State private var rotationAngle: Double = 0
    @State private var pulseScale: Double = 1.0
    @State private var bounceScale: Double = 1.0
    
    var body: some View {
        VStack(spacing: 30) {
            // App Icon/Logo
            if #available(macOS 15.0, *) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                    .symbolEffect(.pulse, options: .repeating)
            } else {
                // Fallback for macOS 14: Custom pulse animation
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                    .scaleEffect(pulseScale)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            pulseScale = 1.2
                        }
                    }
            }
            
            VStack(spacing: 16) {
                Text("Ruma AI")
                    .font(.largeTitle.bold())
                    .foregroundColor(.primary)
                
                Text("Setting up your AI assistant...")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            // Progress Section
            VStack(spacing: 20) {
                switch setupManager.currentStage {
                case .extracting:
                    extractionView
                case .initializing:
                    initializationView
                case .completed:
                    completedView
                case .error(let message):
                    errorView(message: message)
                }
            }
        }
        .padding(40)
        .frame(width: 500, height: 400)
        .background(.ultraThinMaterial)
        .onChange(of: setupManager.currentStage) { _, newStage in
            if case .completed = newStage {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    shouldClose = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseSetupWindow"))) { _ in
            shouldClose = true
        }
    }
    
    var extractionView: some View {
        VStack(spacing: 16) {
            ProgressView(value: setupManager.extractionProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .frame(height: 8)
            
            HStack {
                Image(systemName: "archivebox")
                    .foregroundColor(.blue)
                
                Text("Extracting backend...")
                    .font(.subheadline)
                
                Spacer()
                
                Text("\(Int(setupManager.extractionProgress * 100))%")
                    .font(.subheadline.bold())
                    .foregroundColor(.blue)
            }
            
            if !setupManager.currentTask.isEmpty {
                Text(setupManager.currentTask)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    var initializationView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle(tint: .green))
            
            HStack {
                if #available(macOS 15.0, *) {
                    Image(systemName: "gearshape.2")
                        .foregroundColor(.green)
                        .symbolEffect(.rotate, options: .repeating)
                } else {
                    // Fallback for macOS 14: Custom rotation animation
                    Image(systemName: "gearshape.2")
                        .foregroundColor(.green)
                        .rotationEffect(.degrees(rotationAngle))
                        .onAppear {
                            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                                rotationAngle = 360
                            }
                        }
                }
                
                Text("Initializing AI backend...")
                    .font(.subheadline)
            }
            
            if !setupManager.currentTask.isEmpty {
                Text(setupManager.currentTask)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    var completedView: some View {
        VStack(spacing: 16) {
            if #available(macOS 15.0, *) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                    .symbolEffect(.bounce, options: .nonRepeating)
            } else {
                // Fallback for macOS 14: Custom bounce animation
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                    .scaleEffect(bounceScale)
                    .onAppear {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            bounceScale = 1.2
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                bounceScale = 1.0
                            }
                        }
                    }
            }
            
            VStack(spacing: 8) {
                Text("Setup Complete!")
                    .font(.headline.bold())
                    .foregroundColor(.green)
                
                Text("Ruma AI is ready to use")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            VStack(spacing: 12) {
                Text("Setup Failed")
                    .font(.headline.bold())
                    .foregroundColor(.red)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Retry Setup") {
                    setupManager.retrySetup()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}

// MARK: - Setup Progress Manager

@MainActor
class SetupProgressManager: ObservableObject {
    static let shared = SetupProgressManager()
    
    @Published var currentStage: SetupStage = .extracting
    @Published var extractionProgress: Double = 0.0
    @Published var currentTask: String = ""
    
    private var serverCheckTimer: Timer?
    
    private init() {}
    
    func updateExtractionProgress(_ progress: Double, task: String = "") {
        extractionProgress = progress
        currentTask = task
        
        if progress >= 1.0 {
            currentStage = .initializing
        }
    }
    
    func setInitializing(task: String = "Starting AI backend...") {
        currentStage = .initializing
        currentTask = task
        
        // Start checking for server readiness after initialization begins
        startServerReadinessCheck()
    }
    
    func setCompleted() {
        currentStage = .completed
        currentTask = ""
        stopServerReadinessCheck()
    }
    
    func setError(_ message: String) {
        currentStage = .error(message)
        currentTask = ""
        stopServerReadinessCheck()
    }
    
    func retrySetup() {
        currentStage = .extracting
        extractionProgress = 0.0
        currentTask = ""
        stopServerReadinessCheck()
        
        // Trigger setup retry
        NotificationCenter.default.post(name: NSNotification.Name("RetryBackendSetup"), object: nil)
    }
    
    private func startServerReadinessCheck() {
        // Stop any existing timer
        stopServerReadinessCheck()
        
        // Start checking server readiness every 2 seconds
        serverCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                await self.checkServerReadiness()
            }
        }
    }
    
    private func stopServerReadinessCheck() {
        serverCheckTimer?.invalidate()
        serverCheckTimer = nil
    }
    
    private func checkServerReadiness() async {
        // Only check if we're still in initializing stage
        guard case .initializing = currentStage else { return }
        
        // Use ServerConfig's existing server discovery logic
        await serverConfig.findWorkingServer()
        
        // Check if ServerConfig found a working server
        if serverConfig.isServerReachable {
            // Server is ready!
            await MainActor.run {
                print("✅ Server is ready at \(serverConfig.currentServerURL) - setup complete!")
                self.setCompleted()
                
                // Close setup window
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NotificationCenter.default.post(name: NSNotification.Name("CloseSetupWindow"), object: nil)
                }
            }
        }
    }
}

// MARK: - Setup Window Controller

class SetupWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Ruma AI Setup"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        
        // Disable close button during setup
        window.standardWindowButton(.closeButton)?.isEnabled = false
        
        self.init(window: window)
        
        let contentView = SetupProgressView()
        window.contentView = NSHostingView(rootView: contentView)
        
        // Force window to front and activate app
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func enableCloseButton() {
        window?.standardWindowButton(.closeButton)?.isEnabled = true
    }
    
    func closeWindow() {
        window?.close()
    }
}

// MARK: - Preview
#Preview {
    SetupProgressView()
        .frame(width: 500, height: 400)
}