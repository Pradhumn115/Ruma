//import SwiftUI
//
//struct Message: Encodable {
//    let input : String
//}
//struct ModelMessage: Decodable {
//    let response : String
//}
//
//func sendPostRequest (userInput: String!) async -> String {
//    
//    
//    let url = URL(string: "http://127.0.0.1:8000/chat")!
//    
//    var request = URLRequest(url: url)
//    request.httpMethod = "POST"
//    
////
//    let message = Message(input: userInput)
//    
////
////
//    let jsonData = try! JSONEncoder().encode(message)
//    
//    request.httpBody = jsonData
//    
//    
//    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
////
//    do{
//        let (data, _) = try await URLSession.shared.upload(for: request, from: jsonData)
//        let newData = try JSONDecoder().decode(ModelMessage.self,from: data)
//        print(newData)
//        return newData.response
//
//    }catch{
//        print("Fetch Failed, Error: ",error)
//        return "Fetch Failed"
//    }
//    
//}

import Foundation
import SwiftUI

// Your message to send
struct Message: Encodable {
    let input: String
}

// The JSON response chunk you expect from the server, e.g. {"content": "..."}
struct ModelMessage: Decodable {
    let content: String
}

func streamChatResponse(userInput: String) async throws -> AsyncThrowingStream<String, Error> {
    let url = URL(string: "http://127.0.0.1:8000/chat")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let message = Message(input: userInput)
    request.httpBody = try JSONEncoder().encode(message)

    let (bytes, _) = try await URLSession.shared.bytes(for: request)

    return AsyncThrowingStream { continuation in
        Task {
            do {
                for try await line in bytes.lines {
                    guard line.starts(with: "data:") else { continue }
                    print(line)
                    let dataLine = line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

                    // Stop signal (optional)
                    if dataLine == "[DONE]" || dataLine == "<|eot_id|>" {
                        break
                    }
                    
                    if let jsonData = dataLine.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(ModelMessage.self, from: jsonData) {
                        continuation.yield(decoded.content)
                    }
                    
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

func waitForModelReady(retryInterval: TimeInterval = 1.0) async throws {
    let url = URL(string: "http://127.0.0.1:8000/status")!

    while true {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let status = try? JSONDecoder().decode([String: Bool].self, from: data),
               status["ready"] == true {
                print("✅ Model is ready.")
                return
            }
            print("⏳ Model not ready, retrying...")

        } catch {
            print("❌ Server not reachable, retrying in \(retryInterval)s...")
        }
        
        try await Task.sleep(nanoseconds: UInt64(retryInterval * 1_000_000_000))
    }
}

class AppState: ObservableObject {
    @Published var modelReady = false
}
