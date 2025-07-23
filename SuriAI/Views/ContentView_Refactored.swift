//
//  ContentView_Refactored.swift
//  SuriAI - Cleaned and Organized
//
//  Created by Claude on 01/07/25.
//

import SwiftUI
import AppKit
import MarkdownUI

// MARK: - Main ContentView (Significantly Cleaned Up)
struct ContentView_Refactored: View {
    var dismiss: () -> ()

    @EnvironmentObject var focusModel: FocusModel
    @FocusState private var isTextFieldFocused: Bool
    @EnvironmentObject var sizeUpdater: WindowSizeUpdater
    
    // MARK: - State Properties
    @State private var streamingTask: Task<Void, Error>? = nil
    @State var messages: [ChatMessage] = []
    @State private var userInput: String = ""
    @State private var response: String = ""
    @State var showResult: Bool = false
    @State var loading: Bool = false
    @State private var isStreaming: Bool = false
    @State private var showChatHistory: Bool = false
    @State private var currentChatId: String? = nil
    @State private var chatSessions: [ChatSession] = []
    @State private var memoryStats: MemoryStats? = nil
    @State private var screenReasoningEnabled: Bool = false
    @State private var showPersonalitySelector: Bool = false
    @State private var showThinkingText = false
    @State private var alternatingTimer: Timer?
    
    // MARK: - ObservableObjects
    @StateObject private var appState = AppState()
    @StateObject private var screenCaptureManager = ScreenCaptureManager()
    @StateObject private var personalityManager = PersonalityManager()
    @StateObject private var dynamicPlacementManager = DynamicIslandPlacementManager.shared
    @StateObject private var userSettings = UserSettings.shared

    var body: some View {
        ZStack {
//             Background with glassmorphism effect
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            HStack(spacing: 0) {
                // Main Chat Interface
                mainChatView
                
                // Chat History Sidebar
                if showChatHistory {
                    ChatSidebarView(
                        chatSessions: chatSessions,
                        currentChatId: currentChatId,
                        showChatHistory: showChatHistory,
                        showResult: showResult,
                        onSelectSession: { sessionId in
                            Task { await selectChatSession(sessionId) }
                        },
                        onDeleteSession: { sessionId in
                            Task { await deleteChatSession(sessionId) }
                        },
                        onCreateNewChat: {
                            Task { await createNewChatSession() }
                        },
                        onCloseSidebar: {
                            toggleChatHistory()
                        }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(Material.ultraThin)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(LinearGradient(
                    colors: [Color.white.opacity(0.2), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .frame(minWidth: 400, maxWidth: showChatHistory ? 800 : 600)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            Task {
                await initializeApp()
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showChatHistory)
        .sheet(isPresented: $showPersonalitySelector) {
            PersonalitySelectorView_Fixed(personalityManager: personalityManager)
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
    
    // MARK: - Main Chat View
    private var mainChatView: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView(
                dismiss: dismiss,
                showPersonalitySelector: { showPersonalitySelector = true },
                screenReasoningEnabled: screenReasoningEnabled,
                screenReasoningToggle: toggleScreenReasoning,
                createNewChat: { Task { await createNewChatSession() } },
                toggleChatHistory: toggleChatHistory,
                showChatHistory: showChatHistory,
                isStreaming: isStreaming,
                showThinkingText: showThinkingText,
                toggleDynamicMode: {
                    dynamicPlacementManager.toggleDynamicMode()
                },
                appState: appState,
                personalityManager: personalityManager,
                screenCaptureManager: screenCaptureManager,
                dynamicPlacementManager: dynamicPlacementManager,
                memoryStats: memoryStats
            )
            
            // Chat Messages Area
            ChatMessagesView(
                messages: messages,
                loading: loading,
                isStreaming: isStreaming,
                showResult: showResult,
                response: response,
                userInput: userInput,
                submitAction: submitAction,
                loadMoreMessages: { /* Not implemented in refactored view */ },
                isLoadingOlderMessages: false,
                hasMoreMessages: false,
                personalityManager: personalityManager
            )
            
            // Input Area
            InputAreaView(
                userInput: $userInput,
                screenReasoningEnabled: screenReasoningEnabled,
                isStreaming: isStreaming,
                submitAction: submitAction,
                stopAction: stopGeneration,
                appState: appState,
                focusModel: focusModel
            )
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Actions
    private func initializeApp() async {
        do {
            try await waitForModelReady()
            appState.modelReady = true
            await loadChatSessions()
            await loadMemoryStats()
            await personalityManager.loadPersonalities()
        } catch {
            print("❌ Model failed to load: \(error)")
        }
    }
    
    private func toggleScreenReasoning() {
        screenReasoningEnabled.toggle()
        if screenReasoningEnabled {
            Task {
                await screenCaptureManager.refreshScreenPermissions()
            }
        }
    }
    
    private func toggleChatHistory() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showChatHistory.toggle()
            let newWidth: CGFloat = showChatHistory ? 800 : 600
            let newHeight: CGFloat = showResult ? 500 : 120
            sizeUpdater.updateSize(to: CGSize(width: newWidth, height: newHeight))
        }
    }
    
    private func stopGeneration() {
        streamingTask?.cancel()
        Task {
            await stopStreamingGeneration()
        }
        isStreaming = false
    }
    
    private func stopStreamingGeneration() async {
        // Additional async stop logic if needed
        print("🛑 Stopping generation")
    }
    
    // MARK: - Chat Functions
    private func submitAction() {
        streamingTask = Task {
            await performChatSubmission()
        }
    }
    
    private func performChatSubmission() async {
        do {
            loading = true
            isStreaming = true
            
            // Add user message
            messages.append(ChatMessage(role: .user, content: userInput))
            response = ""
            
            // Store current input before clearing
            let currentInput = userInput
            
            // Choose appropriate stream based on configuration
            let stream = try await getAppropriateStream(for: currentInput)
            
            // Add placeholder AI message
            messages.append(ChatMessage(role: .ai, content: ""))
            
            showResult = true
            updateWindowSize()
            loading = false
            userInput = ""
            
            // Process streaming response
            await processStreamingResponse(stream)
            
            // Cleanup and updates
            await finalizeSubmission()
            
        } catch {
            await handleSubmissionError(error)
        }
    }
    
    private func getAppropriateStream(for input: String) async throws -> AsyncThrowingStream<String, Error> {
        if personalityManager.hasPersonalities() {
            if screenReasoningEnabled {
                let enhancedInput = await createEnhancedInputWithScreenAnalysis(input)
                return try await streamChatResponseWithPersonality(
                    userInput: enhancedInput,
                    chatId: currentChatId,
                    userId: userSettings.username,
                    personalityManager: personalityManager
                )
            } else {
                return try await streamChatResponseWithPersonality(
                    userInput: input,
                    chatId: currentChatId,
                    userId: userSettings.username,
                    personalityManager: personalityManager
                )
            }
        } else {
            if screenReasoningEnabled {
                let enhancedInput = await createEnhancedInputWithScreenAnalysis(input)
                return try await streamChatResponseWithMemory(
                    userInput: enhancedInput,
                    chatId: currentChatId,
                    userId: "pradhumn"
                )
            } else {
                return try await streamChatResponseWithMemory(
                    userInput: input,
                    chatId: currentChatId,
                    userId: "pradhumn"
                )
            }
        }
    }
    
    private func createEnhancedInputWithScreenAnalysis(_ input: String) async -> String {
        // Add visual feedback
        messages.append(ChatMessage(role: .ai, content: "🧠 Starting advanced screen intelligence analysis..."))
        
        // Perform analysis
        let screenAnalysis = await screenCaptureManager.analyzeScreenContent(userQuestion: input, userID: userSettings.username, chatID: currentChatId ?? "")
        
        
        // Remove the analysis message
        if let lastIndex = messages.lastIndex(where: { $0.role == .ai && $0.content.contains("🧠 Starting") }) {
            messages.remove(at: lastIndex)
        }
        
        return """
        \(input)
        
        [ADVANCED_SCREEN_ANALYSIS]
        \(screenAnalysis)
        
        Please provide a comprehensive response based on the screen analysis above and the user's question.
        """
    }
    
    private func processStreamingResponse(_ stream: AsyncThrowingStream<String, Error>) async {
        var fullMessage = ""
        
        do {
            for try await chunk in stream {
                let cleanChunk = chunk.replacingOccurrences(of: "<|eot_id|>", with: "")
                if cleanChunk.isEmpty { continue }
                
                fullMessage += cleanChunk
                
                await MainActor.run {
                    if let lastIndex = messages.lastIndex(where: { $0.role == .ai }) {
                        messages[lastIndex].content += cleanChunk
                    }
                }
                response += cleanChunk
                
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms delay
            }
        } catch {
            print("Streaming error: \(error)")
        }
        
        await MainActor.run {
            isStreaming = false
        }
    }
    
    private func finalizeSubmission() async {
        // Handle session continuity
        if currentChatId == nil {
            await loadChatSessions()
            if let latestSession = chatSessions.first {
                currentChatId = latestSession.id
                print("✅ New conversation created with chat_id: \(latestSession.id)")
            }
        } else {
            print("✅ Continuing conversation with chat_id: \(currentChatId!)")
        }
        
        // Reload stats and sessions
        await loadMemoryStats()
        await loadChatSessions()
    }
    
    private func handleSubmissionError(_ error: Error) async {
        print("Streaming failed:", error)
        await MainActor.run {
            showResult = true
            loading = false
            isStreaming = false
            updateWindowSize()
            messages.append(ChatMessage(role: .ai, content: "Streaming failed - please try again..."))
        }
    }
    
    private func updateWindowSize() {
        let newHeight: CGFloat = showResult ? 500 : 120
        sizeUpdater.updateSize(to: CGSize(width: showChatHistory ? 800 : 600, height: newHeight))
    }
    
    // MARK: - Session Management Functions
    func loadChatSessions() async {
        // Implementation moved to cleaner async function
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/chat_sessions/\(userSettings.username)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode([String: [ChatSession]].self, from: data)
            await MainActor.run {
                chatSessions = response["sessions"] ?? []
            }
        } catch {
            print("Failed to load chat sessions: \(error)")
        }
    }
    
    func loadMemoryStats() async {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/statistics/\(userSettings.username)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode([String: MemoryStats].self, from: data)
            await MainActor.run {
                memoryStats = response["statistics"]
            }
        } catch {
            print("Failed to load memory stats: \(error)")
        }
    }
    
    func selectChatSession(_ sessionId: String) async {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/chat_sessions/\(userSettings.username)/\(sessionId)/history")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode([String: [ChatHistoryMessage]].self, from: data)
            
            await MainActor.run {
                currentChatId = sessionId
                messages.removeAll()
                
                if let history = response["history"] {
                    for historyMessage in history {
                        let role: ChatMessage.Role = historyMessage.role == "human" ? .user : .ai
                        messages.append(ChatMessage(role: role, content: historyMessage.content))
                    }
                    print("✅ Loaded \(history.count) messages for chat \(sessionId)")
                }
                
                showResult = true
                updateWindowSize()
            }
        } catch {
            print("❌ Failed to load chat history: \(error)")
            await MainActor.run {
                currentChatId = sessionId
                messages.removeAll()
                showResult = true
                updateWindowSize()
            }
        }
    }
    
    func deleteChatSession(_ sessionId: String) async {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/chat_session/\(sessionId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                await MainActor.run {
                    chatSessions.removeAll { $0.id == sessionId }
                    
                    if currentChatId == sessionId {
                        currentChatId = nil
                        messages.removeAll()
                        showResult = false
                        updateWindowSize()
                    }
                }
            }
        } catch {
            print("Failed to delete chat session: \(error)")
        }
    }
    
    func createNewChatSession() async {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/chat_session")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = [
                "user_id": userSettings.username,
                "title": "New Chat \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let responseData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let chatId = responseData["chat_id"] as? String {
                    
                    await MainActor.run {
                        currentChatId = chatId
                        messages.removeAll()
                        showResult = false
                        updateWindowSize()
                        print("✅ Created new chat session: \(chatId)")
                    }
                    
                    await loadChatSessions()
                }
            }
        } catch {
            print("❌ Failed to create new chat session: \(error)")
            
            await MainActor.run {
                currentChatId = nil
                messages.removeAll()
                showResult = false
                updateWindowSize()
            }
        }
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
