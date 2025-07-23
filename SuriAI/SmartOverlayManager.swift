//
//  SmartOverlayManager.swift
//  SuriAI - Smart Overlay Positioning System
//
//  Created by Claude on 02/07/25.
//

import SwiftUI
import Foundation
import AppKit

@MainActor
class SmartOverlayManager: ObservableObject {
    static let shared = SmartOverlayManager()
    
    @Published var isOverlayVisible = false
    @Published var overlayPosition = CGPoint.zero
    @Published var currentScreen: NSScreen?
    
    private var overlayWindow: NSWindow?
    private let overlaySize = CGSize(width: 600, height: 400)
    private let screenPadding: CGFloat = 20
    private let cursorOffset: CGFloat = 30
    
    private init() {}
    
    // MARK: - Public Methods
    
    func showOverlay() {
        calculateOptimalPosition()
        createOrUpdateOverlayWindow()
        isOverlayVisible = true
    }
    
    func hideOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        isOverlayVisible = false
    }
    
    func toggleOverlay() {
        if isOverlayVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }
    
    // MARK: - Smart Positioning Logic
    
    private func calculateOptimalPosition() {
        // Get current mouse position in global coordinates
        let mouseLocation = NSEvent.mouseLocation
        
        // Find the screen containing the mouse cursor
        currentScreen = findScreenContainingPoint(mouseLocation)
        guard let screen = currentScreen else {
            print("⚠️ No screen found for mouse location")
            return
        }
        
        print("🖱️ Mouse at: \(mouseLocation), Screen: \(screen.frame)")
        
        // Calculate optimal position using intelligent placement
        overlayPosition = calculateIntelligentPosition(
            mouseLocation: mouseLocation,
            screen: screen
        )
        
        print("✅ Calculated overlay position: \(overlayPosition)")
    }
    
    private func findScreenContainingPoint(_ point: CGPoint) -> NSScreen? {
        return NSScreen.screens.first { screen in
            NSPointInRect(point, screen.frame)
        } ?? NSScreen.main
    }
    
    private func calculateIntelligentPosition(mouseLocation: CGPoint, screen: NSScreen) -> CGPoint {
        let screenFrame = screen.frame
        let safeArea = NSRect(
            x: screenFrame.minX + screenPadding,
            y: screenFrame.minY + screenPadding,
            width: screenFrame.width - (screenPadding * 2),
            height: screenFrame.height - (screenPadding * 2)
        )
        
        var targetX: CGFloat
        var targetY: CGFloat
        
        // Horizontal positioning logic
        let preferredX = mouseLocation.x + cursorOffset
        let rightAlignedX = mouseLocation.x - overlaySize.width - cursorOffset
        
        if preferredX + overlaySize.width <= safeArea.maxX {
            // Enough space to the right of cursor
            targetX = preferredX
        } else if rightAlignedX >= safeArea.minX {
            // Not enough space right, try left
            targetX = rightAlignedX
        } else {
            // Center horizontally if neither side works
            targetX = safeArea.midX - (overlaySize.width / 2)
        }
        
        // Vertical positioning logic
        let preferredY = mouseLocation.y - cursorOffset - overlaySize.height
        let belowCursorY = mouseLocation.y + cursorOffset
        
        if preferredY >= safeArea.minY {
            // Enough space above cursor (preferred)
            targetY = preferredY
        } else if belowCursorY + overlaySize.height <= safeArea.maxY {
            // Not enough space above, try below
            targetY = belowCursorY
        } else {
            // Center vertically if neither works
            targetY = safeArea.midY - (overlaySize.height / 2)
        }
        
        // Ensure the overlay stays within safe area bounds
        targetX = max(safeArea.minX, min(targetX, safeArea.maxX - overlaySize.width))
        targetY = max(safeArea.minY, min(targetY, safeArea.maxY - overlaySize.height))
        
        return CGPoint(x: targetX, y: targetY)
    }
    
    // MARK: - Overlay Window Management
    
    private func createOrUpdateOverlayWindow() {
        if overlayWindow == nil {
            overlayWindow = createOverlayWindow()
        }
        
        guard let window = overlayWindow else { return }
        
        // Set the calculated position and show
        window.setFrameOrigin(overlayPosition)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Add subtle animation
        animateWindowAppearance(window)
    }
    
    private func createOverlayWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: overlayPosition, size: overlaySize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = true
        
        // Create the SwiftUI content view
        let contentView = SmartOverlayContentView()
            .environmentObject(self)
        
        window.contentView = NSHostingView(rootView: contentView)
        
        return window
    }
    
    private func animateWindowAppearance(_ window: NSWindow) {
        // Start with scaled down and transparent
        window.alphaValue = 0.0
        let originalFrame = window.frame
        let scaledFrame = NSRect(
            x: originalFrame.midX - (originalFrame.width * 0.1) / 2,
            y: originalFrame.midY - (originalFrame.height * 0.1) / 2,
            width: originalFrame.width * 0.1,
            height: originalFrame.height * 0.1
        )
        window.setFrame(scaledFrame, display: false)
        
        // Animate to full size and opacity
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            
            window.animator().alphaValue = 1.0
            window.animator().setFrame(originalFrame, display: true)
        }
    }
    
    // MARK: - Multi-Screen Support
    
    func handleScreenConfigurationChange() {
        guard isOverlayVisible else { return }
        
        // Recalculate position for current screen configuration
        calculateOptimalPosition()
        
        // Update window position if needed
        overlayWindow?.setFrameOrigin(overlayPosition)
    }
    
    // MARK: - Utility Methods
    
    func getScreenInfo() -> String {
        guard let screen = currentScreen else { return "No screen detected" }
        
        let screenIndex = NSScreen.screens.firstIndex(of: screen) ?? 0
        return """
        Screen \(screenIndex + 1) of \(NSScreen.screens.count)
        Resolution: \(Int(screen.frame.width))x\(Int(screen.frame.height))
        Position: \(Int(screen.frame.origin.x)), \(Int(screen.frame.origin.y))
        """
    }
}

// MARK: - Overlay Content View

struct SmartOverlayContentView: View {
    @EnvironmentObject var overlayManager: SmartOverlayManager
    @StateObject private var screenCaptureManager = ScreenCaptureManager()
    @State private var userInput = ""
    @State private var isAnalyzing = false
    @State private var analysisResult = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Main content area
            if analysisResult.isEmpty {
                inputView
            } else {
                resultView
            }
            
            // Footer with actions
            footerView
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Material.ultraThick)
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("SuriAI Screen Analysis")
                    .font(.headline)
                
                Text(overlayManager.getScreenInfo())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                overlayManager.hideOverlay()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.black.opacity(0.02))
    }
    
    private var inputView: some View {
        VStack(spacing: 16) {
            Text("What would you like to know about your screen?")
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()
            
            TextField("Ask about what you see on screen...", text: $userInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            
            Button {
                analyzeScreen()
            } label: {
                HStack {
                    if isAnalyzing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "eye.fill")
                    }
                    Text(isAnalyzing ? "Analyzing..." : "Analyze Screen")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(userInput.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(userInput.isEmpty || isAnalyzing)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var resultView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Analysis Result")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("New Analysis") {
                        analysisResult = ""
                        userInput = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Text(analysisResult)
                    .textSelection(.enabled)
                    .padding()
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
        }
    }
    
    private var footerView: some View {
        HStack {
            Text("Screen reasoning powered by Apple Vision + MLX")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Settings") {
                // Open settings
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding()
        .background(Color.black.opacity(0.02))
    }
    
    private func analyzeScreen() {
        guard !userInput.isEmpty else { return }
        
        isAnalyzing = true
        
        Task {
            let result = await screenCaptureManager.analyzeScreenContent(
                userQuestion: userInput,
                userID: "overlay_user",
                chatID: "overlay_session"
            )
            
            await MainActor.run {
                analysisResult = result
                isAnalyzing = false
            }
        }
    }
}

#Preview {
    SmartOverlayContentView()
        .environmentObject(SmartOverlayManager.shared)
        .frame(width: 600, height: 400)
}