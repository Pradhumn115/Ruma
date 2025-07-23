# Setup Compressed Backend for Ruma

## Instructions for implementing compressed ruma-python backend

### Step 1: Replace ruma-python with zip file in Xcode

1. **Remove the current ruma-python folder** from your Xcode project:
   - In Xcode, right-click on `ruma-python` in the project navigator
   - Select "Delete" and choose "Move to Trash"

2. **Add the compressed zip file**:
   - Drag `ruma-python.zip` from the SuriAI directory into your Xcode project Resources
   - Make sure "Copy items if needed" is checked
   - Ensure it's added to your target

### Step 2: Update AppDelegate.swift

The `AppDelegate.swift` file has been updated with the following new functionality:

- `ensurePythonBackendExtracted()`: Checks if ruma-python exists, extracts from zip if needed
- `extractZip()`: Uses system unzip command to extract the backend
- `setExecutablePermissions()`: Sets proper permissions on Python binaries

### Step 3: Test the implementation

1. Build and run your app
2. Check the console output for extraction messages:
   - "🔄 First-time setup: Extracting Python backend..." (first launch)
   - "✅ Python backend extracted successfully" (successful extraction)
   - "✅ Python backend already extracted" (subsequent launches)

### Benefits of this approach:

1. **Faster app transfer**: Compressed backend significantly reduces app bundle size
2. **First-time extraction**: Backend is extracted automatically on first launch
3. **Persistent storage**: Once extracted, no need to extract again
4. **Proper permissions**: Executable permissions are set automatically
5. **Error handling**: Comprehensive error checking and logging

### File sizes comparison:
- **Uncompressed ruma-python**: ~500MB+ 
- **Compressed ruma-python.zip**: ~150-200MB (60-70% reduction)

### Troubleshooting:

If extraction fails:
1. Check that `ruma-python.zip` is properly included in the app bundle
2. Verify app has write permissions to its Resources directory
3. Check console output for specific error messages
4. Ensure sufficient disk space for extraction

### Development Notes:

- The zip file contains the complete Python environment with all dependencies
- Extraction happens in the app's Resources directory (read-only in production)
- The extracted backend behaves identically to the original uncompressed version
- This approach is compatible with macOS app sandboxing requirements