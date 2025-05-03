// SimpleRSSReader.swift
// A minimal macOS RSS reader using SwiftUI

import SwiftUI
import Foundation

struct FeedItem: Identifiable {
    let id = UUID()
    let title: String
    let link: String
}

struct FeedSource: Identifiable, Equatable, Hashable, Codable {
    let id : UUID
    let name: String
    let url: String
}

class FeedViewModel: ObservableObject {
    @Published var feedSources: [FeedSource] = [] {
        didSet {
            saveFeeds()
        }
    }
    @Published var selectedSource: FeedSource? {
        didSet {
            saveFeeds()
        }
    }
    @Published var feedItems: [FeedItem] = []
    @Published var isLoading = false
    
    private var seenLinks: Set<String> = []
    
    private let feedsFileName = "feeds.json"
    
    init() {
        loadFeeds()
    }

    private var feedsFileURL: URL? {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appSupportURL = documentsURL.appendingPathComponent("SimpleRSSReader")
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        }
        return appSupportURL.appendingPathComponent(feedsFileName)
    }
    
    func saveFeeds() {
        guard let url = feedsFileURL else { return }
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(feedSources)
            try data.write(to: url)
        } catch {
            print("Failed to save feeds: \(error)")
        }
    }
    
    func loadFeeds() {
        guard let url = feedsFileURL else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let savedFeeds = try decoder.decode([FeedSource].self, from: data)
            DispatchQueue.main.async {
                self.feedSources = savedFeeds
                self.selectedSource = savedFeeds.first
                if let firstURL = savedFeeds.first?.url {
                    self.loadFeed(from: firstURL)
                }
            }
        } catch {
            print("Failed to load feeds: \(error)")
        }
    }
    
    func addFeedSource(name: String, url: String) {
        guard !feedSources.contains(where: { $0.url == url }) else { return }
        let newSource = FeedSource(id: UUID(), name: name, url: url)
        feedSources.append(newSource)
        selectedSource = newSource              // <— set it as selected
        loadFeed(from: url)                     // <— trigger loading
    }

    func loadSelectedFeed() {
        guard let source = selectedSource else { return }
        isLoading = true
        loadFeed(from: source.url)
    }

    func updateFeedSource(_ feed: FeedSource, newName: String, newURL: String) {
        guard let index = feedSources.firstIndex(of: feed) else { return }
        feedSources[index] = FeedSource(id: feed.id, name: newName, url: newURL)
        
        // Update selection if needed
        if selectedSource?.id == feed.id {
            selectedSource = feedSources[index]
            loadFeed(from: newURL)
        }
    }

    func deleteFeedSource(_ feed: FeedSource) {
        feedSources.removeAll { $0.id == feed.id }
        if selectedSource?.id == feed.id {
            selectedSource = nil
            feedItems = []
        }
    }
    
    func loadFeed(from urlString: String) {
        guard let url = URL(string: urlString) else {
            isLoading = false
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
                DispatchQueue.main.async {
                    // Set loading to false regardless of success or failure
                    self.isLoading = false
                    
                    guard let data = data else { return }
                    let parser = RSSParser(data: data)
                    let items = parser.parse()
                    self.feedItems = items
                    self.seenLinks.formUnion(items.map { $0.link })
                }
            }
            task.resume()
        }

    func isNew(item: FeedItem) -> Bool {
        !seenLinks.contains(item.link)
    }
    
}

class RSSParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var items: [FeedItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""

    init(data: Data) {
        self.data = data
    }

    func parse() -> [FeedItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if currentElement == "item" {
            currentTitle = ""
            currentLink = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "title": currentTitle += string
        case "link": currentLink += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            let item = FeedItem(title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                link: currentLink.trimmingCharacters(in: .whitespacesAndNewlines))
            items.append(item)
        }
    }
}

@main
struct SimpleRSSReaderApp: App {
    @StateObject private var feedViewModel = FeedViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(feedViewModel)
        }
        .defaultSize(width: 900, height: 800)
    }
}
