//
//  ContentView.swift
//  SimpleRSS
//
//  Created by Dimitry on 03.05.2025.
//
import SwiftUI
import Foundation

struct ContentViewww: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var newFeedName = ""
    @State private var newFeedURL = ""
    @State private var showEditSheet = false
    @State private var feedToEdit: FeedSource?
    @State private var editedName = ""
    @State private var editedURL = ""
    @State private var selectedFeed: FeedSource? = nil
    @State private var feedSources: [FeedSource] = []
    @State private var isShowingAddFeed = false
    @State private var isEditingFeed: FeedSource? = nil
    
    var body: some View {
        HStack {
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
                
                Divider().padding(.vertical)
                
                VStack(alignment: .leading) {
                    //Text("Add New Feed").font(.headline)
                    //TextField("Feed Name", text: $newFeedName)
                    //TextField("Feed URL", text: $newFeedURL)
                    //Button("Add Feed") {
                    //    viewModel.addFeedSource(name: newFeedName, url: newFeedURL)
                    //    newFeedName = ""
                    //    newFeedURL = ""
                    //}
                    Button("Add New Feed") {
                        isShowingAddFeed = true
                    }
                    .padding()
                }
                    
                .padding()
                .sheet(isPresented: $isShowingAddFeed) {
                            AddFeedView (isPresented: $isShowingAddFeed) { name, url in
                                let newFeed = FeedSource(id: UUID(), name: name, url: url)
                                feedSources.append(newFeed)
                                selectedFeed = newFeed
                                viewModel.loadFeed(from: url)
                                viewModel.addFeedSource(name: name, url: url)
                                newFeedName = ""
                                newFeedURL = ""
                                isShowingAddFeed = false
                    }
                    .frame(width: 400, height: 200)
                }
            }
            .frame(minWidth: 250)

            VStack(alignment: .leading) {
                HStack {
                    Text(viewModel.selectedSource?.name ?? "Select a feed")
                        .font(.title2)
                    Spacer()
                    Button("Refresh") {
                        viewModel.loadSelectedFeed()
                    }
                }
                .padding(.horizontal)
                
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
            .padding()
        }
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: $showEditSheet) {
            VStack(alignment: .leading) {
                Text("Edit Feed").font(.headline).padding(.bottom)

                Text("Name")
                TextField("Feed name", text: $editedName)

                Text("URL")
                TextField("Feed URL", text: $editedURL)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        showEditSheet = false
                    }
                    Button("Save") {
                        if let original = feedToEdit {
                            viewModel.updateFeedSource(original, newName: editedName, newURL: editedURL)
                        }
                        showEditSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top)
            }
            .padding()
            .frame(width: 400)
        }
    }
}
