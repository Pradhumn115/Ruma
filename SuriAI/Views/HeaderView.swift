//
//  HeaderView.swift
//  SuriAI
//
//  Created by Claude on 01/07/25.
//

import SwiftUI


struct HeaderView: View {
    let dismiss: () -> Void
    let showPersonalitySelector: () -> Void
    let screenReasoningEnabled: Bool
    let screenReasoningToggle: () -> Void
    let createNewChat: () -> Void
    let toggleChatHistory: () -> Void
    let showChatHistory: Bool
    let isStreaming: Bool
    let showThinkingText: Bool
    let toggleDynamicMode: () -> Void
    
    @ObservedObject var appState: AppState
    @ObservedObject var personalityManager: PersonalityManager
    @ObservedObject var screenCaptureManager: ScreenCaptureManager
    @ObservedObject var dynamicPlacementManager: DynamicIslandPlacementManager
    
    let memoryStats: MemoryStats?
    
    var body: some View {
        HStack {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            
            Spacer()
            
            // AI Personality Indicator
            PersonalityIndicatorView(
                personalityManager: personalityManager,
                appState: appState,
                isStreaming: isStreaming,
                showThinkingText: showThinkingText,
                action: showPersonalitySelector
            )
            
            Spacer()
            
            // Screen Reasoning Toggle
            ScreenReasoningToggleView(
                enabled: screenReasoningEnabled,
                screenCaptureManager: screenCaptureManager,
                action: screenReasoningToggle
            )
            
            // Dynamic Island Toggle
            DynamicIslandToggleView(
                dynamicPlacementManager: dynamicPlacementManager,
                action: toggleDynamicMode
            )
            
            // New Chat Button
            ActionButton(
                icon: "plus.message",
                action: createNewChat,
                help: "Start a new chat conversation"
            )
            
            // Chat History Toggle
            ActionButton(
                icon: showChatHistory ? "sidebar.right" : "sidebar.left",
                action: toggleChatHistory,
                help: "Toggle chat history sidebar"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Material.ultraThin)
                .mask(LinearGradient(
                    colors: [Color.black, Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
        )
    }
}

struct PersonalityIndicatorView: View {
    @ObservedObject var personalityManager: PersonalityManager
    @ObservedObject var appState: AppState
    let isStreaming: Bool
    let showThinkingText: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                let personalityInfo = personalityManager.getActivePersonalityDisplayInfo()
                
                Text(personalityInfo.icon)
                    .font(.caption)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appState.modelReady ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: appState.modelReady)
                        
                        Text(appState.modelReady ? 
                             (isStreaming && showThinkingText ? "thinking..." : personalityInfo.name) : 
                             "Loading...")
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                            .animation(.easeInOut(duration: 0.3), value: showThinkingText)
                    }
                    
                    Text(appState.modelReady ? "Tap to switch" : "AI Assistant")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!appState.modelReady)
    }
}

struct DynamicIslandToggleView: View {
    @ObservedObject var dynamicPlacementManager: DynamicIslandPlacementManager
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: dynamicPlacementManager.isDynamicModeEnabled ? "rectangle.3.group.bubble.left.fill" : "rectangle.3.group.bubble.left")
                    .font(.system(size: 12, weight: .medium))
                Text("Dynamic")
                    .font(.caption2)
            }
            .foregroundStyle(dynamicPlacementManager.isDynamicModeEnabled ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(dynamicPlacementManager.isDynamicModeEnabled ? Color.purple : Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(dynamicPlacementManager.isDynamicModeEnabled ? 
            "Dynamic Island mode active - drag to reposition" : 
            "Enable Dynamic Island style positioning")
    }
}

struct ScreenReasoningToggleView: View {
    let enabled: Bool
    @ObservedObject var screenCaptureManager: ScreenCaptureManager
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: enabled ? "eye.fill" : "eye")
                    .font(.system(size: 12, weight: .medium))
                Text("Screen")
                    .font(.caption2)
                
                if enabled && !screenCaptureManager.isAvailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }
            .foregroundStyle(enabled ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(enabled ? 
                (screenCaptureManager.isAvailable ? Color.blue : Color.orange) : 
                Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(enabled ? 
            (screenCaptureManager.isAvailable ? 
                "Screen reasoning enabled - AI can see your screen" : 
                "Screen reasoning enabled but permissions needed") : 
            "Enable screen reasoning to let AI analyze your screen")
    }
}

struct ActionButton: View {
    let icon: String
    let action: () -> Void
    let help: String
    
    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}