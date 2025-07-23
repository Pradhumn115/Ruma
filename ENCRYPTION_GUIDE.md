# Backend.zip Encryption Guide

## Overview
Your backend.zip file in the app bundle can now be encrypted using AES-256-GCM encryption for enhanced security.

## 🔒 **Security Benefits:**
- **AES-256-GCM encryption** - Military-grade encryption
- **App-specific keys** - Derived from bundle ID and version
- **Tamper resistance** - Cannot be easily reverse-engineered
- **Backward compatibility** - Works with both encrypted and plain zip files

## 📦 **How to Encrypt Your Backend.zip:**

### Step 1: Prepare your backend.zip
Ensure your original `backend.zip` is ready and contains all necessary Python files.

### Step 2: Run the encryption script
```bash
cd /path/to/your/SuriAI/project
swift encrypt_backend.swift backend.zip encrypted_backend.zip
```

### Step 3: Replace the file in your app bundle
1. Remove the original `backend.zip` from your Xcode project
2. Add the `encrypted_backend.zip` to your project
3. **Rename it back to `backend.zip`** in Xcode
4. Make sure it's included in your app bundle

### Step 4: Update bundle ID and version (if needed)
If your bundle ID or app version is different from the defaults, update these in `encrypt_backend.swift`:
```swift
let bundleId = "com.yourcompany.yourapp"  // Update this
let appVersion = "1.0"                    // Update this
```

## 🔍 **Expected Output:**
```
🔒 Encrypting backend.zip...
✅ Backend.zip encrypted successfully
📁 Input file: /path/to/backend.zip
📁 Output file: /path/to/encrypted_backend.zip
🔑 Original size: 1234567 bytes
🔑 Encrypted size: 1234600 bytes
🔑 Size increase: 33 bytes
🎉 Encryption completed successfully!
```

## 🚀 **App Runtime Behavior:**

### With Encrypted backend.zip:
```
🔓 Decrypting backend.zip...
✅ Backend.zip decrypted successfully
🗑️ Cleaned up decrypted zip file
🔒 Applying security measures to backend directory...
```

### With Plain backend.zip:
```
ℹ️ Backend.zip is not encrypted, using as-is
🔒 Applying security measures to backend directory...
```

## 🛡️ **Security Features:**

1. **Encryption Key Generation:**
   - Uses bundle ID + app version + secret phrase
   - SHA256 hash for key derivation
   - 256-bit AES key strength

2. **File Format:**
   - `RUMA_ENCRYPTED_V1` header (17 bytes)
   - Random IV (16 bytes)
   - AES-GCM encrypted content

3. **Runtime Security:**
   - Decrypts only in memory
   - Immediately deletes decrypted temp file
   - No plain text backend.zip left on disk

## 🔧 **Troubleshooting:**

### Error: "Backend decryption failed"
- Check that bundle ID and version match between encryption script and app
- Verify the encrypted file wasn't corrupted during copying
- Ensure the file has the correct `RUMA_ENCRYPTED_V1` header

### Error: "Invalid encrypted file format"
- The file might be corrupted or not properly encrypted
- Re-run the encryption script
- Check file permissions

## 📋 **Best Practices:**

1. **Keep original backend.zip safe** - Store it securely for future updates
2. **Test thoroughly** - Verify the encrypted version works before distribution
3. **Update encryption** - Re-encrypt when changing bundle ID or version
4. **Monitor logs** - Check app logs for decryption success/failure messages

## 🔐 **Security Notes:**

- The encryption key is derived from app metadata, making it unique per app
- Even if someone extracts the encrypted file, they need your specific app to decrypt it
- The decryption only works within your app's runtime environment
- Temporary decrypted files are immediately cleaned up for security