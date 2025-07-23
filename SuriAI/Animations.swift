////
////  Animations.swift
////  SuriAI
////
////  Created by Pradhumn Gupta on 18/06/25.
////
//
//import SwiftUI
//
//
//struct FadeTextRenderer: TextRenderer, Animatable{
//    var elapsedTime: Double
//    var totalDuration: Double
//    
//    var animatableData: Double {
//        get { elapsedTime }
//        set { elapsedTime = newValue }
//    }
//    
//    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
//        let runs = layout.flatMap { $0 }
//        let glyphs = runs.flatMap { $0 }
//        
//        let perGlyph = totalDuration / Double(glyphs.count)
//        print(perGlyph)
//        
//        for (i, glyph) in glyphs.enumerated() {
//            let delay = perGlyph * Double(i)
//            let fadeProgress = min(1, max(0, (elapsedTime - delay) / perGlyph))
//            ctx.opacity = fadeProgress
////            print("start",glyph,"end")
//            ctx.draw(glyph)
//        }
//            
//        
//        
//    }
//}
//
//struct FadeInText: View {
//    let text: Text
//    let content: String
//    let duration: Double
//    
//    @State private var elapsedTime = 0.0
//    
//    
//    var body: some View {
////        let totalDuration: Double = Double(content.count) * duration
//        
//        text
//            .textRenderer(FadeTextRenderer(elapsedTime: elapsedTime, totalDuration: duration))
//            .onAppear {
//                withAnimation(.linear(duration: duration)) {
//                    elapsedTime = duration
//                   
//                }
//            }
//
//    }
//}
//
//
//struct StreamedCharacter: Identifiable {
//    let id = UUID()
//    let char: Character
//    let appearanceTime: Date
//}
//
//
//class TextStreamViewModel: ObservableObject {
//    @Published var characters: [StreamedCharacter] = []
//
//    func addCharacter(_ c: Character) {
//        characters.append(StreamedCharacter(char: c, appearanceTime: Date()))
//    }
//}
//
//
//struct StreamedFadeInText: View {
//    @ObservedObject var viewModel: TextStreamViewModel
//    var duration: TimeInterval = 0.5
//
//    var body: some View {
//        TimelineView(.animation) { timeline in
//            let now = timeline.date
//            HStack(spacing: 0) {
//                ForEach(viewModel.characters) { streamedChar in
//                    let fadeProgress = min(1, max(0, now.timeIntervalSince(streamedChar.appearanceTime) / duration))
//                    Text(String(streamedChar.char))
//                        .opacity(fadeProgress)
//                }
//            }
//        }
//    }
//}
//
//
//struct AnimatedTextView: View {
//    let content: String
//    @State private var revealCount = 0
//
//    let animationSpeed = 0.05 // seconds per character
//
//    var body: some View {
//        Text(String(content.prefix(revealCount)))
//            .font(.title3)
//            .multilineTextAlignment(.leading) // Wraps lines
//            .onAppear {
//                Task {
//                    print(content.count)
//                    for i in 0...content.count {
//                        try? await Task.sleep(nanoseconds: UInt64(animationSpeed * 1_000_000_000))
//                        revealCount = i
//                    }
//                }
//            }
//    }
//}
