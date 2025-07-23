//
//  MemoryManagementView.swift
//  SuriAI - Comprehensive Memory Management Interface
//
//  Created by Claude on 03/07/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MemoryManagementView: View {
    @StateObject private var memoryManager = MemoryManager.shared
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var selectedMemoryType = "All"
    @State private var selectedUrgencyMode = "normal"
    @State private var showDeleteConfirmation = false
    @State private var selectedMemoryIds: Set<String> = []
    @State private var showAddMemorySheet = false
    @State private var newMemoryContent = ""
    @State private var newMemoryType = "fact"
    @State private var newMemoryImportance = 0.5
    @State private var newMemoryCategory = ""
    @State private var backendHealthStatus: BackendHealthStatus = .unknown
    @State private var expandedProfiles: Set<String> = [] // Track expanded profile IDs
    @State private var showImportSheet = false
    @State private var importResult: String = ""
    @State private var showImportResult = false
    @State private var currentPage = 0
    @State private var isLoadingMore = false
    @State private var hasMoreMemories = true
    @State private var allMemories: [MemoryEntry] = []
    @State private var showResetConfirmation = false
    @State private var showOptimizationResults = false
    @State private var optimizationResults: OptimizationResults? = nil
    
    enum BackendHealthStatus {
        case healthy, unhealthy, unknown
        
        var color: Color {
            switch self {
            case .healthy: return .green
            case .unhealthy: return .red
            case .unknown: return .orange
            }
        }
        
        var text: String {
            switch self {
            case .healthy: return "Online"
            case .unhealthy: return "Offline"
            case .unknown: return "Checking..."
            }
        }
    }
    
    private let memoryTypes = [
        "All", "fact", "preference", "pattern", "skill", "goal", "event", 
        "emotional", "temporal", "context", "meta", "social", "procedural",
        "working", "learning", "personal", "technical", "conversation", 
        "insight", "reminder", "note", "task", "observation", "reflection",
        "knowledge", "experience", "habit", "memory"
    ]
    private let urgencyModes = ["instant", "normal", "comprehensive"]
    
    private let memoryTypeColors: [String: Color] = [
        // Core memory types
        "fact": .blue,
        "preference": .green,
        "pattern": .orange,
        "skill": .purple,
        "goal": .red,
        "event": .cyan,
        "emotional": .pink,
        "temporal": .mint,
        "context": .brown,
        "meta": .indigo,
        "social": .teal,
        "procedural": .gray,
        
        // Additional memory types that might appear
        "working": Color.blue.opacity(0.7),
        "learning": Color.purple.opacity(0.7),
        "personal": Color.green.opacity(0.7),
        "technical": Color.orange.opacity(0.7),
        "conversation": Color.cyan.opacity(0.7),
        "insight": Color.yellow,
        "reminder": Color.red.opacity(0.7),
        "note": Color.gray.opacity(0.7),
        "task": Color.indigo.opacity(0.7),
        "observation": Color.mint.opacity(0.7),
        "reflection": Color.pink.opacity(0.7),
        "knowledge": Color.blue.opacity(0.8),
        "experience": Color.brown.opacity(0.7),
        "habit": Color.teal.opacity(0.7),
        "memory": Color.secondary
    ]
    
    private let urgencyModeColors: [String: Color] = [
        "instant": .red,
        "normal": .blue,
        "comprehensive": .green
    ]
    
    private let urgencyModeDescriptions: [String: String] = [
        "instant": "Fast retrieval (<30ms) - SQL only",
        "normal": "Balanced speed/quality (<100ms) - SQL + basic vector",
        "comprehensive": "Best quality (<300ms) - Full semantic search"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Tab Selection
            tabSelectionView
            
            // Content based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    overviewTab
                        .transition(.opacity)
                case 1:
                    memoriesTab
                        .transition(.opacity)
                case 2:
                    insightsTab
                        .transition(.opacity)
                case 3:
                    profilesTab
                        .transition(.opacity)
                case 4:
                    settingsTab
                        .transition(.opacity)
                default:
                    overviewTab
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
        }
        .background(.ultraThinMaterial)
        .onAppear {
            Task {
                await memoryManager.loadAllMemoryData()
            }
        }
        .sheet(isPresented: $showAddMemorySheet) {
            addMemorySheet
        }
        .sheet(isPresented: $showImportSheet) {
            importMemoriesSheet
        }
        .sheet(isPresented: $showOptimizationResults) {
            optimizationResultsSheet
        }
        .alert("Delete Memories", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    let success = await memoryManager.deleteMemories(
                        memoryIds: Array(selectedMemoryIds)
                    )
                    if success {
                        // Remove deleted memories from local array
                        allMemories.removeAll { memory in
                            selectedMemoryIds.contains(memory.id)
                        }
                        selectedMemoryIds.removeAll()
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete \(selectedMemoryIds.count) selected memories? This action cannot be undone.")
        }
        .alert("Import Result", isPresented: $showImportResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importResult)
        }
        .alert("Reset All Memories", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset All", role: .destructive) {
                Task {
                    let success = await memoryManager.deleteMemories()
                    if success {
                        allMemories.removeAll()
                        selectedMemoryIds.removeAll()
                        // Reset pagination
                        currentPage = 0
                        hasMoreMemories = true
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete ALL memories from both SQL and vector databases? This action cannot be undone and will permanently remove all stored memories for all users.")
        }
    }
    
    // MARK: - Header View
    
    var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Memory Management")
                    .font(.title.bold())
                    .foregroundColor(.primary)
                
                Text("Manage your AI's long-term memory and personalization")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // Refresh Button
                Button {
                    Task {
                        await memoryManager.loadAllMemoryData()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(memoryManager.isLoading)
                
                // Add Memory Button
                Button {
                    showAddMemorySheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.green)
                        .frame(width: 32, height: 32)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Tab Selection View
    
    var tabSelectionView: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { index in
                let titles = ["Overview", "Memories", "Insights", "Profiles", "Settings"]
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = index
                    }
                } label: {
                    Text(titles[index])
                        .font(.system(size: 13, weight: selectedTab == index ? .medium : .regular))
                        .foregroundColor(selectedTab == index ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == index ? Color.blue : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Overview Tab
    
    var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if memoryManager.isLoading {
                    loadingView
                } else {
                    statisticsSection
                    memoryTypesBreakdown
                    quickActionsSection
                }
            }
            .padding(20)
        }
    }
    
    var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Memory Statistics")
                .font(.headline.bold())
                .foregroundColor(.primary)
            
            if let stats = memoryManager.memoryStatistics {
                // Main Statistics Row
                HStack(spacing: 16) {
                    StatCard(
                        title: "Total Memories",
                        value: "\(stats.total_memories)",
                        icon: "brain.head.profile",
                        color: .blue
                    )
                    
                    StatCard(
                        title: "Total Tokens",
                        value: "\(stats.total_tokens)",
                        icon: "textformat.abc",
                        color: .green
                    )
                    
                    StatCard(
                        title: "Combined Size",
                        value: formatBytes(stats.displaySize),
                        icon: "internaldrive",
                        color: .orange
                    )
                    
                    StatCard(
                        title: "Avg Importance",
                        value: String(format: "%.1f%%", stats.avg_importance * 100),
                        icon: "star.fill",
                        color: .yellow
                    )
                    
                    StatCard(
                        title: "Memory Types",
                        value: "\(stats.memory_types_count)",
                        icon: "folder.fill",
                        color: .purple
                    )
                    
                    StatCard(
                        title: "Last Updated",
                        value: formatDate(stats.timestamp),
                        icon: "clock.fill",
                        color: .secondary
                    )
                }
                
                // Database Breakdown Section
                if stats.sql_database != nil || stats.vector_database != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Database Breakdown")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 16) {
                            // SQL Database Stats
                            if let sqlDB = stats.sql_database {
                                DatabaseStatCard(
                                    title: "SQL Database",
                                    size: formatBytes(sqlDB.size_bytes),
                                    memoryCount: sqlDB.memory_count,
                                    icon: "cylinder.fill",
                                    color: .blue
                                )
                            }
                            
                            // Vector Database Stats
                            if let vectorDB = stats.vector_database {
                                DatabaseStatCard(
                                    title: "Vector Database",
                                    size: formatBytes(vectorDB.vector_size_bytes),
                                    memoryCount: vectorDB.embedding_count,
                                    icon: "grid.circle.fill",
                                    color: .purple,
                                    additionalInfo: "\(vectorDB.collection_count) collections"
                                )
                            }
                            
                            Spacer()
                        }
                    }
                }
            } else {
                Text("No memory statistics available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    var memoryTypesBreakdown: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Memory Types Breakdown")
                .font(.headline.bold())
                .foregroundColor(.primary)
            
            if let stats = memoryManager.memoryStatistics {
                VStack(spacing: 12) {
                    ForEach(Array(stats.type_breakdown.keys.sorted()), id: \.self) { type in
                        if let typeStats = stats.type_breakdown[type], typeStats.count > 0 {
                            MemoryTypeRow(
                                type: type,
                                count: typeStats.count,
                                tokens: typeStats.tokens,
                                color: getColorForMemoryType(type)
                            )
                        }
                    }
                }
                
                // Debug information (can be removed in production)
                if stats.type_breakdown.isEmpty {
                    Text("Debug: type_breakdown is empty")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("Debug: Found \(stats.type_breakdown.count) memory types")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No memory type data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline.bold())
                .foregroundColor(.primary)
            
            HStack(spacing: 16) {
                MemoryActionButton(
                    title: "Optimize Memory",
                    subtitle: "Comprehensive dual-database optimization",
                    icon: "gearshape.fill",
                    color: .green
                ) {
                    Task {
                        let results = await memoryManager.optimizeMemory(force: true)
                        if let results = results {
                            optimizationResults = results
                            showOptimizationResults = true
                            // Refresh data after optimization
                            await memoryManager.loadAllMemoryData()
                        }
                    }
                }
                
                
                MemoryActionButton(
                    title: "Export Memories",
                    subtitle: "Export all memories to file",
                    icon: "square.and.arrow.up.fill",
                    color: .blue
                ) {
                    Task {
                        await exportMemories()
                    }
                }
                
                MemoryActionButton(
                    title: "Import Memories",
                    subtitle: "Import memories from JSON file",
                    icon: "square.and.arrow.down.fill",
                    color: .purple
                ) {
                    showImportSheet = true
                }
                
                MemoryActionButton(
                    title: "Reset All",
                    subtitle: "Delete all memories from both databases",
                    icon: "exclamationmark.triangle.fill",
                    color: .red
                ) {
                    showResetConfirmation = true
                }
            }
        }
    }
    
    // MARK: - Memories Tab
    
    var memoriesTab: some View {
        VStack(spacing: 0) {
            // Search and Filter
            searchAndFilterSection
            
            // Memories List
            if memoryManager.isLoading {
                loadingView
            } else {
                memoriesListView
            }
        }
    }
    
    var searchAndFilterSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search memories...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, newValue in
                        // Debounced search - only search when user stops typing
                        if newValue.isEmpty {
                            Task {
                                await memoryManager.retrieveUserMemories(
                                    query: "",
                                    urgencyMode: selectedUrgencyMode,
                                    memoryTypes: selectedMemoryType == "All" ? nil : [selectedMemoryType]
                                )
                            }
                        }
                    }
                    .onSubmit {
                        Task {
                            await memoryManager.retrieveUserMemories(
                                query: searchText,
                                urgencyMode: selectedUrgencyMode,
                                memoryTypes: selectedMemoryType == "All" ? nil : [selectedMemoryType]
                            )
                        }
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        Task {
                            await memoryManager.retrieveUserMemories(
                                query: "",
                                urgencyMode: selectedUrgencyMode,
                                memoryTypes: selectedMemoryType == "All" ? nil : [selectedMemoryType]
                            )
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            HStack {
                Text("Filter:")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Picker("Memory Type", selection: $selectedMemoryType) {
                    ForEach(memoryTypes, id: \.self) { type in
                        Text(type.capitalized).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedMemoryType) { _, _ in
                    // TODO: Filter memories by type
                }
                
                Spacer()
                
                if !selectedMemoryIds.isEmpty {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Delete (\(selectedMemoryIds.count))")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    var memoriesListView: some View {
        List {
            ForEach(filteredMemories) { memory in
                MemoryRowView(
                    memory: memory,
                    isSelected: selectedMemoryIds.contains(memory.id),
                    color: memoryTypeColors[memory.memory_type] ?? .gray,
                    onToggleSelection: {
                        if selectedMemoryIds.contains(memory.id) {
                            selectedMemoryIds.remove(memory.id)
                        } else {
                            selectedMemoryIds.insert(memory.id)
                        }
                    },
                    onDelete: {
                        Task {
                            let success = await memoryManager.deleteMemories(memoryIds: [memory.id])
                            if success {
                                selectedMemoryIds.remove(memory.id)
                                // Remove from local arrays too
                                allMemories.removeAll { $0.id == memory.id }
                            }
                        }
                    }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
                .onAppear {
                    // Load more memories when approaching the end
                    if memory.id == filteredMemories.last?.id && hasMoreMemories && !isLoadingMore {
                        Task {
                            await loadMoreMemories()
                        }
                    }
                }
            }
            
            // Loading indicator at bottom
            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading more memories...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onAppear {
            if allMemories.isEmpty {
                Task {
                    await loadInitialMemories()
                }
            }
        }
    }
    
    var filteredMemories: [MemoryEntry] {
        var memories = allMemories.isEmpty ? memoryManager.userMemories : allMemories
        
        if selectedMemoryType != "All" {
            memories = memories.filter { $0.memory_type == selectedMemoryType }
        }
        
        if !searchText.isEmpty {
            memories = memories.filter { 
                $0.content.lowercased().contains(searchText.lowercased()) ||
                $0.memory_type.lowercased().contains(searchText.lowercased())
            }
        }
        
        return memories.sorted { $0.timestamp > $1.timestamp }
    }
    
    // MARK: - Infinite Scroll Functions
    
    func loadInitialMemories() async {
        guard !memoryManager.isLoading else { return }
        
        currentPage = 0
        allMemories = []
        hasMoreMemories = true
        
        await loadMoreMemories()
    }
    
    func loadMoreMemories() async {
        guard !isLoadingMore && hasMoreMemories else { return }
        
        isLoadingMore = true
        let limit = 50
        let offset = currentPage * limit
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/list/pradhumn?limit=\(limit)&offset=\(offset)")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = jsonResponse["success"] as? Bool, success,
                   let memoriesArray = jsonResponse["memories"] as? [[String: Any]] {
                    
                    var newMemories: [MemoryEntry] = []
                    
                    for memoryData in memoriesArray {
                        if let id = memoryData["id"] as? String,
                           let content = memoryData["content"] as? String,
                           let memoryType = memoryData["memory_type"] as? String,
                           let importance = memoryData["importance"] as? Double,
                           let timestamp = memoryData["created_at"] as? String {
                            
                            let memory = MemoryEntry(
                                id: id,
                                content: content,
                                memory_type: memoryType,
                                importance: importance,
                                timestamp: timestamp,
                                user_id: "pradhumn",
                                tokens: memoryData["tokens"] as? Int,
                                metadata: memoryData["metadata"] as? [String: String]
                            )
                            newMemories.append(memory)
                        }
                    }
                    
                    if newMemories.isEmpty {
                        hasMoreMemories = false
                    } else {
                        allMemories.append(contentsOf: newMemories)
                        currentPage += 1
                    }
                }
            }
        } catch {
            print("❌ Failed to load more memories: \(error)")
        }
        
        isLoadingMore = false
    }
    
    // MARK: - Insights Tab
    
    var insightsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if memoryManager.isLoading {
                    loadingView
                } else {
                    insightsContent
                }
            }
            .padding(20)
        }
    }
    
    var insightsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let insights = memoryManager.memoryInsights {
                personalitySection(insights)
                knowledgeDomainsSection(insights)
                interactionPatternsSection(insights)
                recommendationsSection(insights)
            } else {
                Text("No insights available yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    func personalitySection(_ insights: MemoryInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personality Profile")
                .font(.headline.bold())
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                HStack {
                    Text("Communication Style:")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(insights.communication_style)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Traits:")
                        .font(.subheadline.bold())
                    
                    if insights.personality_profile.isEmpty {
                        Text("No personality traits available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(Array(insights.personality_profile.keys.sorted()), id: \.self) { key in
                            HStack(alignment: .top) {
                                Text("• \(key.capitalized):")
                                    .font(.caption.bold())
                                    .foregroundColor(.primary)
                                
                                Text(insights.personality_profile[key] ?? "N/A")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    func knowledgeDomainsSection(_ insights: MemoryInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Knowledge Domains")
                .font(.headline.bold())
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(insights.knowledge_domains, id: \.self) { domain in
                    Text(domain)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
    
    func interactionPatternsSection(_ insights: MemoryInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interaction Patterns")
                .font(.headline.bold())
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                ForEach(Array(insights.interaction_patterns.keys.sorted()), id: \.self) { pattern in
                    HStack {
                        Text(pattern.capitalized)
                            .font(.subheadline)
                        Spacer()
                        Text("\(insights.interaction_patterns[pattern] ?? 0)")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    func recommendationsSection(_ insights: MemoryInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendations")
                .font(.headline.bold())
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                ForEach(insights.recommendations, id: \.self) { recommendation in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 16))
                        
                        Text(recommendation)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(Color.yellow.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    // MARK: - Profiles Tab
    
    var profilesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if memoryManager.isLoading {
                    loadingView
                } else {
                    profilesContent
                }
            }
            .padding(20)
        }
    }
    
    var profilesContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with actions
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("User Profiles")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    
                    Text("\(memoryManager.userProfiles.count) profiles found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await memoryManager.loadAllUserProfiles()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Refresh profiles")
                    
                    Button {
                        Task {
                            let success = await memoryManager.clearAllProfiles()
                            if success {
                                // Optionally show success message
                            }
                        }
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                            .frame(width: 28, height: 28)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear all profiles")
                    .disabled(memoryManager.userProfiles.isEmpty)
                }
            }
            
            // Profiles list
            if memoryManager.userProfiles.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No User Profiles Found")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("User profiles are automatically created as users interact with the system.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(memoryManager.userProfiles) { profile in
                        ProfileRowView(
                            profile: profile,
                            isExpanded: Binding(
                                get: { expandedProfiles.contains(profile.user_id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedProfiles.insert(profile.user_id)
                                    } else {
                                        expandedProfiles.remove(profile.user_id)
                                    }
                                }
                            ),
                            onDelete: {
                                Task {
                                    let success = await memoryManager.deleteUserProfile(userId: profile.user_id)
                                    if success {
                                        // Profile deleted successfully
                                        expandedProfiles.remove(profile.user_id)
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Settings Tab
    
    var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                debugSection
                backendStatusSection
                memorySystemsSection
            }
            .padding(20)
        }
    }
    
    var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug Information")
                .font(.headline.bold())
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                DebugInfoRow(title: "Current User ID", value: "pradhumn")
                DebugInfoRow(title: "Server URL", value: serverConfig.currentServerURL)
                DebugInfoRow(title: "Loading State", value: memoryManager.isLoading ? "Loading..." : "Idle")
                
                if let error = memoryManager.errorMessage {
                    DebugInfoRow(title: "Last Error", value: error)
                        .foregroundColor(.red)
                }
            }
            .padding(16)
            .background(Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    var backendStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Backend Status")
                    .font(.headline.bold())
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    Task {
                        await checkBackendHealth()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(backendHealthStatus == .unknown)
            }
            
            VStack(spacing: 8) {
                SystemStatusRow(
                    name: "Server Connection",
                    status: backendHealthStatus.text,
                    color: backendHealthStatus.color
                )
                
                SystemStatusRow(
                    name: "Memory API",
                    status: memoryManager.isLoading ? "Loading..." : "Active",
                    color: memoryManager.isLoading ? .orange : .green
                )
                
                if let error = memoryManager.errorMessage {
                    SystemStatusRow(
                        name: "Last Error",
                        status: String(error.prefix(30)) + (error.count > 30 ? "..." : ""),
                        color: .red
                    )
                }
            }
        }
        .onAppear {
            Task {
                await checkBackendHealth()
            }
        }
    }
    
    var memorySystemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory Systems")
                .font(.headline.bold())
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                SystemStatusRow(
                    name: "Advanced Memory Manager",
                    status: "Active",
                    color: .green
                )
                
                SystemStatusRow(
                    name: "Adaptive Personalization",
                    status: "Active",
                    color: .green
                )
                
                SystemStatusRow(
                    name: "Cognitive Analyzer",
                    status: "Available",
                    color: .blue
                )
                
                SystemStatusRow(
                    name: "LangGraph Memory",
                    status: "Active",
                    color: .green
                )
            }
        }
    }
    
    // MARK: - Helper Views
    
    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading memory data...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    var addMemorySheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Add New Memory")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Memory Type")
                        .font(.subheadline.bold())
                    
                    Picker("Memory Type", selection: $newMemoryType) {
                        ForEach(memoryTypes.dropFirst(), id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Content")
                        .font(.subheadline.bold())
                    
                    TextEditor(text: $newMemoryContent)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        showAddMemorySheet = false
                        newMemoryContent = ""
                        newMemoryType = "fact"
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Add Memory") {
                        Task {
                            let success = await memoryManager.storeMemory(
                                content: newMemoryContent,
                                memoryType: newMemoryType
                            )
                            if success {
                                showAddMemorySheet = false
                                newMemoryContent = ""
                                newMemoryType = "fact"
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newMemoryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
        .frame(width: 550, height: 400)
    }
    
    var importMemoriesSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Import Memories")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Import memories from a previously exported JSON file.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ImportOptionsView { fileData, overwriteExisting in
                        Task {
                            let result = await memoryManager.importMemories(from: fileData, overwriteExisting: overwriteExisting)
                            await MainActor.run {
                                importResult = result.message
                                showImportResult = true
                                if result.success {
                                    showImportSheet = false
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        showImportSheet = false
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
            }
            .padding(20)
        }
        .frame(width: 600, height: 450)
    }
    
    var optimizationResultsSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Memory Optimization Complete")
                    .font(.title2.bold())
                    .foregroundColor(.primary)
                
                if let results = optimizationResults {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Summary Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Summary")
                                    .font(.headline.bold())
                                    .foregroundColor(.primary)
                                
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Storage Freed: \(String(format: "%.2f", results.savings_mb)) MB")
                                            .font(.subheadline.bold())
                                        Text("Execution Time: \(String(format: "%.0f", results.execution_time_ms)) ms")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.green.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            // Detailed Results Section
                            if !results.strategies_applied.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Optimization Strategies Applied")
                                        .font(.headline.bold())
                                        .foregroundColor(.primary)
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                                        ForEach(results.strategies_applied, id: \.self) { strategy in
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Image(systemName: strategyIcon(for: strategy))
                                                        .foregroundColor(strategyColor(for: strategy))
                                                    Text(strategyDisplayName(for: strategy))
                                                        .font(.subheadline.bold())
                                                    Spacer()
                                                }
                                                
                                                if let details = results.details?[strategy] {
                                                    Text(strategyDescription(for: strategy, details: details))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .padding(12)
                                            .background(strategyColor(for: strategy).opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                            
                            // Database Breakdown
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Database Storage Breakdown")
                                    .font(.headline.bold())
                                    .foregroundColor(.primary)
                                
                                VStack(spacing: 8) {
                                    if let sqlBefore = results.sql_size_before_mb, let sqlAfter = results.sql_size_after_mb {
                                        HStack {
                                            Image(systemName: "database.fill")
                                                .foregroundColor(.blue)
                                            Text("SQL Database:")
                                                .font(.subheadline)
                                            Spacer()
                                            Text("\(String(format: "%.2f", sqlBefore)) MB → \(String(format: "%.2f", sqlAfter)) MB")
                                                .font(.subheadline.bold())
                                        }
                                    }
                                    
                                    if let vectorBefore = results.vector_size_before_mb, let vectorAfter = results.vector_size_after_mb {
                                        HStack {
                                            Image(systemName: "brain.head.profile")
                                                .foregroundColor(.purple)
                                            Text("Vector Database:")
                                                .font(.subheadline)
                                            Spacer()
                                            Text("\(String(format: "%.2f", vectorBefore)) MB → \(String(format: "%.2f", vectorAfter)) MB")
                                                .font(.subheadline.bold())
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    HStack {
                                        Text("Total Storage:")
                                            .font(.subheadline.bold())
                                        Spacer()
                                        Text("\(String(format: "%.2f", results.size_before_mb)) MB → \(String(format: "%.2f", results.size_after_mb)) MB")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(12)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            // Memory Count Changes
                            HStack {
                                Text("Memories:")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(results.memories_before) → \(results.memories_after)")
                                    .font(.subheadline.bold())
                            }
                            .padding(12)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            if let skipped = results.skipped {
                                Text("Note: \(skipped)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(8)
                                    .background(Color.orange.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                } else {
                    Text("No optimization results available")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack {
                    Button("Done") {
                        showOptimizationResults = false
                        optimizationResults = nil
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                }
            }
            .padding(20)
        }
        .frame(width: 700, height: 600)
    }
    
    // Helper functions for optimization results display
    private func strategyIcon(for strategy: String) -> String {
        switch strategy {
        case "deduplication": return "doc.on.doc.fill"
        case "importance_cleanup": return "trash.fill"
        case "compression": return "archivebox.fill"
        case "similarity_merge": return "arrow.triangle.merge"
        case "archival": return "archivebox.circle.fill"
        case "vector_cleanup": return "brain.head.profile"
        default: return "gearshape.fill"
        }
    }
    
    private func strategyColor(for strategy: String) -> Color {
        switch strategy {
        case "deduplication": return .blue
        case "importance_cleanup": return .red
        case "compression": return .orange
        case "similarity_merge": return .green
        case "archival": return .purple
        case "vector_cleanup": return .indigo
        default: return .gray
        }
    }
    
    private func strategyDisplayName(for strategy: String) -> String {
        switch strategy {
        case "deduplication": return "Deduplication"
        case "importance_cleanup": return "Low-Importance Cleanup"
        case "compression": return "Content Compression"
        case "similarity_merge": return "Similarity Merge"
        case "archival": return "Memory Archival"
        case "vector_cleanup": return "Vector Cleanup"
        default: return strategy.capitalized
        }
    }
    
    private func strategyDescription(for strategy: String, details: [String: Any]) -> String {
        switch strategy {
        case "deduplication":
            let merged = details["merged_count"] as? Int ?? 0
            return "Removed \(merged) duplicate memories"
        case "importance_cleanup":
            let deleted = details["deleted_count"] as? Int ?? 0
            return "Deleted \(deleted) low-importance memories"
        case "compression":
            let compressed = details["compressed_count"] as? Int ?? 0
            return "Compressed \(compressed) large memories"
        case "similarity_merge":
            let merged = details["merged_count"] as? Int ?? 0
            return "Merged \(merged) similar memories"
        case "archival":
            let archived = details["archived_count"] as? Int ?? 0
            return "Archived \(archived) old memories"
        case "vector_cleanup":
            let cleaned = details["deleted_count"] as? Int ?? 0
            return "Cleaned \(cleaned) orphaned vectors"
        default:
            return "Strategy applied successfully"
        }
    }
    
    // MARK: - Helper Functions
    
    private func checkBackendHealth() async {
        backendHealthStatus = .unknown
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/health")!
            let (_, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    backendHealthStatus = .healthy
                } else {
                    backendHealthStatus = .unhealthy
                }
            } else {
                backendHealthStatus = .unhealthy
            }
        } catch {
            backendHealthStatus = .unhealthy
            print("❌ Backend health check failed: \(error)")
        }
    }
    
    private func exportMemories() async {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        savePanel.nameFieldStringValue = "memories_export_\(dateFormatter.string(from: Date())).json"
        savePanel.title = "Export Memories"
        savePanel.message = "Choose where to save your memories export"
        
        let response = await savePanel.begin()
        
        if response == .OK, let url = savePanel.url {
            do {
                // Prepare export data with safe JSON serialization
                var statisticsData: [String: Any] = [:]
                if let stats = memoryManager.memoryStatistics {
                    statisticsData = [
                        "user_id": stats.user_id,
                        "total_memories": stats.total_memories,
                        "total_tokens": stats.total_tokens,
                        "total_size_bytes": stats.total_size_bytes,
                        "avg_importance": stats.avg_importance,
                        "memory_types_count": stats.memory_types_count,
                        "timestamp": stats.timestamp,
                        "combined_size_mb": stats.combined_size_mb ?? 0.0,
                        "combined_size_bytes": stats.combined_size_bytes ?? 0
                    ]
                    
                    // Convert type breakdown to JSON-safe format
                    var typeBreakdownData: [String: [String: Any]] = [:]
                    for (type, typeStats) in stats.type_breakdown {
                        typeBreakdownData[type] = [
                            "count": typeStats.count,
                            "tokens": typeStats.tokens
                        ]
                    }
                    statisticsData["type_breakdown"] = typeBreakdownData
                    
                    // Add database stats if available
                    if let sqlDB = stats.sql_database {
                        statisticsData["sql_database"] = [
                            "size_mb": sqlDB.size_mb,
                            "size_bytes": sqlDB.size_bytes,
                            "memory_count": sqlDB.memory_count
                        ]
                    }
                    
                    if let vectorDB = stats.vector_database {
                        statisticsData["vector_database"] = [
                            "vector_size_mb": vectorDB.vector_size_mb,
                            "vector_size_bytes": vectorDB.vector_size_bytes,
                            "embedding_count": vectorDB.embedding_count,
                            "collection_count": vectorDB.collection_count,
                            "chroma_db_size_mb": vectorDB.chroma_db_size_mb,
                            "available": vectorDB.available
                        ]
                    }
                }
                
                let exportData: [String: Any] = [
                    "export_date": ISO8601DateFormatter().string(from: Date()),
                    "user_id": "pradhumn",
                    "total_memories": memoryManager.userMemories.count,
                    "memories": memoryManager.userMemories.map { memory in
                        [
                            "id": memory.id,
                            "content": memory.content,
                            "memory_type": memory.memory_type,
                            "importance": memory.importance,
                            "timestamp": memory.timestamp,
                            "user_id": memory.user_id,
                            "tokens": memory.tokens ?? 0,
                            "metadata": memory.metadata ?? [:]
                        ]
                    },
                    "statistics": statisticsData
                ]
                
                let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
                try jsonData.write(to: url)
                
                print("✅ Memories exported successfully to: \(url.path)")
                
            } catch {
                print("❌ Failed to export memories: \(error)")
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        // Try multiple date format parsers
        let formatters = [
            // ISO8601 with fractional seconds
            { () -> DateFormatter in
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                f.timeZone = TimeZone(identifier: "UTC")
                return f
            }(),
            // ISO8601 without fractional seconds
            { () -> DateFormatter in
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                f.timeZone = TimeZone(identifier: "UTC")
                return f
            }(),
            // SQLite datetime format
            { () -> DateFormatter in
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                f.timeZone = TimeZone(identifier: "UTC")
                return f
            }(),
            // ISO8601 formatter as fallback
            ISO8601DateFormatter()
        ]
        
        for formatter in formatters {
            var date: Date?
            
            if let iso8601Formatter = formatter as? ISO8601DateFormatter {
                date = iso8601Formatter.date(from: dateString)
            } else if let regularFormatter = formatter as? DateFormatter {
                date = regularFormatter.date(from: dateString)
            }
            
            if let parsedDate = date {
                let displayFormatter = DateFormatter()
                displayFormatter.dateStyle = .short
                displayFormatter.timeStyle = .short
                displayFormatter.timeZone = TimeZone.current
                return displayFormatter.string(from: parsedDate)
            }
        }
        
        // If all parsing fails, check if it's a relative time description
        if dateString.lowercased().contains("ago") || dateString.lowercased().contains("now") {
            return dateString
        }
        
        return "Just now"
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func getColorForMemoryType(_ type: String) -> Color {
        // First check predefined colors
        if let color = memoryTypeColors[type] {
            return color
        }
        
        // Generate consistent colors for unknown types based on hash
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .red, .cyan, .pink, .mint,
            .brown, .indigo, .teal, .gray, .yellow, .primary, .secondary
        ]
        
        let hash = abs(type.hashValue)
        let colorIndex = hash % colors.count
        
        print("🎨 Generated color for unknown memory type '\(type)': \(colors[colorIndex])")
        
        return colors[colorIndex]
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 18, weight: .medium))
                
                Spacer()
                
                Text(value)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DatabaseStatCard: View {
    let title: String
    let size: String
    let memoryCount: Int
    let icon: String
    let color: Color
    let additionalInfo: String?
    
    init(title: String, size: String, memoryCount: Int, icon: String, color: Color, additionalInfo: String? = nil) {
        self.title = title
        self.size = size
        self.memoryCount = memoryCount
        self.icon = icon
        self.color = color
        self.additionalInfo = additionalInfo
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .medium))
                
                Spacer()
                
                Text(size)
                    .font(.headline.bold())
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                
                Text("\(memoryCount) \(title.contains("Vector") ? "embeddings" : "memories")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let additionalInfo = additionalInfo {
                    Text(additionalInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct MemoryTypeRow: View {
    let type: String
    let count: Int
    let tokens: Int
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            Text(type.capitalized)
                .font(.subheadline.bold())
                .foregroundColor(.primary)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(count) memories")
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                
                Text("\(tokens) tokens")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MemoryActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 20, weight: .medium))
                    
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct MemoryRowView: View {
    let memory: MemoryEntry
    let isSelected: Bool
    let color: Color
    let onToggleSelection: () -> Void
    let onDelete: () -> Void
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                onToggleSelection()
            } label: {
                ZStack {
                    Circle()
                        .fill(isSelected ? color : Color.clear)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(color, lineWidth: 2)
                        )
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .frame(width: 32, height: 32) // Larger hit area
                .contentShape(Circle()) // Ensure entire area is clickable
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(memory.memory_type.capitalized)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(color)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    Spacer()
                    
                    Text(formatTimestamp(memory.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(memory.content)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                
                HStack {
                    Text("Importance: \(Int(memory.importance * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let tokens = memory.tokens {
                        Text("\(tokens) tokens")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Individual delete button
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Delete this memory")
        }
        .padding(16)
        .background(isSelected ? color.opacity(0.1) : Color.gray.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? color : Color.clear, lineWidth: 2)
        )
        .alert("Delete Memory", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this memory? This action cannot be undone.")
        }
    }
    
    private func formatTimestamp(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: timestamp) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        
        return timestamp
    }
}

struct DebugInfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title + ":")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}

struct SystemStatusRow: View {
    let name: String
    let status: String
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(name)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(status)
                .font(.caption.bold())
                .foregroundColor(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ProfileRowView: View {
    let profile: UserProfile
    @Binding var isExpanded: Bool
    let onDelete: () -> Void
    
    @State private var showDeleteConfirmation = false
    @State private var showDeleteItemConfirmation = false
    @State private var itemToDelete: (type: String, item: String)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main profile info
            HStack(alignment: .top, spacing: 16) {
                // Profile avatar
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(String(profile.user_id.prefix(2)).uppercased())
                            .font(.headline.bold())
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 6) {
                    // User ID and communication style
                    HStack {
                        Text(profile.user_id)
                            .font(.headline.bold())
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(profile.communication_style.capitalized)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    // Last updated
                    Text("Updated: \(formatUpdateDate(profile.updated_at))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Quick overview
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Interests")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Text("\(profile.interests.count)")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Expertise")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Text("\(profile.expertise_areas.count)")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Traits")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Text("\(profile.personality_traits.count)")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                    }
                }
                
                // Action buttons
                VStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                            .frame(width: 28, height: 28)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse details" : "Expand details")
                    
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                            .frame(width: 28, height: 28)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete profile")
                }
            }
            
            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                    
                    // Interests section
                    if !profile.interests.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Interests")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 80), spacing: 8)
                            ], spacing: 8) {
                                ForEach(profile.interests, id: \.self) { interest in
                                    HStack(spacing: 4) {
                                        Text(interest)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        
                                        Button {
                                            itemToDelete = (type: "interest", item: interest)
                                            showDeleteItemConfirmation = true
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove \(interest)")
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }
                    
                    // Expertise areas section
                    if !profile.expertise_areas.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Expertise Areas")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 80), spacing: 8)
                            ], spacing: 8) {
                                ForEach(profile.expertise_areas, id: \.self) { area in
                                    HStack(spacing: 4) {
                                        Text(area)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        
                                        Button {
                                            itemToDelete = (type: "expertise", item: area)
                                            showDeleteItemConfirmation = true
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove \(area)")
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }
                    
                    // Personality traits section
                    if !profile.personality_traits.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Personality Traits")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 80), spacing: 8)
                            ], spacing: 8) {
                                ForEach(profile.personality_traits, id: \.self) { trait in
                                    HStack(spacing: 4) {
                                        Text(trait)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        
                                        Button {
                                            itemToDelete = (type: "trait", item: trait)
                                            showDeleteItemConfirmation = true
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove \(trait)")
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }
                    
                    // Preferences section
                    if !profile.preferences.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preferences")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(profile.preferences.keys.sorted()), id: \.self) { key in
                                    HStack {
                                        Text("\(key.capitalized):")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)
                                        
                                        Text(profile.preferences[key] ?? "N/A")
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Button {
                                            itemToDelete = (type: "preference", item: key)
                                            showDeleteItemConfirmation = true
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(.red.opacity(0.7))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove \(key) preference")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .slide))
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .alert("Delete Profile", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete the profile for \(profile.user_id)? This action cannot be undone.")
        }
        .alert("Remove Item", isPresented: $showDeleteItemConfirmation) {
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
            Button("Remove", role: .destructive) {
                if let item = itemToDelete {
                    deleteProfileItem(type: item.type, item: item.item)
                    itemToDelete = nil
                }
            }
        } message: {
            if let item = itemToDelete {
                Text("Are you sure you want to remove '\(item.item)' from \(item.type == "preference" ? "preferences" : item.type == "trait" ? "personality traits" : item.type == "expertise" ? "expertise areas" : "interests")?")
            } else {
                Text("Remove this item?")
            }
        }
    }
    
    private func deleteProfileItem(type: String, item: String) {
        Task {
            do {
                // Call backend to update profile by removing the specific item
                let url = URL(string: "\(serverConfig.currentServerURL)/profiles/\(profile.user_id)/remove_item")!
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let requestBody: [String: Any] = [
                    "item_type": type,
                    "item_value": item
                ]
                
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = result["success"] as? Bool, success {
                        print("✅ Profile item removed successfully: \(result)")
                        
                        // Refresh the profiles list to show updated data
                        await MemoryManager.shared.loadAllUserProfiles()
                    }
                }
            } catch {
                print("❌ Failed to delete profile item: \(error)")
            }
        }
    }
    
    private func formatUpdateDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        
        return dateString
    }
}

struct ImportOptionsView: View {
    let onImport: (Data, Bool) -> Void
    
    @State private var selectedFile: URL?
    @State private var overwriteExisting = false
    @State private var isDragOver = false
    
    var body: some View {
        VStack(spacing: 20) {
            // File selection area
            VStack(spacing: 12) {
                if let selectedFile = selectedFile {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.blue)
                        Text(selectedFile.lastPathComponent)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                        Button("Remove") {
                            self.selectedFile = nil
                        }
                        .foregroundColor(.red)
                        .font(.caption)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(isDragOver ? .blue : .secondary)
                        
                        Text("Drop JSON file here or click to select")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button("Select File") {
                            selectFile()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isDragOver ? Color.blue : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .background(isDragOver ? Color.blue.opacity(0.05) : Color.clear)
                    )
                    .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                        handleDrop(providers: providers)
                    }
                }
            }
            
            // Import options
            VStack(alignment: .leading, spacing: 8) {
                Text("Import Options")
                    .font(.subheadline.bold())
                
                Toggle("Overwrite existing memories", isOn: $overwriteExisting)
                    .font(.subheadline)
                
                Text("If enabled, memories with matching IDs will be updated. Otherwise, they will be skipped.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Import button
            if selectedFile != nil {
                Button("Import Memories") {
                    performImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFile == nil)
            }
        }
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "Select Memory Export File"
        panel.message = "Choose a JSON file containing exported memories"
        
        if panel.runModal() == .OK {
            selectedFile = panel.url
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               url.pathExtension.lowercased() == "json" {
                DispatchQueue.main.async {
                    selectedFile = url
                }
            }
        }
        return true
    }
    
    private func performImport() {
        guard let fileURL = selectedFile else { return }
        
        do {
            let fileData = try Data(contentsOf: fileURL)
            onImport(fileData, overwriteExisting)
        } catch {
            print("❌ Failed to read file: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    MemoryManagementView()
        .frame(width: 800, height: 600)
}
