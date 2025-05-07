import SwiftUI
import AppKit

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
    @EnvironmentObject var viewModel: FeedViewModel
    @State private var isShowingAddFeed = false
    @State private var feedToEdit: FeedSource?
    @State private var editedName = ""
    @State private var editedURL = ""
    @State private var showEditSheet = false
    
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
                            HStack {
                                    Text(source.name)
                                        Spacer()
                                        // Use only one condition to show the circle
                                        if viewModel.sourcesWithUnreadItems.contains(source.id) {
                                            Circle()
                                                .fill(Color.gray)
                                                .frame(width: 4, height: 4)
                                        }
                                    }
                                .tag(source)
                                .contextMenu {
                                    Button("Edit") {
                                        feedToEdit = source
                                        editedName = source.name
                                        editedURL = source.url
                                        showEditSheet = true
                                    }
                                    Button("Mark All as Read") {
                                        if viewModel.selectedSource?.id == source.id {
                                            viewModel.markAllAsRead()
                                        }
                                    }
                                    Button("Delete", role: .destructive) {
                                        viewModel.deleteFeedSource(source)
                                    }
                                }
                        }
                    }
                    
                    .onChange(of: viewModel.selectedSource) {
                        viewModel.loadSelectedFeed()
                        viewModel.objectWillChange.send()
                    }
                    
                    .frame(height: CGFloat(viewModel.feedSources.count * 32), alignment: .top)
                                
                    Spacer() // Add spacer to push content to the top
                    
                    Button("Add New Feed") {
                        isShowingAddFeed = true
                    }
                    .toolbar {
                                ToolbarItem(placement: .primaryAction) {
                                    Button(action: {
                                        viewModel.refreshAllFeeds(background: false)
                                    }) {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .help("Refresh All Feeds")
                                }
                            }
                    .padding()
                    
                }
            }
            .sheet(isPresented: $isShowingAddFeed) {
                AddFeedView(isPresented: $isShowingAddFeed) { name, url in
                    if !name.isEmpty && !url.isEmpty {
                        viewModel.addFeedSource(name: name, url: url)
                    }
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
                                viewModel.forceRefreshSelectedFeed()
                            }
                            Button("Mark All as Read") {
                                viewModel.markAllAsRead()
                            }
                        }
                        .padding()
                        
                        if viewModel.isLoading {
                            ProgressView("Loading feed...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(viewModel.feedItems) { item in
                                if let url = URL(string: item.link) {
                                    Button {
                                        // First mark as read
                                        viewModel.markAsRead(item: item)
                                        // Then open the URL
                                        NSWorkspace.shared.open(url)
                                    } label: {
                                        HStack {
                                            Text(item.title)
                                                .fontWeight(viewModel.isRead(item: item) ? .regular : .bold)
                                                .foregroundColor(viewModel.isRead(item: item) ? .secondary : .primary)
                                            Spacer()
                                            if !viewModel.isRead(item: item) {
                                                Circle()
                                                    .fill(Color.blue)
                                                    .frame(width: 8, height: 8)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .contextMenu {
                                        Button("Open in Browser") {
                                            viewModel.markAsRead(item: item)
                                            NSWorkspace.shared.open(url)
                                        }
                                        
                                        if viewModel.isRead(item: item) {
                                            Button("Mark as Unread") {
                                                viewModel.markAsUnread(item: item)
                                            }
                                        } else {
                                            Button("Mark as Read") {
                                                viewModel.markAsRead(item: item)
                                            }
                                        }
                                    }
                                }
                            }

                        }
                    }
                }
            }
            
            .focusable(true)
                    .onKeyPress(.escape) {
                        if isShowingAddFeed {
                            isShowingAddFeed = false
                            return .handled
                        } else if showEditSheet {
                            showEditSheet = false
                            return .handled
                        } else if viewModel.selectedSource != nil {
                            viewModel.clearSelection()
                            return .handled
                        }
                        return .ignored
                    }
        
    }
}
