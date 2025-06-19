import SwiftUI
import SplitView

struct ModelInfo: Identifiable, Codable {
    var id: String { modelId }
    let modelId: String
    let tags: [String]
    let downloads: Int?
    let likes: Int?
    let lastModified: String?
    let author: String?
    
    enum CodingKeys: String, CodingKey {
        case modelId
        case tags
        case downloads
        case likes
        case lastModified
        case author
    }
}

class ModelHubViewModel: ObservableObject {
    @Published var query = ""
    @Published var searchResults: [ModelInfo] = []
    @Published var downloadingStatus: [String: String] = [:]
    @Published var downloadedModels: [String] = []

    let baseURL = "http://localhost:8001"

    func searchModels() {
        print("Searching")
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search_models?query=\(encodedQuery)") else {
            print("Invalid URL")
            return
        }

        print("Searched with URL: \(url)")

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("Network error: \(error)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                let results = try JSONDecoder().decode([ModelInfo].self, from: data)
                print("Decoded results: \(results)")
                DispatchQueue.main.async {
                    self.searchResults = results
                }
            } catch {
                print("Decoding error: \(error)")
                print("Raw data: \(String(data: data, encoding: .utf8) ?? "Unreadable")")
            }
        }.resume()
    }

    func downloadModel(_ modelId: String) {
        guard let url = URL(string: "\(baseURL)/download_model") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["model_id": modelId])

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                self.downloadingStatus[modelId] = "started"
                self.pollStatus(modelId)
            }
        }.resume()
    }

    func pollStatus(_ modelId: String) {
        guard let url = URL(string: "\(baseURL)/model_status?model_id=\(modelId)") else { return }

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            URLSession.shared.dataTask(with: url) { data, _, _ in
                if let data = data,
                   let result = try? JSONDecoder().decode([String: String].self, from: data),
                   let status = result["status"] {
                    DispatchQueue.main.async {
                        self.downloadingStatus[modelId] = status
                        if status == "ready" || status == "error" {
                            timer.invalidate()
                            self.loadLocalModels()
                        }
                    }
                }
            }.resume()
        }
    }

    func loadLocalModels() {
        guard let url = URL(string: "\(baseURL)/list_local_models") else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let models = try? JSONDecoder().decode([String].self, from: data) {
                DispatchQueue.main.async {
                    self.downloadedModels = models
                }
            }
        }.resume()
    }
}

struct ModelDetail: Codable {
    let modelId: String
    let description: String?
    let license: String?
    let author: String?
    let tags: [String]
    let downloads: Int?
    let likes: Int?
    let lastModified: String?
}

struct ModelHubView: View {
    @StateObject var viewModel = ModelHubViewModel()
    @State var searchModel: String = ""
    @State var selectedModel: String? = nil
    @State var isMLX: Bool = false
    @State var isGGUF: Bool = false
    var body: some View {
        HStack(spacing: 0){
            VStack{
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.blue)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(10)
                    .background(Color.black.opacity(0.4))
//                    .background(Color.white.opacity(0.8))
                    .clipShape(.buttonBorder)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue, lineWidth: 2)
                    )
                
                
                Image(systemName: "archivebox.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(10)
//                    .background(Color.gray.opacity(0.1))
                    .background(Color.black.opacity(0.2))
                    .clipShape(.buttonBorder)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange, lineWidth: 0)
                    )
                
            }
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(.ultraThinMaterial)
            .overlay{
                HStack{
                    Spacer()
                    Rectangle() // Right border
                        .frame(width: 0.3)
                        .foregroundColor(Color(#colorLiteral(red: 0.2310929, green: 0.2270132899, blue: 0.2324543893, alpha: 1)))
                }
            }
            VStack(spacing:0){
                HStack(spacing:20){
                    TextField("Search Model", text: $viewModel.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        
                        .padding(.horizontal,30)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.2))
                        .clipShape(.buttonBorder)
                        .overlay{
                            HStack{
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(Color.gray.opacity(0.5))
                                Spacer()
                            }
                            .padding(.horizontal,10)
                        }
                        .padding(.vertical,10)
                        .onChange(of: viewModel.query) { _,newValue in
                            viewModel.searchModels()
                            print(newValue,viewModel.searchResults)
                            
                        }
                    
                    Toggle("MLX", isOn: $isMLX)
                        .toggleStyle(.checkbox)
                    
                    Toggle("GGUF", isOn: $isGGUF)
                        .toggleStyle(.checkbox)
                        
                }
                .padding(.trailing,20)
                .padding(.leading,10)
                
                HSplit(
                    left:{
                        VStack{
                            
                            modelPreview()
                            List(viewModel.searchResults, selection: $selectedModel) { model in
                                Text(model.modelId) // Replace with your desired view
                            }
                        }
                        .frame(maxWidth: .infinity,maxHeight: .infinity, alignment: .top)
              
                         
                        .background(Color.gray.opacity(0.1))
                    }
                    ,
                    right:{
                        VStack{
                            Text("hi Everyone")
                        }
                        .frame(maxWidth: .infinity,maxHeight: .infinity)
                        
                    }
                )
                .fraction(0.32)
                .constraints(minPFraction: 0.25, minSFraction: 0.5)
                .splitter { Splitter.invisible() }
                    
                    
                    
                    
                   
                    
                
            }
            
        }
        .frame(minWidth:900, minHeight: 500)
            
        
        
    }
    
}

struct modelPreview: View {
    var body: some View {
        VStack(spacing:0){
            HStack{
                Image("hf-logo")
                    .resizable()
                    .scaledToFit()

                Text("Qwen3-30B-A3B-MLX-4bit")
                    .fontWeight(.semibold)
                
                Spacer(minLength: 0)
                
                Text("MLX")
                    .padding(.horizontal,5)
                    .padding(.vertical,2)
                    .foregroundStyle(.white)
                    .font(.footnote)
                    .background(LinearGradient(colors: [Color(#colorLiteral(red: 0.214979291, green: 0.2103910148, blue: 0.213460058, alpha: 1)),Color(#colorLiteral(red: 0.5020903349, green: 0.491376698, blue: 0.4985446334, alpha: 1))], startPoint: .topTrailing, endPoint: .bottomLeading))
                    .cornerRadius(5)
                
            }
            Spacer()
            VStack{
                HStack(alignment:.bottom){
                    
                Text("lmstudio-community")
                    .font(.callout)
                    .foregroundStyle(Color(#colorLiteral(red: 0.7662388682, green: 0.7498900294, blue: 0.7608289123, alpha: 1)))
                    
                    
                    
                    Spacer()
                    Text("19 days Ago")
                        .font(.caption2)
                        .foregroundStyle(Color(#colorLiteral(red: 0.7662388682, green: 0.7498900294, blue: 0.7608289123, alpha: 1)))
                        .fontWeight(.regular)
                }
                HStack(alignment:.bottom){
                    HStack(spacing:2){
                        Image(systemName: "heart")
                        Text("34")
                            .font(.caption2)
                    }
                    HStack(alignment:.bottom,spacing:2){
                        Image(systemName: "square.and.arrow.down")
                        Text("34452")
                            .font(.caption2)
                        
                    }
                    Spacer()
                }
            }
            
        }
        .padding(10)
        .frame(maxWidth:.infinity)
        .frame(maxHeight: 80)
//                            .background(.black)
        Divider()
        
    }
}



#Preview {
    ModelHubView()
}
