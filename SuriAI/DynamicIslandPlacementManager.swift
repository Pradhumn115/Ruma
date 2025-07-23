//
//  DynamicIslandPlacementManager.swift
//  SuriAI - Dynamic Island Style Window Placement
//
//  Created by Pradhumn Gupta on 25/05/25.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Dynamic Placement States
enum DynamicPlacementState {
    case compact       // Small compact form like Dynamic Island
    case expanded      // Regular size
    case interactive   // Full size with interaction capabilities
    case magnetic      // Magnetically attached to screen edges
}

enum MagneticPosition {
    case topCenter     // Top center (like Dynamic Island)
    case topLeft       // Top left corner
    case topRight      // Top right corner
    case leftEdge      // Left edge center
    case rightEdge     // Right edge center
    case bottomCenter  // Bottom center
    case floating      // Free floating position
}

// MARK: - Dynamic Island Style Manager
@MainActor
class DynamicIslandPlacementManager: ObservableObject {
    static let shared = DynamicIslandPlacementManager()
    
    // Published properties for SwiftUI binding
    @Published var currentState: DynamicPlacementState = .expanded
    @Published var magneticPosition: MagneticPosition = .floating
    @Published var isDynamicModeEnabled: Bool = false
    @Published var isAnimating: Bool = false
    @Published var showMagneticZones: Bool = false
    @Published var nearestMagneticZone: MagneticPosition? = nil
    @Published var isDragging: Bool = false
    
    // Window management
    private var currentWindow: NSWindow?
    private var originalFrame: CGRect = .zero
    private var dragOffset: CGSize = .zero
    
    // Magnetic attraction settings
    private let magneticThreshold: CGFloat = 60.0  // Distance for magnetic attraction (reduced)
    private let snapThreshold: CGFloat = 80.0      // Distance for auto-snap during drag (reduced)
    private let animationDuration: Double = 0.3
    private let snapAnimationDuration: Double = 0.5
    
    // Screen dimensions cache
    private var screenBounds: CGRect {
        NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Dynamic Mode Control
    func toggleDynamicMode() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isDynamicModeEnabled.toggle()
            
            if isDynamicModeEnabled {
                enterDynamicMode()
            } else {
                exitDynamicMode()
            }
        }
    }
    
    private func enterDynamicMode() {
        print("🌟 Entering Dynamic Island mode")
        currentState = .compact
        magneticPosition = .topCenter
        moveToTopMiddle(animated: true)
        
        // Notify UI State Manager that Dynamic Island mode is active
        Task { @MainActor in
            UIStateManager.shared.dynamicIslandDidAppear()
        }
    }
    
    // MARK: - Direct Top Middle Positioning
    func moveToTopMiddle(animated: Bool = true) {
        guard let window = currentWindow else { return }
        
        let screen = screenBounds
        let (width, height) = sizeForMagneticPosition()
        
        // Calculate top middle position
        let x = screen.midX - width / 2
        let y = screen.maxY - height - 10  // 10pt from top
        let targetFrame = CGRect(x: x, y: y, width: width, height: height)
        
        if animated {
            isAnimating = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            } completionHandler: {
                Task { @MainActor in
                    self.isAnimating = false
                }
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
        
        // Update the original frame to the new position for free dragging
        originalFrame = targetFrame
        magneticPosition = .topCenter
    }
    
    private func exitDynamicMode() {
        print("🌟 Exiting Dynamic Island mode")
        currentState = .expanded
        magneticPosition = .floating
        restoreOriginalPosition(animated: true)
        
        // Notify UI State Manager that Dynamic Island mode is inactive
        Task { @MainActor in
            UIStateManager.shared.dynamicIslandDidDisappear()
        }
    }
    
    // MARK: - Window Registration
    func registerWindow(_ window: NSWindow) {
        currentWindow = window
        originalFrame = window.frame
        print("🪟 Window registered for Dynamic Island placement")
    }
    
    // MARK: - State Management
    func setState(_ newState: DynamicPlacementState, animated: Bool = true) {
        guard isDynamicModeEnabled else { return }
        
        withAnimation(animated ? .spring(response: 0.6, dampingFraction: 0.8) : .none) {
            currentState = newState
            updateWindowForState(animated: animated)
        }
    }
    
    // MARK: - Hotkey Integration
    func handleHotkeyWhileActive() {
        print("🏝️ Hotkey pressed while Dynamic Island active - handling gracefully")
        
        guard isDynamicModeEnabled, let window = currentWindow else { return }
        
        // Temporarily disable Dynamic Island mode to prevent conflicts
        isDynamicModeEnabled = false
        currentState = .expanded
        
        // Restore normal position smoothly
        let normalFrame = CGRect(
            x: window.screen?.visibleFrame.midX ?? 0 - 300,
            y: window.screen?.visibleFrame.midY ?? 0,
            width: 600,
            height: 500
        )
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(normalFrame, display: true)
        } completionHandler: {
            print("🏝️ Dynamic Island gracefully transitioned to normal mode")
        }
    }
    
    private func updateWindowForState(animated: Bool) {
        guard let window = currentWindow else { return }
        
        let targetFrame = frameForCurrentState()
        
        if animated {
            isAnimating = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            } completionHandler: {
                Task { @MainActor in
                    self.isAnimating = false
                }
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }
    
    // MARK: - Frame Calculations
    private func frameForCurrentState() -> CGRect {
        let screen = screenBounds
        
        switch currentState {
        case .compact:
            return compactFrame(in: screen)
        case .expanded:
            return expandedFrame(in: screen)
        case .interactive:
            return interactiveFrame(in: screen)
        case .magnetic:
            return magneticFrame(in: screen)
        }
    }
    
    private func compactFrame(in screen: CGRect) -> CGRect {
        // Dynamic Island style with shape morphing based on position
        let (width, height) = sizeForMagneticPosition()
        
        return frameForMagneticPosition(width: width, height: height, in: screen)
    }
    
    private func sizeForMagneticPosition() -> (CGFloat, CGFloat) {
        switch magneticPosition {
        case .topCenter:
            // Wide strip like Dynamic Island with text input
            return (600, 44)
        case .topLeft, .topRight:
            // Rounded square for corners
            return (120, 120)
        case .leftEdge, .rightEdge:
            // Vertical strip for edges
            return (45, 200)
        case .bottomCenter:
            // Wide strip for bottom with text input
            return (580, 44)
        case .floating:
            // Regular size when floating with text input
            return (500, 44)
        }
    }
    
    private func expandedFrame(in screen: CGRect) -> CGRect {
        // Regular window size
        let width: CGFloat = 600
        let height: CGFloat = 500
        
        return frameForMagneticPosition(width: width, height: height, in: screen)
    }
    
    private func interactiveFrame(in screen: CGRect) -> CGRect {
        // Full interactive size
        let width: CGFloat = 800
        let height: CGFloat = 600
        
        return frameForMagneticPosition(width: width, height: height, in: screen)
    }
    
    private func magneticFrame(in screen: CGRect) -> CGRect {
        // Adaptive size based on content
        let width: CGFloat = 400
        let height: CGFloat = 300
        
        return frameForMagneticPosition(width: width, height: height, in: screen)
    }
    
    private func frameForMagneticPosition(width: CGFloat, height: CGFloat, in screen: CGRect) -> CGRect {
        let x: CGFloat
        let y: CGFloat
        
        switch magneticPosition {
        case .topCenter:
            x = screen.midX - width / 2
            y = screen.maxY - height - 10  // 10pt from top
            
        case .topLeft:
            x = screen.minX + 20
            y = screen.maxY - height - 10
            
        case .topRight:
            x = screen.maxX - width - 20
            y = screen.maxY - height - 10
            
        case .leftEdge:
            x = screen.minX + 10
            y = screen.midY - height / 2
            
        case .rightEdge:
            x = screen.maxX - width - 10
            y = screen.midY - height / 2
            
        case .bottomCenter:
            x = screen.midX - width / 2
            y = screen.minY + 10
            
        case .floating:
            return originalFrame.isEmpty ? 
                CGRect(x: screen.midX - width / 2, y: screen.midY - height / 2, width: width, height: height) : 
                originalFrame
        }
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // MARK: - Magnetic Positioning
    func moveToMagneticPosition(animated: Bool = true) {
        updateWindowForState(animated: animated)
    }
    
    func setMagneticPosition(_ position: MagneticPosition, animated: Bool = true) {
        withAnimation(animated ? .spring(response: 0.6, dampingFraction: 0.8) : .none) {
            magneticPosition = position
            if isDynamicModeEnabled {
                moveToMagneticPosition(animated: animated)
            }
        }
    }
    
    // MARK: - Drag and Drop Support
    func startDragging(at location: CGPoint) {
        guard isDynamicModeEnabled else { return }
        isDragging = true
        dragOffset = .zero
        showMagneticZones = true  // Show magnetic zones during drag
        
        // Store the current frame as the starting point for this drag
        if let window = currentWindow {
            originalFrame = window.frame
        }
        
        print("🎯 Started dragging - magnetic zones visible")
    }
    
    func updateDrag(translation: CGSize) {
        guard isDynamicModeEnabled && isDragging else { return }
        
        dragOffset = translation
        
        // Update window position smoothly during drag - prioritize smooth movement
        if let window = currentWindow {
            // Calculate new position based on original frame + translation
            var newFrame = originalFrame
            newFrame.origin.x += translation.width
            newFrame.origin.y -= translation.height  // Flip Y coordinate for macOS
            
            // Set frame without animation for smooth dragging
            window.setFrame(newFrame, display: true, animate: false)
        }
        
        // Remove magnetic attraction during drag - allow free movement
        // No longer checking magnetic zones or applying magnetic effects
    }
    
    private func distanceToNearestMagneticPosition() -> CGFloat {
        guard let window = currentWindow else { return CGFloat.infinity }
        
        let windowCenter = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let screen = screenBounds
        
        let distances = [
            distanceToPosition(.topCenter, from: windowCenter, in: screen),
            distanceToPosition(.topLeft, from: windowCenter, in: screen),
            distanceToPosition(.topRight, from: windowCenter, in: screen),
            distanceToPosition(.leftEdge, from: windowCenter, in: screen),
            distanceToPosition(.rightEdge, from: windowCenter, in: screen),
            distanceToPosition(.bottomCenter, from: windowCenter, in: screen)
        ]
        
        return distances.min() ?? CGFloat.infinity
    }
    
    private func findNearestMagneticPositionForDrag() -> MagneticPosition {
        guard let window = currentWindow else { return .floating }
        
        let windowCenter = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let screen = screenBounds
        
        // Calculate distances to each magnetic position
        let positions: [(MagneticPosition, CGFloat)] = [
            (.topCenter, distanceToPosition(.topCenter, from: windowCenter, in: screen)),
            (.topLeft, distanceToPosition(.topLeft, from: windowCenter, in: screen)),
            (.topRight, distanceToPosition(.topRight, from: windowCenter, in: screen)),
            (.leftEdge, distanceToPosition(.leftEdge, from: windowCenter, in: screen)),
            (.rightEdge, distanceToPosition(.rightEdge, from: windowCenter, in: screen)),
            (.bottomCenter, distanceToPosition(.bottomCenter, from: windowCenter, in: screen))
        ]
        
        // Find the closest position
        if let closest = positions.min(by: { $0.1 < $1.1 }) {
            return closest.0
        }
        
        return .floating
    }
    
    func endDragging() {
        guard isDynamicModeEnabled && isDragging else { return }
        
        isDragging = false
        showMagneticZones = false  // Hide magnetic zones after drag
        nearestMagneticZone = nil
        
        // No longer snap to magnetic positions - allow free positioning
        // Update the original frame to current position for future drags
        if let window = currentWindow {
            originalFrame = window.frame
        }
        
        dragOffset = .zero
        print("🎯 Ended dragging - free positioning allowed")
    }
    
    private func findNearestMagneticPosition() -> MagneticPosition {
        guard let window = currentWindow else { return .floating }
        
        let windowFrame = window.frame
        let screen = screenBounds
        let windowCenter = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        
        // Calculate distances to each magnetic position
        let positions: [(MagneticPosition, CGFloat)] = [
            (.topCenter, distanceToPosition(.topCenter, from: windowCenter, in: screen)),
            (.topLeft, distanceToPosition(.topLeft, from: windowCenter, in: screen)),
            (.topRight, distanceToPosition(.topRight, from: windowCenter, in: screen)),
            (.leftEdge, distanceToPosition(.leftEdge, from: windowCenter, in: screen)),
            (.rightEdge, distanceToPosition(.rightEdge, from: windowCenter, in: screen)),
            (.bottomCenter, distanceToPosition(.bottomCenter, from: windowCenter, in: screen))
        ]
        
        // Find the closest position within threshold
        if let closest = positions.min(by: { $0.1 < $1.1 }), closest.1 < magneticThreshold {
            return closest.0
        }
        
        return .floating
    }
    
    private func distanceToPosition(_ position: MagneticPosition, from point: CGPoint, in screen: CGRect) -> CGFloat {
        let targetPoint: CGPoint
        
        switch position {
        case .topCenter:
            targetPoint = CGPoint(x: screen.midX, y: screen.maxY - 30)
        case .topLeft:
            targetPoint = CGPoint(x: screen.minX + 100, y: screen.maxY - 30)
        case .topRight:
            targetPoint = CGPoint(x: screen.maxX - 100, y: screen.maxY - 30)
        case .leftEdge:
            targetPoint = CGPoint(x: screen.minX + 30, y: screen.midY)
        case .rightEdge:
            targetPoint = CGPoint(x: screen.maxX - 30, y: screen.midY)
        case .bottomCenter:
            targetPoint = CGPoint(x: screen.midX, y: screen.minY + 30)
        case .floating:
            return CGFloat.infinity
        }
        
        return sqrt(pow(point.x - targetPoint.x, 2) + pow(point.y - targetPoint.y, 2))
    }
    
    // MARK: - Utility Methods
    private func restoreOriginalPosition(animated: Bool) {
        guard let window = currentWindow, !originalFrame.isEmpty else { return }
        
        if animated {
            isAnimating = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(originalFrame, display: true)
            } completionHandler: {
                Task { @MainActor in
                    self.isAnimating = false
                }
            }
        } else {
            window.setFrame(originalFrame, display: true)
        }
    }
    
    private func setupNotificationObservers() {
        // Observe screen changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenDidChange()
        }
    }
    
    private func screenDidChange() {
        // Reposition window when screen configuration changes
        if isDynamicModeEnabled {
            moveToMagneticPosition(animated: true)
        }
    }
    
    // MARK: - Animation Helpers
    func getScaleEffect() -> CGFloat {
        if !isDynamicModeEnabled {
            return 1.0
        }
        
        switch magneticPosition {
        case .topCenter, .bottomCenter:
            // Wider, flatter for strip shapes
            return 0.7
        case .topLeft, .topRight:
            // Smaller, more compact for corners
            return 0.6
        case .leftEdge, .rightEdge:
            // Taller, narrower for vertical strips
            return 0.8
        case .floating:
            return 0.9
        }
    }
    
    // Removed old scaling methods since we now use DynamicIslandCapsule component
    
    func getCornerRadius() -> CGFloat {
        switch magneticPosition {
        case .topCenter, .bottomCenter:
            // High corner radius for strip shapes (like Dynamic Island)
            return currentState == .compact ? 18 : 16
        case .topLeft, .topRight:
            // Medium corner radius for corner positions
            return currentState == .compact ? 25 : 20
        case .leftEdge, .rightEdge:
            // High corner radius for vertical strips
            return currentState == .compact ? 22 : 18
        case .floating:
            // Standard corner radius for floating
            return currentState == .compact ? 16 : 12
        }
    }
    
    func getBackgroundOpacity() -> Double {
        // Always transparent - no background box
        return 0.0
    }
    
    func getBlurEffect() -> NSVisualEffectView.Material {
        switch magneticPosition {
        case .topCenter:
            return .hudWindow  // Dynamic Island style blur
        case .topLeft, .topRight, .bottomCenter:
            return .popover    // Softer blur for other positions
        case .leftEdge, .rightEdge:
            return .sidebar    // Minimal blur for edge strips
        case .floating:
            return .windowBackground  // Standard blur for floating
        }
    }
    
    func getBorderWidth() -> CGFloat {
        return isDynamicModeEnabled ? 0.5 : 0.0
    }
    
    func getBorderColor() -> Color {
        return Color.white.opacity(0.2)
    }
}

// MARK: - SwiftUI Integration
struct DynamicIslandStyle: ViewModifier {
    @ObservedObject var placementManager = DynamicIslandPlacementManager.shared
    let personalityManager: PersonalityManager
    let userInput: Binding<String>
    let isStreaming: Binding<Bool>
    let screenReasoningEnabled: Binding<Bool>
    let currentResponse: Binding<String>
    let showResponse: Binding<Bool>
    let onSendMessage: () -> Void
    let onExitDynamicMode: () -> Void
    let onToggleScreenAnalysis: () -> Void
    let onShowSearch: () -> Void
    
    func body(content: Content) -> some View {
        ZStack {
            if placementManager.isDynamicModeEnabled {
                // Show Dynamic Island capsule UI instead of original content
                DynamicIslandCapsule(
                    personalityManager: personalityManager,
                    userInput: userInput,
                    isStreaming: isStreaming,
                    screenReasoningEnabled: screenReasoningEnabled,
                    currentResponse: currentResponse,
                    showResponse: showResponse,
                    onSendMessage: onSendMessage,
                    onExitDynamicMode: onExitDynamicMode,
                    onToggleScreenAnalysis: onToggleScreenAnalysis,
                    onShowSearch: onShowSearch
                )

            } else {
                // Show original content with normal styling
                content
                    .background(
                        VisualEffectView(
                            material: .hudWindow,
                            blendingMode: .withinWindow
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .opacity(0.95)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(
                        color: .black.opacity(0.3),
                        radius: 20,
                        x: 0,
                        y: 10
                    )
                    .cornerRadius(16)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: placementManager.isDynamicModeEnabled)
        .animation(placementManager.isDragging ? .none : .spring(response: 0.3, dampingFraction: 0.8), value: placementManager.magneticPosition)
    }
}

extension View {
    func dynamicIslandStyle(
        personalityManager: PersonalityManager,
        userInput: Binding<String>,
        isStreaming: Binding<Bool>,
        screenReasoningEnabled: Binding<Bool>,
        currentResponse: Binding<String>,
        showResponse: Binding<Bool>,
        onSendMessage: @escaping () -> Void,
        onExitDynamicMode: @escaping () -> Void,
        onToggleScreenAnalysis: @escaping () -> Void,
        onShowSearch: @escaping () -> Void
    ) -> some View {
        modifier(DynamicIslandStyle(
            personalityManager: personalityManager,
            userInput: userInput,
            isStreaming: isStreaming,
            screenReasoningEnabled: screenReasoningEnabled,
            currentResponse: currentResponse,
            showResponse: showResponse,
            onSendMessage: onSendMessage,
            onExitDynamicMode: onExitDynamicMode,
            onToggleScreenAnalysis: onToggleScreenAnalysis,
            onShowSearch: onShowSearch
        ))
    }
}
