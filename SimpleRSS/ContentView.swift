import SwiftUI

struct EditFeedView: View {
    @Binding var feedToEdit: FeedSource?
    @Binding var editedName: String
    @Binding var editedURL: String
    var onSave: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("Edit Feed").font(.headline).padding(.bottom)

            Text("Name")
            TextField("Feed name", text: $editedName)

            Text("URL")
            TextField("Feed URL", text: $editedURL)

            HStack {
                Spacer()
                Button("Cancel") {
                    feedToEdit = nil
                }
                Button("Save") {
                    onSave(editedName, editedURL)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 400)
    }
}


struct ContentView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var showAddFeedSheet = false
    @State private var showEditSheet = false
    @State private var isShowingAddFeed = false
    @State private var feedToEdit: FeedSource?
    @State private var editedName = ""
    @State private var editedURL = ""
    @State private var newFeedName = ""
    @State private var newFeedURL = ""
    @State private var selectedFeed: FeedSource? = nil
    @State private var feedSources: [FeedSource] = []
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedSource = nil
                    }
                
                VStack {
                    List(selection: $viewModel.selectedSource) {
                        ForEach(viewModel.feedSources) { source in
                            Text(source.name)
                                .tag(source)
                                .contextMenu {
                                    Button("Edit") {
                                        feedToEdit = source
                                        editedName = source.name
                                        editedURL = source.url
                                        showEditSheet = true
                                    }
                                    Button("Delete", role: .destructive) {
                                        viewModel.deleteFeedSource(source)
                                    }
                                }
                        }
                    }
                    
                    .onChange(of: viewModel.selectedSource) {
                        viewModel.loadSelectedFeed()
                    }
                    
                    .frame(height: CGFloat(viewModel.feedSources.count * 32), alignment: .top)
                                
                    Spacer() // Add spacer to push content to the top
                    
                    Button("Add New Feed") {
                        isShowingAddFeed = true
                    }
                    .padding()
                }
            }
                .sheet(isPresented: $isShowingAddFeed) {
                    AddFeedView { name, url in
                        if !name.isEmpty && !url.isEmpty {  // Only proceed if we have valid data
                            let newFeed = FeedSource(id: UUID(), name: name, url: url)
                            feedSources.append(newFeed)
                            selectedFeed = newFeed
                            viewModel.loadFeed(from: url)
                            viewModel.addFeedSource(name: name, url: url)
                            newFeedName = ""
                            newFeedURL = ""
                        }
                        isShowingAddFeed = false
                    }
                }
                
                .sheet(isPresented: $showEditSheet) {
                    EditFeedView(feedToEdit: $feedToEdit, editedName: $editedName, editedURL: $editedURL) { name, url in
                        if let original = feedToEdit {
                            viewModel.updateFeedSource(original, newName: name, newURL: url)
                        }
                        showEditSheet = false
                    }
                    .frame(width: 400, height: 200)
                }
                
                
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
            } detail: {
                if viewModel.selectedSource == nil {
                    ContentUnavailableView("Add or Select a Feed",
                                           systemImage: "newspaper")
                    .padding()
                } else {
                    // Detail view showing feed items
                    VStack(alignment: .leading) {
                        HStack {
                            Text(viewModel.selectedSource?.name ?? "Select a feed")
                                .font(.title2)
                            Spacer()
                            Button("Refresh") {
                                viewModel.loadSelectedFeed()
                            }
                        }
                        .padding()
                        
                        if viewModel.isLoading {
                            ProgressView("Loading feed...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(viewModel.feedItems) { item in
                                if let url = URL(string: item.link) {
                                    Link(destination: url) {
                                        HStack {
                                            Text(item.title)
                                                .fontWeight(viewModel.isNew(item: item) ? .bold : .regular)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        .focusable()
        .onKeyPress(.escape) {
            viewModel.selectedSource = nil
            return .handled
        }
    }
}
