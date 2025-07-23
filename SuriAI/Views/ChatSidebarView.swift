//
//  ChatSidebarView.swift
//  SuriAI
//
//  Created by Claude on 01/07/25.
//

import SwiftUI

struct ChatSidebarView: View {
    let chatSessions: [ChatSession]
    let currentChatId: String?
    let showChatHistory: Bool
    let showResult: Bool
    
    let onSelectSession: (String) -> Void
    let onDeleteSession: (String) -> Void
    let onCreateNewChat: () -> Void
    let onCloseSidebar: () -> Void
    
    @EnvironmentObject var sizeUpdater: WindowSizeUpdater
    
    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(
                onClose: onCloseSidebar,
                showResult: showResult,
                sizeUpdater: sizeUpdater
            )
            
            Divider()
            
            SessionsList(
                chatSessions: chatSessions,
                currentChatId: currentChatId,
                onSelectSession: onSelectSession,
                onDeleteSession: onDeleteSession
            )
            
            Spacer()
            
            NewChatButton(action: onCreateNewChat)
        }
        .frame(width: 200)
        .background(Material.ultraThin)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Color.black.opacity(0.1)),
            alignment: .leading
        )
    }
}

struct SidebarHeader: View {
    let onClose: () -> Void
    let showResult: Bool
    let sizeUpdater: WindowSizeUpdater
    
    var body: some View {
        HStack {
            Text("Chat History")
                .font(.headline.bold())
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    onClose()
                    sizeUpdater.updateSize(to: CGSize(width: 600, height: showResult ? 500 : 120))
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.02))
    }
}

struct SessionsList: View {
    let chatSessions: [ChatSession]
    let currentChatId: String?
    let onSelectSession: (String) -> Void
    let onDeleteSession: (String) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(chatSessions) { session in
                    ChatSessionRow(
                        session: session,
                        isSelected: session.id == currentChatId,
                        onSelect: {
                            onSelectSession(session.id)
                        },
                        onDelete: {
                            onDeleteSession(session.id)
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct NewChatButton: View {
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                Image(systemName: "plus")
                Text("New Chat")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}