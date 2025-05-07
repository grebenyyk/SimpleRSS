// SimpleRSSReader.swift
// A minimal macOS RSS reader using SwiftUI

import SwiftUI
import Foundation
import Combine

struct FeedItem: Identifiable, Codable, Equatable {
    var id: UUID { UUID(uuidString: link) ?? UUID() }
    let title: String
    let link: String
    var isRead: Bool = false
    
    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        return lhs.link == rhs.link
    }
}

struct ReadState: Codable {
    var readLinks: Set<String> = []
    var lastReadDates: [String: Date] = [:]
    }


struct FeedSource: Identifiable, Equatable, Hashable, Codable {
    let id : UUID
    let name: String
    let url: String
}

struct CacheData: Codable {
    var feedCache: [String: [FeedItem]]
    var lastFetchTimes: [String: Date]
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: FeedViewModel?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel?.refreshAllFeeds(background: false)
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        viewModel?.refreshAllFeeds(background: false)
    }
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
    @Published var readLinks: Set<String> = [] {
        didSet {
            saveReadState()
        }
    }
    @Published var sourcesWithUnreadItems: Set<UUID> = []
    
    private var seenLinks: Set<String> = []
    private let feedsFileName = "feeds.json"
    private let readStateFileName = "readstate.json"
    private var feedCache: [String: [FeedItem]] = [:]
    private var lastFetchTimes: [String: Date] = [:]
    private let cacheDuration: TimeInterval = 10 * 60 // 10 minutes
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadFeeds()
        loadReadState()
        loadFeedCache()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateUnreadStatus()
        }
        
        Timer.publish(every: 15*60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshAllFeeds(background: true)
            }
            .store(in: &cancellables)

    }

    private var feedsFileURL: URL? {
            getFileURL(for: feedsFileName)
        }
        
        private var readStateFileURL: URL? {
            getFileURL(for: readStateFileName)
        }
    
    func getFileURL(for fileName: String) -> URL? {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appSupportURL = documentsURL.appendingPathComponent("SimpleRSSReader")
        
        // Create directory if needed
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            do {
                try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
                print("✅ Created directory at: \(appSupportURL.path)")
            } catch {
                print("❌ Failed to create directory: \(error)")
                return nil
            }
        }
        
        let fileURL = appSupportURL.appendingPathComponent(fileName)
        print("📄 Using file URL: \(fileURL.path)")
        return fileURL
    }

    
    func saveFeeds() {
        guard let url = feedsFileURL else { return }
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(feedSources)
            try data.write(to: url)
            print("✅ Saved \(feedSources.count) feeds to:\n\(url.path)")
                } catch {
                    print("❌ Failed to save feeds: \(error)")
        }
    }
    
    deinit {
        saveFeeds()
        saveReadState()
    }
    
    func loadFeeds() {
        guard let url = feedsFileURL else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
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
            }
        } catch {
            print("Failed to load feeds: \(error)")
            self.feedSources = []
        }
    }
    
    func refreshAllFeeds(background: Bool = false) {
        // Store the currently selected source
        let currentlySelected = selectedSource
        
        // Set loading state if not in background mode
        if !background {
            isLoading = true
        }
        
        // Iterate through all feed sources and refresh each one
        for source in feedSources {
            // Clear cache timestamp to force refresh
            lastFetchTimes[source.url] = Date(timeIntervalSince1970: 0)
            
            // Load the feed without changing selection
            loadFeedWithoutSelecting(from: source.url)
        }
        
        // Ensure we maintain the same selection after refresh
        DispatchQueue.main.async {
            self.selectedSource = currentlySelected
            
            // If a feed was selected, make sure we show its content
            if let selected = currentlySelected {
                self.feedItems = self.feedCache[selected.url] ?? []
            }
            
            // Update loading state
            if !background {
                self.isLoading = false
            }
        }
    }

    // Add this helper method to load a feed without changing selection
    private func loadFeedWithoutSelecting(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                guard let data = data else { return }
                
                let parser = RSSParser(data: data)
                let newItems = parser.parse()
                
                // Update cache without changing the displayed items
                self.updateFeedCache(urlString: urlString, newItems: newItems)
            }
        }
        task.resume()
    }

    // Helper method to update cache without affecting displayed items
    private func updateFeedCache(urlString: String, newItems: [FeedItem]) {
        // Update the cache
        feedCache[urlString] = newItems
        lastFetchTimes[urlString] = Date()
        
        // Update unread status
        updateUnreadStatus()
        
        // Save cache
        saveFeedCache()
    }


    
    func saveReadState() {
        guard let url = readStateFileURL else { return }
        do {
            let readState = ReadState(readLinks: readLinks)
            let encoder = JSONEncoder()
            let data = try encoder.encode(readState)
            try data.write(to: url, options: .atomic)
            print("Successfully saved read state with \(readLinks.count) items")
            } catch {
                print("Failed to save read state: \(error)")
            }
        }
    func saveReadStateIfNeeded() {
        saveReadState()
    }
    
    func loadReadState() {
        guard let url = readStateFileURL else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let savedReadState = try decoder.decode(ReadState.self, from: data)
                self.readLinks = savedReadState.readLinks
                print("Successfully loaded read state with \(savedReadState.readLinks.count) items")
            }
        } catch {
            print("Failed to load read state: \(error)")
        }
    }
    
    func addFeedSource(name: String, url: String) {
        guard !feedSources.contains(where: { $0.url == url }) else { return }
        let newSource = FeedSource(id: UUID(), name: name, url: url)
        DispatchQueue.main.async { [weak self] in
                self?.feedSources.append(newSource)
                self?.selectedSource = newSource
                self?.loadFeed(from: url)
            }
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
        
        // Check if we have a recent cache
        let now = Date()
        if let lastFetch = lastFetchTimes[urlString],
           now.timeIntervalSince(lastFetch) < cacheDuration,
           let cachedItems = feedCache[urlString] {
            // Use cached data if it's recent enough
            DispatchQueue.main.async {
                self.isLoading = false
                self.feedItems = cachedItems
                print("Using cached data for \(urlString)")
            }
            return
        }
        
        // Otherwise fetch fresh data
        isLoading = true
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                guard let data = data else {
                    // If we have cached data, use it as fallback
                    if let cachedItems = self.feedCache[urlString] {
                        self.feedItems = cachedItems
                        print("Network error, using cached data for \(urlString)")
                    }
                    return
                }
                
                let parser = RSSParser(data: data)
                let newItems = parser.parse()
                
                // Merge with existing items to preserve read states
                self.updateFeedItems(urlString: urlString, newItems: newItems)
                
                // Update cache
                self.feedCache[urlString] = self.feedItems
                self.lastFetchTimes[urlString] = now
                self.updateUnreadStatus()
                
                // Save cache to disk
                self.saveFeedCache()
            }
        }
        task.resume()
    }

    private func updateFeedItems(urlString: String, newItems: [FeedItem]) {
        // Get existing items
        let existingItems = feedCache[urlString] ?? []
        
        // Find truly new items (not in existing items)
        let existingLinks = Set(existingItems.map { $0.link })
        let brandNewItems = newItems.filter { !existingLinks.contains($0.link) }
        
        if !brandNewItems.isEmpty {
            print("Found \(brandNewItems.count) new items in feed")
        }
        
        // Merge items, putting new ones at the top
        feedItems = brandNewItems + existingItems
        
        // Limit to reasonable number to prevent unlimited growth
        if feedItems.count > 200 {
            feedItems = Array(feedItems.prefix(200))
        }
    }

    // Save and load cache methods
    private func saveFeedCache() {
        guard let url = getFileURL(for: "feedcache.json") else { return }
        
        do {
            let cacheData = CacheData(
                feedCache: feedCache,
                lastFetchTimes: lastFetchTimes
            )
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(cacheData)
            try data.write(to: url)
            print("✅ Saved feed cache")
        } catch {
            print("❌ Failed to save feed cache: \(error)")
        }
    }

    private func loadFeedCache() {
        guard let url = getFileURL(for: "feedcache.json") else { return }
        
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let cacheData = try decoder.decode(CacheData.self, from: data)
                
                self.feedCache = cacheData.feedCache
                self.lastFetchTimes = cacheData.lastFetchTimes
                print("✅ Loaded feed cache")
            }
        } catch {
            print("❌ Failed to load feed cache: \(error)")
        }
    }

    public func updateUnreadStatus() {
        for source in feedSources {
            if feedCache[source.url]?.contains(where: { !readLinks.contains($0.link) }) ?? false {
                sourcesWithUnreadItems.insert(source.id)
            } else {
                sourcesWithUnreadItems.remove(source.id)
            }
        }
        objectWillChange.send()
    }
    
    func refreshUnreadStatus() {
        updateUnreadStatus()
    }

    
    func forceRefreshSelectedFeed() {
        guard let source = selectedSource else { return }
        
        let urlString = source.url
        lastFetchTimes[urlString] = Date(timeIntervalSince1970: 0)
        
        
        loadSelectedFeed()
    }

    
    func isNew(item: FeedItem) -> Bool {
        !seenLinks.contains(item.link)
    }
    
    func isRead(item: FeedItem) -> Bool {
        readLinks.contains(item.link)
    }
    
    func markAsRead(item: FeedItem) {
            readLinks.insert(item.link)
            saveReadState()
            updateUnreadStatus()
            objectWillChange.send()
        }
        
    func markAsUnread(item: FeedItem) {
            readLinks.remove(item.link)
            saveReadState()
            updateUnreadStatus()
            objectWillChange.send()
        }
        
    func markAllAsRead() {
        for item in feedItems {
            readLinks.insert(item.link)
            }
        saveReadState()
        updateUnreadStatus()
        }
    
    func hasUnreadItems(for source: FeedSource) -> Bool {
        // Use cached data instead of making a network request
        if let cachedItems = feedCache[source.url] {
            return cachedItems.contains { !readLinks.contains($0.link) }
        }
        
        // If no cache exists, default to false or trigger a background fetch
        return false
    }
        
    
    func clearSelection() {
        DispatchQueue.main.async {
            self.selectedSource = nil
        }
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
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.appearsActive) private var appearsActive
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(feedViewModel)
                .onAppear {
                     // Configure the app delegate here
                     appDelegate.viewModel = feedViewModel
                 }
                .onChange(of: appearsActive) { oldValue, newValue in
                        if newValue == true { // Window became active
                            feedViewModel.refreshAllFeeds(background: false)
                        }
                    }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    feedViewModel.saveFeeds()
                    feedViewModel.saveReadState()
                }
        }
        .defaultSize(width: 900, height: 800)
        .windowResizability(.contentSize)

    }
}

