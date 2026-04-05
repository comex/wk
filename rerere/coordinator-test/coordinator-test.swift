//
//  coordinator_testApp.swift
//  coordinator-test
//
//  Created by Nicholas Allegra on 4/5/26.
//  Copyright © 2026 Nicholas Allegra. All rights reserved.
//

import SwiftUI
import Observation
internal import UniformTypeIdentifiers


final class Presenter: NSObject, NSFilePresenter, Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = .init()
    let logger: AsyncStream<String>.Continuation
    
    init(url: URL, logger: AsyncStream<String>.Continuation) {
        self.presentedItemURL = url
        self.logger = logger
        super.init()
        self.log("presenter init")
    }

    func log(_ message: String) {
        print("[NSFilePresenterLogger] \(message)")
        self.logger.yield(message)
    }

    func relinquishPresentedItem(toReader reader: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        self.log("relinquishPresentedItem(toReader:)")
    }

    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        self.log("relinquishPresentedItem(toWriter:)")
    }


    func savePresentedItemChanges() async throws {
        self.log("savePresentedItemChanges()")
    }


    func accommodatePresentedItemDeletion() async throws {
        self.log("accommodatePresentedItemDeletion()")
    }


    func accommodatePresentedItemEviction() async throws {
        self.log("accommodatePresentedItemEviction()")
    }
    func presentedItemDidMove(to newURL: URL) {
        self.log("presentedItemDidMove(to: \(newURL))")
    }

    func presentedItemDidChange() {
        self.log("presentedItemDidChange()")
    }
    func presentedItemDidChangeUbiquityAttributes(_ attributes: Set<URLResourceKey>) {
        self.log("presentedItemDidChangeUbiquityAttributes(\(attributes))")
    }
    func presentedItemDidGain(_ version: NSFileVersion) {
        self.log("presentedItemDidGain(\(version))")
    }
    func presentedItemDidLose(_ version: NSFileVersion) {
        self.log("presentedItemDidLose(\(version))")
    }
    func presentedItemDidResolveConflict(_ version: NSFileVersion) {
        self.log("presentedItemDidResolveConflict(\(version))")
    }
    func accommodatePresentedSubitemDeletion(at url: URL) async throws {
        self.log("accommodatePresentedSubitemDeletion(at: \(url))")
    }
    func presentedSubitemDidAppear(at url: URL) {
        self.log("presentedSubitemDidAppear(at: \(url))")
    }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        self.log("presentedSubitem(at: \(oldURL), didMoveTo: \(newURL))")
    }
    func presentedSubitemDidChange(at url: URL) {
        self.log("presentedSubitemDidChange(at: \(url))")
    }
    func presentedSubitem(at url: URL, didGain version: NSFileVersion) {
        self.log("presentedSubitem(at: \(url), didGain: \(version))")
    }
    func presentedSubitem(at url: URL, didLose version: NSFileVersion) {
        self.log("presentedSubitem(at: \(url), didLose: \(version))")
    }
    func presentedSubitem(at url: URL, didResolve version: NSFileVersion) {
        self.log("presentedSubitem(at: \(url), didResolve: \(version))")
    }
}

@MainActor @Observable final class MyState {
    var logMessages: [(id: Int, msg: String)] = []
    let logger: AsyncStream<String>.Continuation
    var presenter: Presenter? = nil
    init() {
        let stream: AsyncStream<String>
        (stream, self.logger) = AsyncStream.makeStream(of: String.self)
        Task { @MainActor in
            for await msg in stream {
                self.logMessages.append((id: self.logMessages.count, msg: msg))
            }
        }
        self.logger.yield("hullo")

        
    }
}

struct ContentView: View {
    @State var state = MyState()
    @State private var isImporting: Bool = false
    func log(_ message: String) {
        print("\(message)")
        self.state.logger.yield(message)
    }
    var body: some View {
        VStack {
            ForEach(state.logMessages, id: \.id) { message in
                Text("\(message.id). \(message.msg)")
            }
            Button("Select File") {
                self.isImporting = true
            }.fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    self.log("importing: \(url.path)")
                    self.state.presenter = Presenter(url: url, logger: self.state.logger)
                case .failure:
                    self.log("import failed")
                }
            }
            Button("Append Something") {
                self.coordinateSomething(write: true)
                
            }
            Button("Read Something") {
                self.coordinateSomething(write: true)
            }
        }
        .padding()
    }
    
    func coordinateSomething(write: Bool) {
        guard let presenter = self.state.presenter, let baseURL = presenter.presentedItemURL else {
            self.log("no presenter/url")
            return
        }
        Task {
            self.log("will coordinateAsync")
            do {
                guard baseURL.startAccessingSecurityScopedResource() else {
                    self.log("startAccessingSecurityScopedResource failed")
                    return
                }
                defer { baseURL.stopAccessingSecurityScopedResource() }
                try await coordinateAsync(url: baseURL, filePresenter: presenter, write: write) { url in
                    await self.log("coordinateAsync callback")
                    if write {
                        let fh = try FileHandle(forUpdating: url)
                        try fh.seekToEnd()
                        try fh.write(contentsOf: "Hello\n".data(using: .utf8)!)
                        try fh.close()
                    } else {
                        let fh = try FileHandle(forReadingFrom: url)
                        

                        try fh.close()
                    }
                }
                
            } catch let e {
                self.log("coordinateAsync error: \(e)")
            }
        }

    }
}

#Preview {
    ContentView()
}

@main
struct coordinator_testApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
