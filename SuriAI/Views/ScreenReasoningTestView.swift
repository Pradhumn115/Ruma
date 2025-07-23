//
//  ScreenReasoningTestView.swift
//  SuriAI - Screen Reasoning Test Interface
//
//  Created by Claude on 01/07/25.
//

import SwiftUI

struct ScreenReasoningTestView: View {
    @StateObject private var screenCaptureManager = ScreenCaptureManager()
    @State private var questionText = ""
    @State private var analysisResult = ""
    @State private var isAnalyzing = false
    @State private var useStreaming = true
    @State private var selectedTestQuestion = TestQuestion.whatApp
    @State private var streamedContent = ""
    
    enum TestQuestion: String, CaseIterable {
        case whatApp = "What application is this and what can I do here?"
        case nextSteps = "What actions can I take next?"
        case fillForm = "How do I fill out this form or complete this task?"
        case findButtons = "What buttons or clickable elements are available?"
        case navigation = "How can I navigate from here?"
        case completeTask = "Help me complete what I'm trying to do"
        case findFeature = "Help me find a specific feature or option"
        case troubleshoot = "Is there anything that looks like an error or issue?"
        case shortcuts = "What keyboard shortcuts or quick actions are available?"
        case workflow = "What's the typical workflow from this screen?"
        
        var displayName: String {
            return self.rawValue
        }
        
        var category: String {
            switch self {
            case .whatApp, .completeTask:
                return "General Analysis"
            case .navigation, .findFeature, .nextSteps:
                return "Navigation Help"
            case .fillForm, .findButtons, .workflow:
                return "Task Assistance"
            case .troubleshoot, .shortcuts:
                return "Advanced Help"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    Text("Screen Reasoning Test")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: refreshCapture) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Refresh screen capture capabilities")
                }
                
                Text("Test the enhanced Apple Vision + Python MLX screen analysis pipeline")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            // Status indicators
            HStack(spacing: 20) {
                StatusIndicator(
                    title: "Screen Capture",
                    isActive: screenCaptureManager.isAvailable,
                    icon: "camera.viewfinder"
                )
                
                StatusIndicator(
                    title: "Apple Vision",
                    isActive: true, // Always available on modern macOS
                    icon: "eye"
                )
                
                StatusIndicator(
                    title: "Analysis Ready",
                    isActive: !isAnalyzing,
                    icon: "brain.head.profile"
                )
            }
            
            Divider()
            
            // Quick test questions
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Test Questions")
                    .font(.headline)
                
                let groupedQuestions = Dictionary(grouping: TestQuestion.allCases, by: { $0.category })
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(Array(groupedQuestions.keys.sorted()), id: \.self) { category in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            ForEach(groupedQuestions[category] ?? [], id: \.self) { question in
                                Button(action: {
                                    selectedTestQuestion = question
                                    questionText = question.rawValue
                                }) {
                                    HStack {
                                        Text(question.displayName)
                                            .font(.caption)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        if selectedTestQuestion == question {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                                .font(.caption)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        selectedTestQuestion == question ? 
                                        Color.blue.opacity(0.2) : Color.gray.opacity(0.1)
                                    )
                                    .cornerRadius(4)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            
            // Custom question input
            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Question")
                    .font(.headline)
                
                TextField("Ask anything about the screen content...", text: $questionText, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(2...4)
            }
            
            // Analysis options
            HStack {
                Toggle("Enable Streaming", isOn: $useStreaming)
                    .toggleStyle(SwitchToggleStyle())
                
                Spacer()
                
                Button(action: clearResults) {
                    Text("Clear")
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: analyzeScreen) {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isAnalyzing ? "Analyzing..." : "Analyze Screen")
                    }
                }
                .disabled(questionText.isEmpty || isAnalyzing)
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            // Results area
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Analysis Results")
                        .font(.headline)
                    
                    Spacer()
                    
                    if !analysisResult.isEmpty || !streamedContent.isEmpty {
                        Button(action: copyResults) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Copy results to clipboard")
                    }
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if useStreaming && !streamedContent.isEmpty {
                            Text(streamedContent)
                                .font(.system(.body, design: .default))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if !analysisResult.isEmpty {
                            Text(analysisResult)
                                .font(.system(.body, design: .default))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("Analysis results will appear here...")
                                .foregroundColor(.secondary)
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                .frame(minHeight: 200)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            refreshCapture()
        }
    }
    
    // MARK: - Actions
    
    private func refreshCapture() {
        Task {
            await screenCaptureManager.refreshScreenPermissions()
        }
    }
    
    private func analyzeScreen() {
        guard !questionText.isEmpty else { return }
        
        isAnalyzing = true
        
        Task {
            if useStreaming {
                await performStreamingAnalysis()
            } else {
                await performStandardAnalysis()
            }
            
            await MainActor.run {
                isAnalyzing = false
            }
        }
    }
    
    private func performStandardAnalysis() async {
        let result = await screenCaptureManager.analyzeScreenContent(
            userQuestion: questionText,
            userID: "test_user",
            chatID: "screen_reasoning_test"
        )
        
        await MainActor.run {
            analysisResult = result
            streamedContent = ""
        }
    }
    
    private func performStreamingAnalysis() async {
        await MainActor.run {
            streamedContent = ""
            analysisResult = ""
        }
        
        // Use real streaming from ScreenCaptureManager
        await screenCaptureManager.streamScreenAnalysis(
            userQuestion: questionText,
            userID: "test_user",
            chatID: "screen_reasoning_test"
        ) { chunk in
            Task { @MainActor in
                streamedContent += chunk
            }
        }
    }
    
    private func clearResults() {
        analysisResult = ""
        streamedContent = ""
    }
    
    private func copyResults() {
        let textToCopy = useStreaming ? streamedContent : analysisResult
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
    }
}

// MARK: - Supporting Views

struct StatusIndicator: View {
    let title: String
    let isActive: Bool
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(isActive ? .green : .red)
                .font(.caption)
            
            Text(title)
                .font(.caption)
                .foregroundColor(isActive ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
    }
}

// MARK: - Preview

struct ScreenReasoningTestView_Previews: PreviewProvider {
    static var previews: some View {
        ScreenReasoningTestView()
            .frame(width: 600, height: 800)
    }
}