//
//  DynamicIslandCapsule.swift
//  SuriAI - Dynamic Island Capsule UI Component
//
//  Created by Pradhumn Gupta on 25/05/25.
//

import SwiftUI


struct DynamicIslandCapsule: View {
    @ObservedObject var placementManager = DynamicIslandPlacementManager.shared
    @ObservedObject var personalityManager: PersonalityManager
    @Binding var userInput: String
    @Binding var isStreaming: Bool
    @Binding var screenReasoningEnabled: Bool
    @Binding var currentResponse: String
    @Binding var showResponse: Bool
    let onSendMessage: () -> Void
    let onExitDynamicMode: () -> Void
    let onToggleScreenAnalysis: () -> Void
    let onShowSearch: () -> Void
    
    @State private var isExpanded = true
    @State private var pulseAnimation = false
    @State private var showResponseExpansion = false
    @State private var showThinkingText = false
    @State private var alternatingTimer: Timer?
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Dynamic Island Capsule
            Group {
                switch placementManager.magneticPosition {
                case .topCenter, .bottomCenter:
                    horizontalCapsule
                case .leftEdge, .rightEdge:
                    verticalStrip
                case .topLeft, .topRight:
                    compactSquare
                case .floating:
                    floatingPill
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: placementManager.magneticPosition)
            .onTapGesture(count: 2) {
                // Double tap to expand/collapse for more controls (won't interfere with buttons)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }
            
            // Response Expansion (appears below main capsule)
            if showResponse && !currentResponse.isEmpty {
                responseExpansionView
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .onAppear {
            pulseAnimation = true
        }
        .onChange(of: showResponse) { _, newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showResponseExpansion = newValue
            }
        }
        .onChange(of: isStreaming) { _, newValue in
            if newValue {
                startAlternatingTimer()
            } else {
                stopAlternatingTimer()
            }
        }
        .onDisappear {
            stopAlternatingTimer()
        }
    }
    
    // MARK: - Horizontal Capsule (Top/Bottom Center)
    var horizontalCapsule: some View {
        HStack(spacing: 12) {
            // AI Personality Section
            HStack(spacing: 8) {
                let personalityInfo = personalityManager.getActivePersonalityDisplayInfo()
                
                Circle()
                    .fill(isStreaming ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    .animation(
                        isStreaming ? 
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : 
                        .default, 
                        value: pulseAnimation
                    )
                
                Text(isStreaming && showThinkingText ? "thinking..." : personalityInfo.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .animation(.easeInOut(duration: 0.3), value: showThinkingText)
            }
            if isExpanded{
                
                // Inline Text Input Field
                TextField("Enter Text", text: $userInput)
                    .font(.system(size: 13, weight: .medium))
                    .textFieldStyle(.plain)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                    )
                    .onSubmit {
                        if !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSendMessage()
                        }
                    }
                
                // Functional Control Buttons
                HStack(spacing: 8) {
                    // Send/Stop Button (prominent)
                    Button(action: {
                        if isStreaming {
                            // Stop functionality would be handled by parent
                        } else {
                            onSendMessage()
                        }
                    }) {
                        Circle()
                            .fill(isStreaming ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: isStreaming ? "stop.fill" : "paperplane.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(isStreaming ? .red : .blue)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming)
                    
                    // Screen Analysis Button
                    Button(action: onToggleScreenAnalysis) {
                        Circle()
                            .fill(screenReasoningEnabled ? Color.blue.opacity(0.3) : Color.gray.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: screenReasoningEnabled ? "eye.fill" : "eye")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(screenReasoningEnabled ? .blue : .primary)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    // Exit Button
                    Button(action: onExitDynamicMode) {
                        Circle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 44)
        .frame(width: isExpanded ? 600 : 100)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }
    
    // MARK: - Vertical Strip (Left/Right Edge)
    var verticalStrip: some View {
        VStack(spacing: 12) {
            // AI Status
            Circle()
                .fill(isStreaming ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                .animation(
                    isStreaming ? 
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : 
                    .default, 
                    value: pulseAnimation
                )
            
            VStack(spacing: 8) {
                // Screen Analysis Button
                Button(action: onToggleScreenAnalysis) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(screenReasoningEnabled ? Color.blue.opacity(0.3) : Color.gray.opacity(0.15))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: screenReasoningEnabled ? "eye.fill" : "eye")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(screenReasoningEnabled ? .blue : .primary)
                        )
                }
                .buttonStyle(.plain)
                
                // Send/Stop Button
                Button(action: {
                    if isStreaming {
                        // Stop functionality
                    } else {
                        onSendMessage()
                    }
                }) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isStreaming ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: isStreaming ? "stop.fill" : "paperplane.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isStreaming ? .red : .blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .frame(width: 40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
        )
    }
    
    // MARK: - Compact Square (Corners)
    var compactSquare: some View {
        VStack(spacing: 6) {
            // AI Status
            Circle()
                .fill(isStreaming ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                .animation(
                    isStreaming ? 
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : 
                    .default, 
                    value: pulseAnimation
                )
            
            if isExpanded {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Button(action: onToggleScreenAnalysis) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(screenReasoningEnabled ? Color.blue.opacity(0.3) : Color.gray.opacity(0.15))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Image(systemName: screenReasoningEnabled ? "eye.fill" : "eye")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(screenReasoningEnabled ? .blue : .primary)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: {
                        if isStreaming {
                            // Stop functionality
                        } else {
                            onSendMessage()
                        }
                    }) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isStreaming ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                            .frame(width: 40, height: 20)
                            .overlay(
                                Image(systemName: isStreaming ? "stop.fill" : "paperplane.fill")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(isStreaming ? .red : .blue)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming)
                }
                .transition(.opacity.combined(with: .scale))
            } else {
                let personalityInfo = personalityManager.getActivePersonalityDisplayInfo()
                Text(personalityInfo.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .padding(10)
        .frame(width: isExpanded ? 70 : 44, height: isExpanded ? 70 : 44)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 1)
        )
    }
    
    // MARK: - Floating Pill (Default)
    var floatingPill: some View {
        HStack(spacing: 10) {
            // AI Personality Section
            HStack(spacing: 6) {
                let personalityInfo = personalityManager.getActivePersonalityDisplayInfo()
                
                Circle()
                    .fill(isStreaming ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                    .animation(
                        isStreaming ? 
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : 
                        .default, 
                        value: pulseAnimation
                    )
                
                Text(isStreaming && showThinkingText ? "thinking..." : personalityInfo.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .animation(.easeInOut(duration: 0.3), value: showThinkingText)
            }
            
            // Inline Text Input Field
            TextField("Ask anything...", text: $userInput)
                .font(.system(size: 12, weight: .medium))
                .textFieldStyle(.plain)
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                )
                .onSubmit {
                    if !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSendMessage()
                    }
                }
            
            // Functional Control Buttons
            HStack(spacing: 6) {
                // Send/Stop Button
                Button(action: {
                    if isStreaming {
                        // Stop functionality
                    } else {
                        onSendMessage()
                    }
                }) {
                    Circle()
                        .fill(isStreaming ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: isStreaming ? "stop.fill" : "paperplane.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isStreaming ? .red : .blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming)
                
                // Screen Analysis Button  
                Button(action: onToggleScreenAnalysis) {
                    Circle()
                        .fill(screenReasoningEnabled ? Color.blue.opacity(0.3) : Color.gray.opacity(0.15))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: screenReasoningEnabled ? "eye.fill" : "eye")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(screenReasoningEnabled ? .blue : .primary)
                        )
                }
                .buttonStyle(.plain)
                
                // Exit Button
                Button(action: onExitDynamicMode) {
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.primary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 500, height: 40)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
        )
    }
    
    // MARK: - Response Expansion View
    var responseExpansionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                let personalityInfo = personalityManager.getActivePersonalityDisplayInfo()
                
                Text(personalityInfo.icon)
                    .font(.system(size: 12))
                
                Text(personalityInfo.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                
                Spacer()
                
                // Minimize button
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showResponse = false
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.02))
            
            // Divider
            Divider()
                .background(Color.black.opacity(0.1))
            
            // Response content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    
                    // AI Response Text or Loading State
                    if currentResponse.isEmpty && isStreaming {
                        // Initial loading/thinking state
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("🧠 AI is thinking...")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            
                            // Animated thinking dots
                            HStack(spacing: 4) {
                                ForEach(0..<3) { index in
                                    Circle()
                                        .fill(Color.blue.opacity(0.6))
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(pulseAnimation ? 1.0 : 0.5)
                                        .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: pulseAnimation)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                    } else {
                        // AI Response Text or Placeholder
                        VStack(alignment: .leading, spacing: 8) {
                            if !currentResponse.isEmpty {
                                Text(currentResponse)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if showResponse {
                                Text("Waiting for AI response...")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                            
                            if isStreaming && !currentResponse.isEmpty {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Still responding...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 250) // Set minimum height so response is visible
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.top, 6) // Small gap between capsule and expansion
        .frame(width: 500) // Set consistent width with Dynamic Island
    }
    
    // MARK: - Timer Helper Methods
    private func startAlternatingTimer() {
        stopAlternatingTimer() // Stop any existing timer
        alternatingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showThinkingText.toggle()
            }
        }
    }
    
    private func stopAlternatingTimer() {
        alternatingTimer?.invalidate()
        alternatingTimer = nil
        showThinkingText = false
    }
}

// MARK: - Preview
struct DynamicIslandCapsule_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            DynamicIslandCapsule(
                personalityManager: PersonalityManager(),
                userInput: .constant("Hello world"),
                isStreaming: .constant(false),
                screenReasoningEnabled: .constant(false),
                currentResponse: .constant("Hello! This is a test AI response that should be visible in the Dynamic Island expansion. If you can see this text, the response display is working correctly."),
                showResponse: .constant(true),
                onSendMessage: {},
                onExitDynamicMode: {},
                onToggleScreenAnalysis: {},
                onShowSearch: {}
            )
            
            Text("Dynamic Island Capsule UI")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}





