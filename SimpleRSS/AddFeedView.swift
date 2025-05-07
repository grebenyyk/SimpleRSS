//
//  AddFeedView.swift
//  SimpleRSS
//
//  Created by Dimitry on 03.05.2025.
//
import SwiftUI
import Foundation
import FeedKit

struct AddFeedView: View {
    @State private var name = ""
    @State private var url = ""
    @State private var isValidating = false
    @State private var validationError: String? = nil
    @State private var showingError = false
    @Binding var isPresented: Bool
    
    var onAdd: (String, String) -> Void

    var body: some View {
            VStack(spacing: 20) {
                Text("Add New Feed")
                    .font(.headline)

                TextField("Feed Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .disabled(isValidating)

                TextField("Feed URL", text: $url)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .disabled(isValidating)

                if showingError, let errorMessage = validationError {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        isPresented = false
                        onAdd("", "") // Maintain your existing pattern for cancel
                    }
                    .disabled(isValidating)
                    .keyboardShortcut(.cancelAction)

                    Button(isValidating ? "Validating..." : "Add") {
                        validateAndAdd()
                    }
                    .disabled(name.isEmpty || url.isEmpty || isValidating)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal)
            }
            .padding()
            .frame(width: 400)
            
        }
        
    private func validateAndAdd() {
        guard !name.isEmpty, !url.isEmpty else { return }
        
        isValidating = true
        validationError = nil
        showingError = false
        
        guard let feedURL = URL(string: url) else {
            isValidating = false
            validationError = "Invalid URL format"
            showingError = true
            return
        }
        
        let parser = FeedParser(URL: feedURL)
        parser.parseAsync { result in
            DispatchQueue.main.async {
                self.isValidating = false
                
                switch result {
                case .success(let feed):
                    // Check if we got any feed type
                    if feed.rssFeed != nil || feed.atomFeed != nil || feed.jsonFeed != nil {
                        // Feed is valid
                        self.onAdd(self.name, self.url)
                        self.isPresented = false
                    } else {
                        self.validationError = "Feed format not recognized"
                        self.showingError = true
                    }
                    
                case .failure(let error):
                    self.validationError = "Error parsing feed: \(error.localizedDescription)"
                    self.showingError = true
                }
            }
        }
    }

}

struct KeyPressHandler: NSViewRepresentable {
    let key: KeyEquivalent
    let action: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.key = key
        view.action = action
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyView {
            view.key = key
            view.action = action
        }
    }
    
    class KeyView: NSView {
        var key: KeyEquivalent = .escape
        var action: (() -> Void)? = nil
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Escape key code
                action?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
