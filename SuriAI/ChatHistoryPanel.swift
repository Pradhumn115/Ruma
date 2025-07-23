import SwiftUI
import Foundation

// MARK: - Data Models
struct ChatSession: Identifiable, Codable {
    let id: String
    let title: String
    let created_at: String
    let updated_at: String
    let message_count: Int
    
    var formattedDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if let date = dateFormatter.date(from: updated_at) {
            let displayFormatter = DateFormatter()
            if Calendar.current.isDateInToday(date) {
                displayFormatter.dateFormat = "HH:mm"
                return "Today " + displayFormatter.string(from: date)
            } else if Calendar.current.isDateInYesterday(date) {
                displayFormatter.dateFormat = "HH:mm"
                return "Yesterday " + displayFormatter.string(from: date)
            } else {
                displayFormatter.dateFormat = "MMM d"
                return displayFormatter.string(from: date)
            }
        }
        return updated_at
    }
}

struct ChatSessionsResponse: Codable {
    let sessions: [ChatSession]
}

struct ChatHistoryMessage: Identifiable, Codable {
    let id = UUID()
    let role: String
    let content: String
    
    enum CodingKeys: String, CodingKey {
        case role, content
    }
}

struct ChatHistoryResponse: Codable {
    let history: [ChatHistoryMessage]
}

// MARK: - Chat History Manager
class ChatHistoryManager: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var currentSession: ChatSession?
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    private var baseURL: String {
        return serverConfig.currentServerURL
    }
    
    func loadSessions(for userId: String) async {
        await MainActor.run { isLoading = true }
        
        guard let url = URL(string: "\(baseURL)/chat_sessions/\(userId)") else {
            await MainActor.run {
                errorMessage = "Invalid URL"
                isLoading = false
            }
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ChatSessionsResponse.self, from: data)
            
            await MainActor.run {
                sessions = response.sessions
                isLoading = false
                errorMessage = ""
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load sessions: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    func createSession(for userId: String, title: String? = nil) async -> String? {
        guard let url = URL(string: "\(baseURL)/chat_session") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "user_id": userId,
            "title": title ?? generateDefaultChatTitle()
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let chatId = response["chat_id"] as? String {
                // Reload sessions to show the new one
                await loadSessions(for: userId)
                return chatId
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to create session: \(error.localizedDescription)"
            }
        }
        
        return nil
    }
    
    private func generateDefaultChatTitle() -> String {
        let currentTime = Date()
        let formatter = DateFormatter()
        
        let hour = Calendar.current.component(.hour, from: currentTime)
        let dayOfWeek = formatter.weekdaySymbols[Calendar.current.component(.weekday, from: currentTime) - 1]
        
        let timeOfDay: String
        switch hour {
        case 5..<12:
            timeOfDay = "Morning"
        case 12..<17:
            timeOfDay = "Afternoon"
        case 17..<21:
            timeOfDay = "Evening"
        default:
            timeOfDay = "Night"
        }
        
        let topics = [
            "Chat", "Conversation", "Discussion", "Questions", "Session", 
            "Inquiry", "Meeting", "Talk", "Dialogue", "Exchange"
        ]
        
        let randomTopic = topics.randomElement() ?? "Chat"
        
        // Generate contextual titles
        let titleOptions = [
            "\(timeOfDay) \(randomTopic)",
            "\(dayOfWeek) \(randomTopic)",
            "\(timeOfDay) \(dayOfWeek)",
            "Quick \(randomTopic)",
            "New \(randomTopic)"
        ]
        
        return titleOptions.randomElement() ?? "New Chat"
    }
    
    func deleteSession(_ sessionId: String, userId: String) async {
        guard let url = URL(string: "\(baseURL)/chat_session/\(sessionId)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        do {
            let (_, _) = try await URLSession.shared.data(for: request)
            await loadSessions(for: userId)
        } catch {
            await MainActor.run {
                errorMessage = "Failed to delete session: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Chat History Panel View
struct ChatHistoryPanel: View {
    @StateObject private var historyManager = ChatHistoryManager()
    @State private var userId = "default_user" // You can make this dynamic
    @State private var showingNewChatDialog = false
    @State private var newChatTitle = ""
    @Binding var isPresented: Bool
    @Binding var selectedChatId: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Modern Header with Close Button
            HStack(spacing: 16) {
                // Close Button
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .background(Color.clear)
                }
                .buttonStyle(.plain)
                .help("Close")
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat History")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("\(historyManager.sessions.count) conversations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // New Chat Button
                Button {
                    showingNewChatDialog = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("New")
                    }
                    .font(.callout)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Start new conversation")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(Color(.controlBackgroundColor).opacity(0.3))
            
            // Content Area
            if historyManager.isLoading {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading conversations...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else if historyManager.sessions.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 56))
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    VStack(spacing: 8) {
                        Text("No conversations yet")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Start a new chat to begin your conversation history")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Button {
                        showingNewChatDialog = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Start New Chat")
                        }
                        .font(.callout)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.controlBackgroundColor).opacity(0.1))
                
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(historyManager.sessions) { session in
                            ChatSessionRow(
                                session: session,
                                isSelected: selectedChatId == session.id,
                                onSelect: {
                                    selectedChatId = session.id
                                    historyManager.currentSession = session
                                    isPresented = false // Close panel after selection
                                },
                                onDelete: {
                                    Task {
                                        await historyManager.deleteSession(session.id, userId: userId)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .background(Color(.controlBackgroundColor).opacity(0.1))
            }
            
            // Error Message (if any)
            if !historyManager.errorMessage.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    Text(historyManager.errorMessage)
                        .font(.callout)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button("Dismiss") {
                        historyManager.errorMessage = ""
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 380, height: 520)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
        .onAppear {
            Task {
                await historyManager.loadSessions(for: userId)
            }
        }
        .sheet(isPresented: $showingNewChatDialog) {
            NewChatDialog(
                title: $newChatTitle,
                onCreate: {
                    Task {
                        if let chatId = await historyManager.createSession(for: userId, title: newChatTitle.isEmpty ? nil : newChatTitle) {
                            selectedChatId = chatId
                        }
                        newChatTitle = ""
                        showingNewChatDialog = false
                    }
                },
                onCancel: {
                    newChatTitle = ""
                    showingNewChatDialog = false
                }
            )
        }
    }
}

// MARK: - Chat Session Row
struct ChatSessionRow: View {
    let session: ChatSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Chat Icon
            Image(systemName: isSelected ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .white : .blue)
                .frame(width: 20)
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundColor(isSelected ? .white : .primary)
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "message")
                            .font(.system(size: 10))
                        Text("\(session.message_count)")
                            .font(.caption2)
                    }
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    
                    Spacer()
                    
                    Text(session.formattedDate)
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            
            Spacer()
            
            // Actions
            if isHovering && !isSelected {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.red.opacity(0.8))
                        .background(Color.white, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Delete conversation")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? 
                    Color.blue : 
                    (isHovering ? Color(.controlBackgroundColor).opacity(0.8) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - New Chat Dialog
struct NewChatDialog: View {
    @Binding var title: String
    let onCreate: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                
                Text("New Conversation")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Start a fresh chat with personalized memory")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Input Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Title (Optional)")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                TextField("Enter a descriptive title...", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .padding(.horizontal, 4)
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                
                Spacer()
                
                Button("Create Chat") {
                    onCreate()
                }
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(8)
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 340)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
    }
}

// MARK: - Preview
#Preview {
    ChatHistoryPanel(
        isPresented: .constant(true),
        selectedChatId: .constant(nil)
    )
}
