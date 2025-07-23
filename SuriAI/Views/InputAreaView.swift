//
//  InputAreaView.swift
//  SuriAI
//
//  Created by Claude on 01/07/25.
//

import SwiftUI

struct InputAreaView: View {
    @Binding var userInput: String
    @FocusState private var isTextFieldFocused: Bool
    
    let screenReasoningEnabled: Bool
    let isStreaming: Bool
    let submitAction: () -> Void
    let stopAction: () -> Void
    
    @ObservedObject var appState: AppState
    @ObservedObject var focusModel: FocusModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Input field with modern design
            HStack(spacing: 12) {
                // Screen reasoning indicator
                if screenReasoningEnabled {
                    ScreenReasoningIndicator()
                }
                
                // Text input with enhanced styling
                ChatTextField(
                    userInput: $userInput,
                    isTextFieldFocused: _isTextFieldFocused,
                    focusModel: focusModel,
                    appState: appState,
                    screenReasoningEnabled: screenReasoningEnabled,
                    isStreaming: isStreaming,
                    submitAction: submitAction
                )
                
                // Send/Stop button
                SendStopButton(
                    isStreaming: isStreaming,
                    userInput: userInput,
                    submitAction: submitAction,
                    stopAction: stopAction,
                    appState: appState
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Rectangle()
                    .fill(Material.ultraThin)
                    .mask(LinearGradient(
                        colors: [Color.black.opacity(0.8), Color.black],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            )
        }
    }
}

struct ScreenReasoningIndicator: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "eye.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.blue)
            Text("Screen")
                .font(.caption2)
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ChatTextField: View {
    @Binding var userInput: String
    @FocusState var isTextFieldFocused: Bool
    
    @ObservedObject var focusModel: FocusModel
    @ObservedObject var appState: AppState
    
    let screenReasoningEnabled: Bool
    let isStreaming: Bool
    let submitAction: () -> Void
    
    private var placeholder: String {
        if !appState.modelReady {
            return "Loading model..."
        }
        return screenReasoningEnabled ? "Ask about screen or anything..." : "Ask anything..."
    }
    
    var body: some View {
        TextField(placeholder, text: $userInput, axis: .vertical)
            .focused($isTextFieldFocused)
            .onChange(of: focusModel.focusTextField) { newValue, _ in
                isTextFieldFocused = true
                focusModel.focusTextField = false
            }
            .font(.body)
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isTextFieldFocused ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            )
            .onSubmit {
                if canSubmit {
                    submitAction()
                }
            }
            .disabled(!appState.modelReady || isStreaming)
    }
    
    private var canSubmit: Bool {
        !isStreaming && appState.modelReady && !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SendStopButton: View {
    let isStreaming: Bool
    let userInput: String
    let submitAction: () -> Void
    let stopAction: () -> Void
    
    @ObservedObject var appState: AppState
    
    private var canSubmit: Bool {
        appState.modelReady && !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var isDisabled: Bool {
        !appState.modelReady || (!isStreaming && userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    
    var body: some View {
        Button {
            if isStreaming {
                stopAction()
            } else if canSubmit {
                submitAction()
            }
        } label: {
            buttonContent
                .font(.system(size: 16, weight: .medium))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isStreaming ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
    
    @ViewBuilder
    private var buttonContent: some View {
        if isStreaming {
            Image(systemName: "stop.fill")
                .foregroundStyle(.red)
        } else if canSubmit {
            Image(systemName: "paperplane.fill")
                .foregroundStyle(.blue)
        } else {
            Image(systemName: "paperplane.fill")
                .foregroundStyle(.secondary)
        }
    }
}