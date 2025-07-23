#!/usr/bin/env swift

import Foundation
import CryptoKit

// This script encrypts your backend.zip file for secure distribution
// Usage: swift encrypt_backend.swift /path/to/backend.zip /path/to/encrypted_backend.zip

// Same encryption key generation as in the app
func generateEncryptionKey() -> SymmetricKey {
    let bundleId = "name.pradhumn.Ruma"  // Updated to match your actual bundle ID
    let appVersion = "0.2.0"             // Updated to match your actual app version
    let keyData = "\(bundleId).\(appVersion).ruma.backend.key".data(using: .utf8)!
    print("🔑 Encryption key derived from: \(bundleId).\(appVersion)")
    return SymmetricKey(data: SHA256.hash(data: keyData))
}

func encryptBackendZip(at inputURL: URL, outputURL: URL) throws {
    print("🔒 Encrypting backend.zip...")
    
    // Read original zip data
    let originalData = try Data(contentsOf: inputURL)
    
    // Generate random IV
    let iv = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    
    // Encrypt the data
    let encryptionKey = generateEncryptionKey()
    let sealedBox = try AES.GCM.seal(originalData, using: encryptionKey)
    
    // Create final encrypted file with header + IV + encrypted content
    var finalData = Data()
    finalData.append("RUMA_ENCRYPTED_V1".data(using: .utf8)!)
    finalData.append(iv)
    
    // Get the combined data from sealed box
    guard let combinedData = sealedBox.combined else {
        throw NSError(domain: "EncryptionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get combined encrypted data"])
    }
    finalData.append(combinedData)
    
    // Write encrypted file
    try finalData.write(to: outputURL)
    
    print("✅ Backend.zip encrypted successfully")
    print("📁 Input file: \(inputURL.path)")
    print("📁 Output file: \(outputURL.path)")
    print("🔑 Original size: \(originalData.count) bytes")
    print("🔑 Encrypted size: \(finalData.count) bytes")
    print("🔑 Size increase: \(finalData.count - originalData.count) bytes")
}

// Main execution
guard CommandLine.arguments.count == 3 else {
    print("Usage: swift encrypt_backend.swift <input_backend.zip> <output_encrypted_backend.zip>")
    print("Example: swift encrypt_backend.swift backend.zip encrypted_backend.zip")
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

let inputURL = URL(fileURLWithPath: inputPath)
let outputURL = URL(fileURLWithPath: outputPath)

// Verify input file exists
guard FileManager.default.fileExists(atPath: inputPath) else {
    print("❌ Input file not found: \(inputPath)")
    exit(1)
}

// Encrypt the file
do {
    try encryptBackendZip(at: inputURL, outputURL: outputURL)
    print("🎉 Encryption completed successfully!")
    print("ℹ️ Replace your backend.zip in the app bundle with the encrypted version")
} catch {
    print("❌ Encryption failed: \(error)")
    exit(1)
}
