//
//  ContentView.swift
//  FloatingWindow2
//
//  Created by Pradhumn Gupta on 25/05/25.
//

import SwiftUI
import AppKit
import MarkdownUI

struct ContentView: View {
    var dismiss: () -> ()


    @EnvironmentObject var focusModel: FocusModel
    @FocusState private var isTextFieldFocused: Bool
    @State private var streamingTask: Task<Void, Error>? = nil
    @State var messages: [ChatMessage] = []
    @State private var userInput: String = ""
    @State private var response: String = ""
    @State var showResult: Bool = false
    @State var loading: Bool = false
    @State private var text: String = ""
    @State private var isStreaming: Bool = false
    @StateObject private var appState = AppState()
    @State private var textStreaming:Bool = false



    @EnvironmentObject var sizeUpdater: WindowSizeUpdater

    var body: some View {
  
        VStack(spacing: 0){
            

            HStack{
                Button{
                      self.dismiss()
                    
                }label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
    
                .focusEffectDisabled()
        
                
                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal, 10)
           
    
               
                
            TextField(appState.modelReady ? "Ask Query" : "loading model..." , text: $userInput)
                .focused($isTextFieldFocused)
                .onChange(of: focusModel.focusTextField) { newValue, _ in
                    
                    isTextFieldFocused = true
                    focusModel.focusTextField = false // reset trigger
                    
                }
                .font(.title2)
                .textFieldStyle(.plain)
                .padding(.trailing , 50)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .onSubmit {
                    if !isStreaming && appState.modelReady{
                            submitAction()
                        
                    }
                }
                .overlay{
                    
                    HStack{
                        Spacer()
                        Button{
                            if isStreaming{
                                streamingTask?.cancel()
                                
                                Task {
                                    await stopGeneration()
                                }
                                
                                isStreaming = false
                                
                            }else{
                                if appState.modelReady{
                                    submitAction()
                                }
                            }
                            
                            

                            
                            
                            
                            
                        }label: {
                            if isStreaming{
                                Image(systemName: "square.fill")
                                    .font(.system(size: 20))
                                    .padding(.trailing,20)
                            }
                            else{
                                if appState.modelReady{
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 20))
                                        .padding(.trailing,20)
                                }
                                else {
                                    Image(systemName: "paperplane.fill")
                                        .foregroundStyle(.gray)
                                        .font(.system(size: 20))
                                        .padding(.trailing,20)
                                }
                                
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
           
//            if !appState.modelReady{
//                HStack{
//                    Text("Loading Model ")
//                        .fontWeight(.medium)
//                    DotLoader()
//                }
//            }
            
            if loading {
                DotLoader()
            }
            
     
            
            
            
            
            ScrollViewReader { scrollProxy in
                ScrollView{

                    LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(messages) { message in
                                    HStack {
                                        if message.role == .user {
                                            Spacer()
                                            Text(.init(message.content))
                                                .font(.title3)
                                                .padding(.horizontal)
                                                .padding(.vertical, 10)
                                                .background(Color.blue.opacity(0.7))
                                                .foregroundColor(.white)
                                                .cornerRadius(8)
                                            
                                            
                                            
                                        }
                                        else {

                                            Markdown(message.content)
                                                .markdownTextStyle{
                                                    FontSize(15)
                                                }
                                                
                                            
                                                      
                                            
                                            Spacer()
                                        }
                                            
                                       
                                    }
                                    
                                    
                                    .padding(.bottom, 20)
                                }

                                
                                
                                
                            }
                    // Scroll to the last message
                    Color.clear.frame(height: 1).id("BOTTOM")
                    
                }
                
                .scrollIndicators(.never)
                .padding(showResult ? 20 : 0)
                .animation(.easeIn, value: showResult)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                .padding()
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing){
                    if showResult {
                        
                        Button{
                            showResult = false
                            sizeUpdater.updateSize(to: CGSize(width: 300, height: 70))
                        }label:{
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(24)
                        .buttonStyle(.plain)
                        
                    }
                    
                }
                .onChange(of: response) { _, _ in
                    // Auto-scroll to bottom when new content comes in
                    withAnimation {
                        scrollProxy.scrollTo("BOTTOM", anchor: .bottom)
                    }
                }
            }
            
        
                
                
        }
        .background(Material.ultraThin)
            
        
//            .transition(.move(edge: .leading).combined(with: .opacity))
            .cornerRadius(10)
            .frame(minWidth: 400)
//            .frame(width: 500, alignment: .top)
//            .frame(height: showResult ? 500 : 70 , alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .onAppear{
                Task{
                    do {
                        try await waitForModelReady()
                        appState.modelReady = true
                    } catch {
                        print("❌ Model failed to load: \(error)")
                    }
                }
            }


            
      
        


    }
    
    func submitAction(){
        
        streamingTask = Task{
            do {
                
                loading = true
                
                isStreaming = true
                
                
                // Add user message
                messages.append(ChatMessage(role: .user, content: userInput))
                response = "" // reset response for new AI answer
                
       
     
       
                let stream = try await streamChatResponse(userInput: userInput)
                
                
                
                
                // Add placeholder AI message to update as chunks come in
                messages.append(ChatMessage(role: .ai, content: ""))
                
                showResult = true
                let newHeight: CGFloat = showResult ? 400 : 70
                sizeUpdater.updateSize(to: CGSize(width: 500, height: newHeight))
                loading = false
                
                var fullMessage = ""
                
                for try await chunk in stream {
                    let cleanChunk = chunk.replacingOccurrences(of: "<|eot_id|>", with: "")
                    fullMessage += cleanChunk

                    for char in cleanChunk {
                        try await Task.sleep(nanoseconds: 1_000_000) // 10ms delay per character
                        await MainActor.run {
                            if let lastIndex = messages.lastIndex(where: { $0.role == .ai }) {
                                messages[lastIndex].content.append(char)
                            }
                        }
                    }
                    response += cleanChunk
                }
                
 
                
               
                
                isStreaming = false
            } catch {
                print("Streaming failed:", error)
                showResult = true
                
                
                let newHeight: CGFloat = showResult ? 400 : 70
                sizeUpdater.updateSize(to: CGSize(width: 500, height: newHeight))
                
                loading = false
                isStreaming = false
                
                messages.append(ChatMessage(role:.ai, content:"Streaming failed - please try again..."))
            }
        }
        
    }
    
    func focusInput() {
        isTextFieldFocused = true
    }
    
    
        
}

struct DotLoader: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 10, height: 10)
                    .scaleEffect(isAnimating ? 0.4 : 0.7)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: isAnimating)
            }
        }
        .onAppear { isAnimating = true }

    }
}

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







//
//#Preview {
//    ContentView(messages: [ChatMessage(role: .user, content: "Write about Indore"), ChatMessage(role: .ai, content: "**Indore** is a city in central India"),
//                           ChatMessage(role: .user, content: "What is the capital of India?"), ChatMessage(role: .ai, content: "New Delhi"),ChatMessage(role: .ai, content: "Indore is a city in central Indiasdm dc m,d dm cmc d cm,c m,sc mds cmd c,d cds cm,ds cmds cm,ds cm,ds c,m sdc dscm,d scm,d scm, dscm, dscm, dsm,c ds,mc dsm,c dc csdccm cmsdcd dcdcdscdcdscds cmdscm c md cmd cmd cm dmc smc dmc dsmc dmc dmc mdc dmc md mc sdmcd mc dsmc mc sdmc dmsc dmsc mdc dmc mdc mdsc mdsc md cmds cd")]
//    )
//}
