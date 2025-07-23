//
//  ChatMessagesView.swift
//  SuriAI
//
//  Created by Claude on 01/07/25.
//

import SwiftUI

struct ChatMessagesView: View {
    let messages: [ChatMessage]
    let loading: Bool
    let isStreaming: Bool
    let showResult: Bool
    let response: String
    let userInput: String
    let submitAction: () -> Void
    let loadMoreMessages: () -> Void
    let isLoadingOlderMessages: Bool
    let hasMoreMessages: Bool
    
    @ObservedObject var personalityManager: PersonalityManager
    
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                if loading && messages.isEmpty {
                    LoadingStateView()
                } else if messages.isEmpty {
                    EmptyStateView(
                        userInput: userInput,
                        submitAction: submitAction
                    )
                } else {
                    MessagesListView(
                        messages: messages,
                        isStreaming: isStreaming,
                        personalityManager: personalityManager,
                        loadMoreMessages: loadMoreMessages,
                        isLoadingOlderMessages: isLoadingOlderMessages,
                        hasMoreMessages: hasMoreMessages
                    )
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
    }
}

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            DotLoader()
            Text("Preparing AI...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct EmptyStateView: View {
    let userInput: String
    let submitAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("Ready to assist")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                
                Text("Advanced AI with memory capabilities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            SuggestionGridView(submitAction: submitAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct SuggestionGridView: View {
    let submitAction: () -> Void
    @State private var userInput: String = ""
    
    private let suggestions = [
        "Remember my name",
        "Search latest news",
        "Explain quantum physics",
        "Help with coding"
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Try asking:")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        // This would need to be passed through properly
                        // For now, just trigger the action
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
}

struct MessagesListView: View {
    let messages: [ChatMessage]
    let isStreaming: Bool
    @ObservedObject var personalityManager: PersonalityManager
    let loadMoreMessages: () -> Void
    let isLoadingOlderMessages: Bool
    let hasMoreMessages: Bool
    
    var body: some View {
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
                            loadMoreMessages()
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
                    if !isLoadingOlderMessages {
                        loadMoreMessages()
                    }
                }
            }
            
            ForEach(messages) { message in
                MessageBubble(message: message, personalityManager: personalityManager)
                    .id(message.id)
            }
            
            // Loading indicator for streaming
            if isStreaming {
                StreamingIndicatorView()
                    .id("thinking-indicator")
            }
        }
        .padding(.vertical, 16)
    }
}

struct StreamingIndicatorView: View {
    var body: some View {
        HStack {
            DotLoader()
            Text("AI is thinking...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}