//
//  ModelDirectorySettings.swift
//  SuriAI
//
//  Created by Claude on 02/07/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ModelDirectorySettings: View {
    @EnvironmentObject var viewModel: ModelHubViewModel
    @State private var showingDirectoryPicker = false
    @State private var newDirectoryPath = ""
    @State private var showingConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Models Directory Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Choose where to store downloaded AI models")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Current directory info
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text("Current Directory")
                        .font(.headline)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.modelsDirectory.isEmpty ? "Loading..." : viewModel.modelsDirectory)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                    
                    Text("This is where all downloaded models are stored")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Directory selection
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "gear")
                        .foregroundStyle(.orange)
                    Text("Change Directory")
                        .font(.headline)
                }
                
                VStack(spacing: 12) {
                    Button {
                        showingDirectoryPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("Choose New Directory")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isChangingDirectory)
                    
                    if !newDirectoryPath.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("New Directory:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text(newDirectoryPath)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .foregroundStyle(.green)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            
                            Button("Apply Changes") {
                                showingConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isChangingDirectory)
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Warning section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Important Notes")
                        .font(.headline)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Changing the directory doesn't move existing models")
                    Text("• You'll need to re-download models in the new location")
                    Text("• Make sure the new directory has sufficient free space")
                    Text("• The app will restart after changing the directory")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.yellow.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Spacer()
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if viewModel.isChangingDirectory {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Updating...")
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 600)
        .background(Material.regular)
        .onAppear {
            Task {
                await viewModel.fetchModelsDirectory()
            }
        }
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    newDirectoryPath = url.path
                }
            case .failure(let error):
                viewModel.errorMessage = "Failed to select directory: \(error.localizedDescription)"
            }
        }
        .alert("Change Models Directory?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {
                newDirectoryPath = ""
            }
            Button("Change Directory") {
                Task {
                    let success = await viewModel.setModelsDirectory(newPath: newDirectoryPath)
                    if success {
                        newDirectoryPath = ""
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This will change where new models are downloaded. Existing models will remain in the current directory.\n\nNew directory: \(newDirectoryPath)")
        }
        .alert("Error", isPresented: .constant(!viewModel.errorMessage.isEmpty)) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

#Preview {
    ModelDirectorySettings()
        .environmentObject(ModelHubViewModel())
}