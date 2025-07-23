//
//  ContentView_Modern.swift
//  SuriAI - Advanced AI Chat Interface
//
//  Created by Pradhumn Gupta on 25/05/25.
//

import SwiftUI
import AppKit
import MarkdownUI

// MARK: - Custom Dot Loader Component
struct DotLoader: View {
    @State private var isAnimating = false
    let dotCount: Int
    let dotSize: CGFloat
    let animationDelay: Double
    let color: Color
    
    init(dotCount: Int = 3, dotSize: CGFloat = 6, animationDelay: Double = 0.2, color: Color = .blue) {
        self.dotCount = dotCount
        self.dotSize = dotSize
        self.animationDelay = animationDelay
        self.color = color
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(color.opacity(0.6))
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * animationDelay), value: isAnimating)
            }
        }
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

// MARK: - Text Highlight Animation Component
struct AnimatedHighlightText: View {
    let text: String
    let isAnimating: Bool
    let font: Font
    let color: Color
    let highlightColor: Color
    let animationDuration: Double
    
    @State private var animationProgress: CGFloat = 0
    
    init(
        text: String,
        isAnimating: Bool = false,
        font: Font = .body,
        color: Color = .primary,
        highlightColor: Color = .blue.opacity(0.3),
        animationDuration: Double = 2.0
    ) {
        self.text = text
        self.isAnimating = isAnimating
        self.font = font
        self.color = color
        self.highlightColor = highlightColor
        self.animationDuration = animationDuration
    }
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .background(
                GeometryReader { geometry in
                    Rectangle()
                        .fill(highlightColor)
                        .frame(width: geometry.size.width * animationProgress)
                        .animation(.easeInOut(duration: animationDuration), value: animationProgress)
                }
            )
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    animationProgress = 0
                    withAnimation(.easeInOut(duration: animationDuration)) {
                        animationProgress = 1.0
                    }
                } else {
                    animationProgress = 0
                }
            }
    }
}

// MARK: - Enhanced Text Display with Highlight Animation
struct ThinkingText: View {
    let personalityName: String
    let isStreaming: Bool
    let showThinkingText: Bool
    let font: Font
    let color: Color
    
    @State private var isHighlightAnimating = false
    
    init(
        personalityName: String,
        isStreaming: Bool,
        showThinkingText: Bool,
        font: Font = .caption.bold(),
        color: Color = .primary
    ) {
        self.personalityName = personalityName
        self.isStreaming = isStreaming
        self.showThinkingText = showThinkingText
        self.font = font
        self.color = color
    }
    
    var body: some View {
        let displayText = isStreaming && showThinkingText ? "thinking..." : personalityName
        
        AnimatedHighlightText(
            text: displayText,
            isAnimating: isHighlightAnimating,
            font: font,
            color: color,
            highlightColor: .blue.opacity(0.2),
            animationDuration: 1.5
        )
        .onChange(of: displayText) { _, _ in
            if isStreaming {
                isHighlightAnimating = true
                // Stop animation after duration
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isHighlightAnimating = false
                }
            }
        }
        .onChange(of: isStreaming) { _, newValue in
            if newValue {
                isHighlightAnimating = true
            } else {
                isHighlightAnimating = false
            }
        }
    }
}

// MARK: - Supporting Data Models (imported from existing files)
// ChatSession and ChatSessionRow are defined in ChatHistoryPanel.swift

struct MemoryStats: Codable {
    let totalMemories: Int
    let totalTokens: Int
    let totalSizeMb: Double
    let avgImportance: Double
    
    enum CodingKeys: String, CodingKey {
        case totalMemories = "total_memories"
        case totalTokens = "total_tokens"
        case totalSizeMb = "combined_size_mb"
        case avgImportance = "avg_importance"
    }
}

struct MemoryStatsResponse: Codable {
    let success: Bool
    let statistics: MemoryStats
}

// ChatHistoryMessage is defined in ChatHistoryPanel.swift

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Message Bubble Component
struct MessageBubble: View {
    let message: ChatMessage
    let personalityManager: PersonalityManager
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 50)
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    
                    Text("You")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        let personalityInfo = personalityManager.getActivePersonalityDisplayInfo()
                        
                        Text(personalityInfo.icon)
                            .font(.caption)
                        
                        Text(personalityInfo.name)
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                        
                        Spacer()
                    }
                    .padding(.leading, 8)
                    
                    Markdown(message.content)
                        .markdownTextStyle {
                            FontSize(14)
                            ForegroundColor(.primary)
                        }
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                )
                        )
                }
                
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Main ContentView
struct ContentView: View {
    var dismiss: () -> ()

    @EnvironmentObject var focusModel: FocusModel
    @FocusState private var isTextFieldFocused: Bool
    @State private var streamingTask: Task<Void, Error>? = nil
    @State var messages: [ChatMessage] = []
    @State private var displayedMessages: [ChatMessage] = []  // Only messages currently displayed
    @State private var isLoadingOlderMessages = false
    @State private var hasMoreMessages = true
    @State private var messagesPerPage = 10  // Load 10 messages at a time for performance
    @State private var maxVisibleMessages = 20  // Keep only 20 messages in memory for performance
    @State private var userInput: String = ""
    @State private var response: String = ""
    @State var showResult: Bool = false
    @State var loading: Bool = false
    @State private var text: String = ""
    @State private var isStreaming: Bool = false
    @StateObject private var appState = AppState()
    @State private var textStreaming: Bool = false
    @State private var currentChatId: String? = nil
    @State private var chatSessions: [ChatSession] = []
    @State private var memoryStats: MemoryStats? = nil
    @State private var isCacheInitializing: Bool = false
    @State private var screenReasoningEnabled: Bool = false
    @StateObject private var screenCaptureManager = ScreenCaptureManager()
    @StateObject private var personalityManager = PersonalityManager()
    @StateObject private var overlayManager = SmartOverlayManager.shared
    @StateObject private var dynamicPlacementManager = DynamicIslandPlacementManager.shared
    @StateObject private var userSettings = UserSettings.shared
    @State private var showPersonalitySelector: Bool = false
    @State private var showChatHistory: Bool = false
    @State private var overlayMode: Bool = false
    @State private var showSearchDialog: Bool = false
    @State private var dynamicIslandResponse: String = ""
    @State private var showDynamicIslandResponse: Bool = false
    @State private var memoryUrgencyMode: String = "normal"
    @State private var showUrgencyModeSelector: Bool = false
    @State private var showThinkingText = false
    @State private var alternatingTimer: Timer?

    @EnvironmentObject var sizeUpdater: WindowSizeUpdater

    var body: some View {
        ZStack {
            // Background with glassmorphism effect
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
   
            ZStack {
                // Main Chat Interface - always full width and fixed position
                mainChatView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Chat History Panel - overlay positioned to the right
                if showChatHistory {
                    HStack {
                        Spacer()
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
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    showChatHistory = false
                                }
                            }
                        )
                        .offset(x: 0) // Position outside main content area
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .allowsHitTesting(true)
                }
            }
            
        }
        .background(Color.clear)
        .frame(minWidth: 400, maxWidth: .infinity)
//        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            print("🟢🟢🟢 CONTENTVIEW APPEARED 🟢🟢🟢")
            // Removed UI state tracking from onAppear - handled by hotkey instead
            
            Task {
                do {
                    try await waitForModelReady()
                    appState.modelReady = true
                    await loadChatSessions()
                    await loadMemoryStats()
                    await personalityManager.loadPersonalities()
                    
                    // Continue previous chat session if available, else create new one
                    await continueOrCreateChatSession()
                    
                } catch {
                    print("❌ Model failed to load: \(error)")
                }
            }
        }
        .dynamicIslandStyle(
            personalityManager: personalityManager,
            userInput: $userInput,
            isStreaming: $isStreaming,
            screenReasoningEnabled: $screenReasoningEnabled,
            currentResponse: $dynamicIslandResponse,
            showResponse: $showDynamicIslandResponse,
            onSendMessage: {
                if !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    submitDynamicIslandAction()
                }
            },
            onExitDynamicMode: {
                dynamicPlacementManager.toggleDynamicMode()
            },
            onToggleScreenAnalysis: {
                screenReasoningEnabled.toggle()
                if screenReasoningEnabled {
                    Task {
                        await screenCaptureManager.refreshScreenPermissions()
                    }
                }
            },
            onShowSearch: {
                showSearchDialog = true
            }
        )

        .onDisappear {
            print("🔴🔴🔴 CONTENTVIEW DISAPPEARED 🔴🔴🔴")
            // Removed UI state tracking from onDisappear - handled by window close instead
        }
        .sheet(isPresented: $showPersonalitySelector) {
            PersonalitySelectorView_Fixed(personalityManager: personalityManager)
        }
        .sheet(isPresented: $showSearchDialog) {
            SearchDialogView(userInput: $userInput, onSearch: {
                showSearchDialog = false
                submitAction()
            })
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
    var mainChatView: some View {
        VStack(spacing: 0) {
            // Header with modern styling
            headerView
            
            // Chat Messages Area
            chatMessagesView
            
            // Input Area with modern design
            inputAreaView
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Header View (Using Modular Component)
    var headerView: some View {
        HeaderView(
            dismiss: {
                if isStreaming {
                    streamingTask?.cancel()
                    Task {
                        await stopGeneration()
                    }
                    isStreaming = false
                }
                self.dismiss()
                UIStateManager.shared.forceUIInactive()
            },
            showPersonalitySelector: { showPersonalitySelector = true },
            screenReasoningEnabled: screenReasoningEnabled,
            screenReasoningToggle: {
                screenReasoningEnabled.toggle()
                if screenReasoningEnabled {
                    Task {
                        await screenCaptureManager.refreshScreenPermissions()
                    }
                }
            },
            createNewChat: { 
                Task { 
                    await createNewChatSession() 
                } 
            },
            toggleChatHistory: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showChatHistory.toggle()
                }
            },
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
    }
    
    // MARK: - Chat Messages View
    var chatMessagesView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                if loading && messages.isEmpty {
                    // Loading state
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            DotLoader(dotCount: 3, dotSize: 8, color: .blue)
                            
                            AnimatedHighlightText(
                                text: "🧠 AI is thinking...",
                                isAnimating: loading,
                                font: .body.weight(.medium),
                                color: .primary,
                                highlightColor: .blue.opacity(0.3),
                                animationDuration: 2.5
                            )
                            
                            // Additional animated thinking dots
                            DotLoader(dotCount: 5, dotSize: 6, animationDelay: 0.15, color: .blue)
                            
                            AnimatedHighlightText(
                                text: "Preparing your response...",
                                isAnimating: loading,
                                font: .caption,
                                color: .secondary,
                                highlightColor: .gray.opacity(0.2),
                                animationDuration: 3.0
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if messages.isEmpty {
                    // Empty state with modern design
                    VStack(spacing: 20) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.6))
                        
                        VStack(spacing: 8) {
                            Text("Welcome to Ruma")
                                .font(.title2.bold())
                                .foregroundStyle(.primary)
                            
                            Text("Advanced AI with memory capabilities")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(spacing: 12) {
                            Text("Try asking:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach([
                                    "Remember my name",
                                    "Search latest news",
                                    "Explain quantum physics",
                                    "Help with coding"
                                ], id: \.self) { suggestion in
                                    Button {
                                        userInput = suggestion
                                        submitAction()
                                    } label: {
                                        Text(suggestion)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundStyle(.blue)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    // Messages list with modern styling and pagination
                    LazyVStack(alignment: .leading, spacing: 16) {
                        // Load more indicator at the top
                        if hasMoreMessages {
                            HStack {
                                if isLoadingOlderMessages {
                                    DotLoader(dotCount: 3, dotSize: 4, color: .secondary)
                                    Text("Loading older messages...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("Load older messages") {
                                        Task {
                                            await loadMoreMessages()
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .onAppear {
                                // Auto-load when scrolled to top (more user-friendly)
                                if !isLoadingOlderMessages && displayedMessages.count > 0 {
                                    Task {
                                        await loadMoreMessages()
                                    }
                                }
                            }
                        }
                        
                        ForEach(displayedMessages) { message in
                            MessageBubble(message: message, personalityManager: personalityManager)
                                .id(message.id)
                        }
                        
                        // Loading indicator for streaming
                        if isStreaming {
                            HStack {
                                VStack(spacing: 8) {
                                    HStack(spacing: 8) {
                                        DotLoader(dotCount: 3, dotSize: 6, color: .blue)
                                        AnimatedHighlightText(
                                            text: "🧠 AI is thinking...",
                                            isAnimating: isStreaming,
                                            font: .caption.weight(.medium),
                                            color: .primary,
                                            highlightColor: .blue.opacity(0.25),
                                            animationDuration: 2.0
                                        )
                                    }
                                    
//                                    // Additional animated thinking dots
//                                    DotLoader(dotCount: 4, dotSize: 5, animationDelay: 0.18, color: .blue)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .id("thinking-indicator")
                        }
                    }
                    .padding(.vertical, 16)
                }
                
                // Scroll anchor
                Color.clear.frame(height: 1).id("BOTTOM")
            }
            .scrollIndicators(.never)
            .background(Color.clear)
            .onChange(of: response) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    scrollProxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    scrollProxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: showResult ? .infinity : 0)
        .opacity(showResult ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: showResult)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showChatHistory)

    }
    
    // MARK: - Input Area View
    var inputAreaView: some View {
        VStack(spacing: 0) {
            // Input field with modern design
            HStack(alignment: .bottom, spacing: 12) {
                // Screen reasoning indicator
                if screenReasoningEnabled {
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
                
                // Memory urgency mode selector
                Button {
                    showUrgencyModeSelector.toggle()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: urgencyModeIcon(memoryUrgencyMode))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(urgencyModeColor(memoryUrgencyMode))
                        Text(memoryUrgencyMode.capitalized)
                            .font(.caption2)
                            .foregroundStyle(urgencyModeColor(memoryUrgencyMode))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
                    .background(urgencyModeColor(memoryUrgencyMode).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showUrgencyModeSelector) {
                    urgencyModeSelector
                }
                
                // Text input with enhanced styling
                TextField(appState.modelReady ? (screenReasoningEnabled ? "Ask about screen or anything..." : "Ask anything...") : "Loading model...", text: $userInput, axis: .vertical)
                    .focused($isTextFieldFocused)
                    .onChange(of: focusModel.focusTextField) { newValue, _ in
                        isTextFieldFocused = true
                        focusModel.focusTextField = false
                    }
                    .font(.body)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity) // Take all available space
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isTextFieldFocused ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                    )
                    .onSubmit {
                        if !isStreaming && appState.modelReady && !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            submitAction()
                        }
                    }
                    .disabled(!appState.modelReady || isStreaming)
                
                // Send/Stop button with modern design
                Button {
                    if isStreaming {
                        streamingTask?.cancel()
                        Task {
                            await stopGeneration()
                        }
                        isStreaming = false
                    } else {
                        if appState.modelReady && !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            submitAction()
                        }
                    }
                } label: {
                    Group {
                        if isStreaming {
                            Image(systemName: "stop.fill")
                                .foregroundStyle(.red)
                        } else if appState.modelReady && !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(.blue)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(isStreaming ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!appState.modelReady || (!isStreaming && userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 68) // Ensure consistent minimum height for input area
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
    
    
    // MARK: - Functions
    
    func submitDynamicIslandAction() {
        // Handle Dynamic Island specific message submission
        Task {
            do {
                // Ensure we have a valid chat session before proceeding
                if currentChatId == nil {
                    print("⚠️ No chat session available for Dynamic Island, creating one first...")
                    await createNewChatSession()
                }
                
                // Double-check we have a chat session
                guard currentChatId != nil else {
                    print("❌ Failed to create chat session for Dynamic Island, cannot proceed")
                    return
                }
                
                // Store current input before clearing
                let currentInput = userInput
                
                // Clear input immediately like ContentView does
                await MainActor.run {
                    userInput = ""
                    isStreaming = true
                    showDynamicIslandResponse = true
                    dynamicIslandResponse = "" // Clear previous response
                }
                
                // Choose appropriate streaming endpoint
                let stream: AsyncThrowingStream<String, Error>
                
                if personalityManager.hasPersonalities() {
                    if screenReasoningEnabled {
                        let screenAnalysis = await screenCaptureManager.analyzeScreenContent(userQuestion: currentInput, userID: userSettings.username, chatID: currentChatId ?? "")
                        let enhancedInput = """
                        \(currentInput)
                        
                        [ADVANCED_SCREEN_ANALYSIS]
                        \(screenAnalysis)
                        
                        Please provide a comprehensive response based on the screen analysis above and the user's question.
                        """
                        stream = try await streamChatResponseWithPersonality(userInput: enhancedInput, chatId: currentChatId, userId: userSettings.username, personalityManager: personalityManager, urgencyMode: memoryUrgencyMode)
                    } else {
                        stream = try await streamChatResponseWithPersonality(userInput: currentInput, chatId: currentChatId, userId: userSettings.username, personalityManager: personalityManager, urgencyMode: memoryUrgencyMode)
                    }
                } else {
                    if screenReasoningEnabled {
                        let screenAnalysis = await screenCaptureManager.analyzeScreenContent(userQuestion: currentInput, userID: userSettings.username, chatID: currentChatId ?? "")
                        let enhancedInput = """
                        \(currentInput)
                        
                        [ADVANCED_SCREEN_ANALYSIS]
                        \(screenAnalysis)
                        
                        Please provide a comprehensive response based on the screen analysis above and the user's question.
                        """
                        stream = try await streamChatResponseWithMemory(userInput: enhancedInput, chatId: currentChatId, userId: userSettings.username, urgencyMode: memoryUrgencyMode)
                    } else {
                        stream = try await streamChatResponseWithMemory(userInput: currentInput, chatId: currentChatId, userId: userSettings.username, urgencyMode: memoryUrgencyMode)
                    }
                }
                
                // Stream response into Dynamic Island (same pattern as ContentView)
                for try await chunk in stream {
                    let cleanChunk = chunk.replacingOccurrences(of: "<|eot_id|>", with: "")
                    if cleanChunk.isEmpty { continue }
                    
                    await MainActor.run {
                        dynamicIslandResponse += cleanChunk
                    }
                    
                    try await Task.sleep(nanoseconds: 5_000_000) // 5ms delay per chunk
                }
                
                await MainActor.run {
                    isStreaming = false
                }
                
                print("🏝️ Dynamic Island response completed")
                
            } catch {
                print("❌ Dynamic Island streaming failed:", error)
                await MainActor.run {
                    isStreaming = false
                    dynamicIslandResponse = "Sorry, there was an error. Please try again."
                }
            }
        }
    }
    
    func submitAction() {
        streamingTask = Task {
            do {
                // Ensure we have a valid chat session before proceeding
                if currentChatId == nil {
                    print("⚠️ No chat session available, creating lightweight session...")
                    // Create a lightweight session without cache initialization during message submission
                    await createLightweightChatSession()
                }
                
                // Double-check we have a chat session
                guard currentChatId != nil else {
                    print("❌ Failed to create chat session, cannot proceed")
                    return
                }
                
                loading = true
                isStreaming = true
                
                // Add user message
                let userMessage = ChatMessage(role: .user, content: userInput)
                messages.append(userMessage)
                displayedMessages.append(userMessage)
                
                // Update chat session title if this is the first message
                if messages.count == 1, let chatId = currentChatId {
                    Task {
                        await updateChatSessionTitle(chatId: chatId, firstMessage: userInput)
                    }
                }
                
                // Manage memory: keep displayed messages limited for performance
                if displayedMessages.count > maxVisibleMessages {
                    let keepCount = maxVisibleMessages - 2 // Keep space for user and AI response
                    displayedMessages = Array(displayedMessages.suffix(keepCount))
                    messages = displayedMessages // Keep them in sync
                    print("🧹 Auto-cleaned message cache during chat: keeping \(displayedMessages.count) recent messages")
                }
                
                response = ""
                
                // Store current input before clearing
                let currentInput = userInput
                
                // Choose endpoint based on screen reasoning mode and personality
                let stream: AsyncThrowingStream<String, Error>
                
                if personalityManager.hasPersonalities() {
                    // Use personality-aware chat endpoint
                    if screenReasoningEnabled {
                        // Add visual feedback for advanced screen analysis
                        let analysisMessage = ChatMessage(role: .ai, content: "🧠 Starting advanced screen intelligence analysis...")
                        messages.append(analysisMessage)
                        displayedMessages.append(analysisMessage)
                        
                        // Perform comprehensive screen analysis
                        let screenAnalysis = await screenCaptureManager.analyzeScreenContent(userQuestion: currentInput, userID: userSettings.username, chatID: currentChatId ?? "")
                        
                        // Create enhanced context with the analysis
                        let enhancedInput = """
                        \(currentInput)
                        
                        [ADVANCED_SCREEN_ANALYSIS]
                        \(screenAnalysis)
                        
                        Please provide a comprehensive response based on the screen analysis above and the user's question.
                        """
                        
                        // Remove the analysis message and replace with actual response
                        if let lastIndex = messages.lastIndex(where: { $0.role == .ai && $0.content.contains("🧠 Starting") }) {
                            messages.remove(at: lastIndex)
                            // Also remove from displayedMessages
                            if let displayedIndex = displayedMessages.lastIndex(where: { $0.role == .ai && $0.content.contains("🧠 Starting") }) {
                                displayedMessages.remove(at: displayedIndex)
                            }
                        }
                        
                        stream = try await streamChatResponseWithPersonality(userInput: enhancedInput, chatId: currentChatId, userId: userSettings.username, personalityManager: personalityManager, urgencyMode: memoryUrgencyMode)
                    } else {
                        stream = try await streamChatResponseWithPersonality(userInput: currentInput, chatId: currentChatId, userId: userSettings.username, personalityManager: personalityManager, urgencyMode: memoryUrgencyMode)
                    }
                } else {
                    // Fallback to regular memory-based chat
                    if screenReasoningEnabled {
                        // Add visual feedback for advanced screen analysis
                        let analysisMessage = ChatMessage(role: .ai, content: "🧠 Starting advanced screen intelligence analysis...")
                        messages.append(analysisMessage)
                        displayedMessages.append(analysisMessage)
                        
                        // Perform comprehensive screen analysis
                        let screenAnalysis = await screenCaptureManager.analyzeScreenContent(userQuestion: currentInput, userID: userSettings.username, chatID: currentChatId ?? "")
                        
                        // Create enhanced context with the analysis
                        let enhancedInput = """
                        \(currentInput)
                        
                        [ADVANCED_SCREEN_ANALYSIS]
                        \(screenAnalysis)
                        
                        Please provide a comprehensive response based on the screen analysis above and the user's question.
                        """
                        
                        // Remove the analysis message and replace with actual response
                        if let lastIndex = messages.lastIndex(where: { $0.role == .ai && $0.content.contains("🧠 Starting") }) {
                            messages.remove(at: lastIndex)
                            // Also remove from displayedMessages
                            if let displayedIndex = displayedMessages.lastIndex(where: { $0.role == .ai && $0.content.contains("🧠 Starting") }) {
                                displayedMessages.remove(at: displayedIndex)
                            }
                        }
                        
                        stream = try await streamChatResponseWithMemory(userInput: enhancedInput, chatId: currentChatId, userId: userSettings.username, urgencyMode: memoryUrgencyMode)
                    } else {
                        stream = try await streamChatResponseWithMemory(userInput: currentInput, chatId: currentChatId, userId: userSettings.username, urgencyMode: memoryUrgencyMode)
                    }
                }
                
                // Add placeholder AI message to update as chunks come in
                let aiMessage = ChatMessage(role: .ai, content: "")
                messages.append(aiMessage)
                displayedMessages.append(aiMessage)
                
                showResult = true
                let newHeight: CGFloat = showResult ? 500 : 120
                sizeUpdater.updateSize(to: CGSize(width: 600, height: newHeight))
                loading = false
                
                // Clear input
                userInput = ""
                
                var fullMessage = ""
                
                for try await chunk in stream {
                    let cleanChunk = chunk.replacingOccurrences(of: "<|eot_id|>", with: "")
                    if cleanChunk.isEmpty { continue }
                    
                    fullMessage += cleanChunk

                    // Faster streaming - update in chunks rather than character by character
                    await MainActor.run {
                        if let lastIndex = messages.lastIndex(where: { $0.role == .ai }) {
                            messages[lastIndex].content += cleanChunk
                        }
                        // Also update displayedMessages
                        if let displayedIndex = displayedMessages.lastIndex(where: { $0.role == .ai }) {
                            displayedMessages[displayedIndex].content += cleanChunk
                        }
                    }
                    response += cleanChunk
                    
                    // Smaller delay for faster streaming
                    try await Task.sleep(nanoseconds: 5_000_000) // 5ms delay per chunk
                }
                
                // Ensure streaming indicator is properly stopped
                await MainActor.run {
                    isStreaming = false
                }
                
                print("🔄 Streaming completed, indicator stopped")
                
                // If this was a new conversation, ensure we maintain session continuity
                if currentChatId == nil {
                    // For new conversations, we need to get the chat_id from the backend
                    // The backend should create a session automatically, but we need to track it
                    await loadChatSessions()
                    if let latestSession = chatSessions.first {
                        currentChatId = latestSession.id
                        print("✅ New conversation created with chat_id: \(latestSession.id)")
                    }
                } else {
                    print("✅ Continuing conversation with chat_id: \(currentChatId!)")
                }
                
                // Reload memory stats and chat sessions
                await loadMemoryStats()
                await loadChatSessions()
                
            } catch {
                print("Streaming failed:", error)
                await MainActor.run {
                    showResult = true
                    loading = false
                    isStreaming = false
                    
                    let newHeight: CGFloat = showResult ? 500 : 120
                    sizeUpdater.updateSize(to: CGSize(width: 600, height: newHeight))
                    
                    let errorMessage = ChatMessage(role:.ai, content:"Streaming failed - please try again...")
                    messages.append(errorMessage)
                    displayedMessages.append(errorMessage)
                }
                print("🔄 Streaming failed, indicator stopped")
            }
        }
    }
    
    func focusInput() {
        isTextFieldFocused = true
    }
    
    func loadChatSessions() async {
        // Implementation to load chat sessions from backend
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
    
    func updateChatSessionTitle(chatId: String, firstMessage: String) async {
        // Update chat session title with the first user message
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/chat_sessions/\(chatId)/update_title")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = ["first_message": firstMessage]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ Updated chat session title: '\(firstMessage.prefix(50))...'")
                // Reload chat sessions to reflect the title change
                await loadChatSessions()
            } else {
                print("⚠️ Failed to update chat session title")
            }
        } catch {
            print("❌ Error updating chat session title: \(error)")
        }
    }
    
    func loadMemoryStats() async {
        // Implementation to load memory statistics from backend
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/statistics/\(userSettings.username)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(MemoryStatsResponse.self, from: data)
            await MainActor.run {
                memoryStats = response.statistics
            }
        } catch {
            print("Failed to load memory stats: \(error)")
        }
    }
    
    // MARK: - Paginated Message Loading
    func loadMoreMessages() async {
        guard !isLoadingOlderMessages && hasMoreMessages else { return }
        
        await MainActor.run {
            isLoadingOlderMessages = true
        }
        
        // Calculate offset based on currently displayed messages
        let offset = displayedMessages.count
        
        await loadMessagesPage(offset: offset, limit: messagesPerPage)
        
        await MainActor.run {
            // Implement memory management - keep only recent messages for performance
            if displayedMessages.count > maxVisibleMessages {
                // Keep the most recent messages and some older ones for context
                let keepFromEnd = maxVisibleMessages - 5  // Keep last 15 messages
                let keepFromStart = 5  // Keep first 5 messages for context
                
                if displayedMessages.count > keepFromEnd + keepFromStart {
                    let endMessages = Array(displayedMessages.suffix(keepFromEnd))
                    let startMessages = Array(displayedMessages.prefix(keepFromStart))
                    displayedMessages = startMessages + endMessages
                    
                    print("🧹 Cleaned up message cache: keeping \(displayedMessages.count) messages for performance")
                }
            }
            
            isLoadingOlderMessages = false
        }
    }
    
    func loadMessagesPage(offset: Int, limit: Int) async {
        guard let chatId = currentChatId else { return }
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/chat_sessions/\(userSettings.username)/\(chatId)/history?offset=\(offset)&limit=\(limit)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode([String: [ChatHistoryMessage]].self, from: data)
            
            await MainActor.run {
                if let history = response["history"] {
                    let newMessages = history.map { historyMessage in
                        ChatMessage(
                            role: historyMessage.role == "human" ? .user : .ai,
                            content: historyMessage.content
                        )
                    }
                    
                    // If we received fewer messages than requested, we've reached the end
                    if newMessages.count < limit {
                        hasMoreMessages = false
                    }
                    
                    // Insert older messages at the beginning
                    displayedMessages.insert(contentsOf: newMessages, at: 0)
                    
                    print("📄 Loaded \(newMessages.count) older messages (offset: \(offset), total: \(displayedMessages.count))")
                }
            }
        } catch {
            print("Failed to load message page: \(error)")
            await MainActor.run {
                hasMoreMessages = false  // Stop trying if there's an error
            }
        }
    }
    
    func selectChatSession(_ sessionId: String) async {
        // Load messages for the selected chat session (initial load - most recent messages)
        await MainActor.run {
            currentChatId = sessionId
            messages.removeAll()
            displayedMessages.removeAll()
            hasMoreMessages = true
            isLoadingOlderMessages = false
        }
        
        // Load first page of recent messages (only most recent for performance)
        await loadMessagesPage(offset: 0, limit: messagesPerPage)
        
        await MainActor.run {
            // Keep messages array minimal for compatibility - just copy the displayed ones
            messages = displayedMessages
            print("💾 Initialized with \(displayedMessages.count) recent messages for performance")
            
            // Show the chat area if there are messages
            if !displayedMessages.isEmpty {
                showResult = true
                let newHeight: CGFloat = 500
                sizeUpdater.updateSize(to: CGSize(width: 600, height: newHeight))
            }
        }
        
        // Fallback: if pagination failed, load recent messages only (not all history for performance)
        if displayedMessages.isEmpty {
            do {
                let url = URL(string: "\(serverConfig.currentServerURL)/chat_sessions/\(userSettings.username)/\(sessionId)/history")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode([String: [ChatHistoryMessage]].self, from: data)
                
                await MainActor.run {
                    if let history = response["history"] {
                        // Only load the most recent messages for performance
                        let recentHistory = Array(history.suffix(maxVisibleMessages))
                        
                        for historyMessage in recentHistory {
                            let role: ChatMessage.Role = historyMessage.role == "human" ? .user : .ai
                            let message = ChatMessage(role: role, content: historyMessage.content)
                            displayedMessages.append(message)
                            messages.append(message)
                        }
                        
                        // Set hasMoreMessages if we truncated the history
                        hasMoreMessages = history.count > maxVisibleMessages
                        
                        print("💾 Fallback: Loaded \(recentHistory.count) recent messages (of \(history.count) total) for performance")
                    } else {
                        print("⚠️ No history found for chat \(sessionId)")
                        hasMoreMessages = false
                    }
                    
                    // Always show the chat area when selecting a session
                    showResult = true
                    let newHeight: CGFloat = 500
                    sizeUpdater.updateSize(to: CGSize(width: 600, height: newHeight))
                    
                    print("✅ Chat session \(sessionId) selected, showing \(displayedMessages.count) messages")
                }
            } catch {
                print("❌ Failed to load chat history: \(error)")
                await MainActor.run {
                    // Still set the chat ID and show the interface for new conversation
                    currentChatId = sessionId
                    messages.removeAll()
                    displayedMessages.removeAll()
                    hasMoreMessages = false
                    showResult = true
                    let newHeight: CGFloat = 500
                    sizeUpdater.updateSize(to: CGSize(width: 600, height: newHeight))
                }
            }
        }
    }
    
    func deleteChatSession(_ sessionId: String) async {
        // Delete the chat session from backend
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/chat_session/\(sessionId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                await MainActor.run {
                    // Remove from local list
                    chatSessions.removeAll { $0.id == sessionId }
                    
                    // If this was the current session, clear it
                    if currentChatId == sessionId {
                        currentChatId = nil
                        messages.removeAll()
                        displayedMessages.removeAll()
                        hasMoreMessages = false
                        showResult = false
                        sizeUpdater.updateSize(to: CGSize(width: 600, height: 120))
                    }
                }
            }
        } catch {
            print("Failed to delete chat session: \(error)")
        }
    }
    
    func continueOrCreateChatSession() async {
        // Check if we have recent chat sessions to continue
        if !chatSessions.isEmpty {
            // Find the most recent session (first in list)
            let mostRecentSession = chatSessions[0]
            
            print("🔄 Continuing previous chat session: \(mostRecentSession.id)")
            
            // Continue with the most recent session
            await selectChatSession(mostRecentSession.id)
            
            // Only initialize cache if UI is not already visible (not in dynamic island or overlay mode)
            if !dynamicPlacementManager.isDynamicModeEnabled && !overlayManager.isOverlayVisible {
                await initializeCacheForSession(mostRecentSession.id)
            } else {
                print("⚡ Skipping cache initialization - UI is visible (Dynamic Island or overlay active)")
            }
        } else {
            print("📝 No previous sessions found, creating new chat session")
            await createNewChatSession()
        }
    }
    
    func initializeCacheForSession(_ sessionId: String) async {
        // Cache warmup disabled - using smart memory system instead
        print("💡 Cache warmup disabled - smart memory system handles optimization")
        
        await MainActor.run {
            isCacheInitializing = false
        }
    }
    
    func createLightweightChatSession() async {
        // Create a session without cache initialization for immediate use during message submission
        let tempChatId = UUID().uuidString
        
        await MainActor.run {
            currentChatId = tempChatId
            print("⚡ Created lightweight session: \(tempChatId) (no cache initialization)")
        }
        
        // Background session creation (optional)
        Task.detached {
            do {
                let url = URL(string: "\(serverConfig.currentServerURL)/chat/initialize")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let requestBody = await [
                    "user_id": userSettings.username,
                    "chat_id": "",  // Empty chat_id will create new session
                    "message": "",  // Empty message for initialization
                    "urgency_mode": "normal"
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let responseData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let realChatId = responseData["chat_id"] as? String {
                        
                        await MainActor.run {
                            if currentChatId == tempChatId {
                                currentChatId = realChatId
                                print("✅ Lightweight session upgraded: \(tempChatId) → \(realChatId)")
                            }
                        }
                    }
                }
            } catch {
                print("⚠️ Background session creation failed, continuing with temporary ID")
            }
        }
    }
    
    func createNewChatSession() async {
        // Generate a temporary chat ID for immediate UI feedback
        let tempChatId = UUID().uuidString
        let newChatTitle = "New Chat \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
        
        // IMMEDIATE UI UPDATE - Don't wait for backend
        await MainActor.run {
            currentChatId = tempChatId
            messages.removeAll()
            displayedMessages.removeAll()
            hasMoreMessages = false  // New chat has no history to load
            showResult = false
            isCacheInitializing = true  // Show cache initialization indicator
            sizeUpdater.updateSize(to: CGSize(width: 600, height: 120))
            
            print("🚀 Created temporary chat session: \(tempChatId) (backend processing...)")
        }
        
        // BACKGROUND BACKEND PROCESSING - Non-blocking
        Task.detached {
            do {
                let url = URL(string: "\(serverConfig.currentServerURL)/chat/initialize")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let requestBody = await [
                    "user_id": userSettings.username,
                    "chat_id": "",  // Empty chat_id will create new session
                    "message": "",  // Empty message for initialization
                    "urgency_mode": "normal"
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let responseData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let realChatId = responseData["chat_id"] as? String {
                        
                        await MainActor.run {
                            // Replace temporary ID with real ID from backend
                            if currentChatId == tempChatId {
                                currentChatId = realChatId
                                isCacheInitializing = false  // Cache initialization complete
                                print("✅ Backend completed: Replaced temp ID \(tempChatId) with real ID \(realChatId)")
                            }
                        }
                        
                        // Background reload of chat sessions (non-blocking)
                        await loadChatSessions()
                        
                        print("🎯 Chat session fully initialized with cache pre-loading")
                    }
                } else {
                    print("⚠️ Backend chat session creation failed, keeping temporary session")
                    await MainActor.run {
                        isCacheInitializing = false  // Clear flag even on failure
                    }
                }
            } catch {
                print("❌ Backend error during chat session creation: \(error)")
                print("💡 Continuing with temporary session for user experience")
                await MainActor.run {
                    isCacheInitializing = false  // Clear flag on error
                }
            }
        }
    }
    
    // MARK: - Memory Urgency Mode Helper Functions
    
    private func urgencyModeIcon(_ mode: String) -> String {
        switch mode {
        case "instant":
            return "bolt.fill"
        case "normal":
            return "scale.3d"
        case "comprehensive":
            return "magnifyingglass.circle.fill"
        default:
            return "scale.3d"
        }
    }
    
    private func urgencyModeColor(_ mode: String) -> Color {
        switch mode {
        case "instant":
            return .yellow
        case "normal":
            return .green
        case "comprehensive":
            return .purple
        default:
            return .green
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
    
    // MARK: - Urgency Mode Selector View
    
    var urgencyModeSelector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Memory Retrieval Mode")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                UrgencyModeOption(
                    mode: "instant",
                    title: "Instant",
                    description: "Ultra-fast retrieval (< 30ms)",
                    icon: "bolt.fill",
                    color: .yellow,
                    isSelected: memoryUrgencyMode == "instant"
                ) {
                    memoryUrgencyMode = "instant"
                    showUrgencyModeSelector = false
                }
                
                UrgencyModeOption(
                    mode: "normal", 
                    title: "Normal",
                    description: "Balanced speed & relevance (< 100ms)",
                    icon: "scale.3d",
                    color: .green,
                    isSelected: memoryUrgencyMode == "normal"
                ) {
                    memoryUrgencyMode = "normal"
                    showUrgencyModeSelector = false
                }
                
                UrgencyModeOption(
                    mode: "comprehensive",
                    title: "Comprehensive", 
                    description: "Deep semantic search (< 300ms)",
                    icon: "magnifyingglass.circle.fill",
                    color: .purple,
                    isSelected: memoryUrgencyMode == "comprehensive"
                ) {
                    memoryUrgencyMode = "comprehensive"
                    showUrgencyModeSelector = false
                }
            }
            
            Text("Choose how quickly you need memory retrieval vs. how comprehensive the search should be.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .padding(16)
        .frame(width: 280)
    }
}

// MARK: - Urgency Mode Option Component

struct UrgencyModeOption: View {
    let mode: String
    let title: String
    let description: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? color.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? color.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// ChatSessionRow is defined in ChatHistoryPanel.swift

// Updated DotLoader and other existing components remain the same...
//struct DotLoader: View {
//    @State private var isAnimating = false
//
//    var body: some View {
//        HStack(spacing: 1) {
//            ForEach(0..<3) { index in
//                Circle()
//                    .frame(width: 10, height: 10)
//                    .scaleEffect(isAnimating ? 0.4 : 0.7)
//                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: isAnimating)
//            }
//        }
//        .onAppear { isAnimating = true }
//    }
//}

struct LoadingModel: View {
    var body: some View {
        HStack{
            Text("Loading Model ")
                .fontWeight(.medium)
            DotLoader()
        }
    }
}

class FocusModel: ObservableObject {
    @Published var focusTextField: Bool = false
}

// MARK: - Search Dialog View
struct SearchDialogView: View {
    @Binding var userInput: String
    let onSearch: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    
                    Text("Search & Ask")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Button {
                        
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("Enter your search query or question")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 12) {
                TextField("Search the web or ask anything...", text: $searchText, axis: .vertical)
                    .focused($isSearchFocused)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSearchFocused ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                    )
                    .onSubmit {
                        performSearch()
                    }
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("Search") {
                        performSearch()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            // Quick search suggestions
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick searches:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach([
                        "Latest tech news",
                        "Weather today",
                        "Stock market updates",
                        "AI developments"
                    ], id: \.self) { suggestion in
                        Button {
                            searchText = suggestion
                        } label: {
                            Text(suggestion)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Material.ultraThin)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            isSearchFocused = true
        }
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        userInput = searchText
        onSearch()
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String

    enum Role {
        case user
        case ai
    }
}

struct RichTextView: NSViewRepresentable {
    let attributedString: AttributedString
    
    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        return textView
    }
    
    func updateNSView(_ nsView: NSTextView, context: Context) {
        nsView.textStorage?.setAttributedString(NSAttributedString(attributedString))
    }
}


//#Preview(){
//    ContentView(dismiss: {})
//        .environmentObject(FocusModel())
//}

//#Preview(){
//
//}
