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

@Observable
final class Presenter: NSObject, NSFilePresenter, Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = .init()
    let logger: AsyncStream<String>.Continuation
    @MainActor var hasConflicts: Bool = false
    init(url: URL, logger: AsyncStream<String>.Continuation) {
        self.presentedItemURL = url
        self.logger = logger
        super.init()
        self.log("presenter init")
        self.presentedItemOperationQueue.addOperation {
            self.log("btw I am on an operation queue")
        }
    }

    func log(_ message: String) {
        print("[NSFilePresenterLogger] \(message)")
        self.logger.yield(message)
    }

    func relinquishPresentedItem(toReader reader: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        self.log("relinquishPresentedItem(toReader:)")
        reader({
            self.log("relinquishPresentedItem(toReader:) reacquire callback")
        })
    }

    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        self.log("relinquishPresentedItem(toWriter:)")
        writer({
            self.log("relinquishPresentedItem(toWriter:) reacquire callback")
        })
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
        Task { @MainActor in
            let resourceValues = try! self.presentedItemURL!.resourceValues(forKeys: attributes)
            self.log(" ===> \(resourceValues)")
            if let hasConflicts = resourceValues.ubiquitousItemHasUnresolvedConflicts {
                self.hasConflicts = hasConflicts
            }
        }
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
    let conflictMonitor: AsyncMutex<()> = .init(())
    init() {
        let stream: AsyncStream<String>
        (stream, self.logger) = AsyncStream.makeStream(of: String.self)
        Task { @MainActor in
            for await msg in stream {
                self.logMessages.append((id: self.logMessages.count, msg: msg))
            }
        }
        self.log("hullo")

        
    }

    func log(_ message: String) {
        print("\(message)")
        self.logger.yield(message)
    }
}

struct ContentView: View {
    @State var state = MyState()
    @State private var isImporting: Bool = false

    var body: some View {
    
        VStack {
            ScrollView {
                ForEach(state.logMessages, id: \.id) { message in
                    Text("\(message.id). \(message.msg)")
                }
            }
            Button("Clear") {
                self.state.logMessages.removeAll()
            }
            Button("Select File") {
                self.isImporting = true
            }.fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    guard url.startAccessingSecurityScopedResource() else {
                        fatalError("couldn't access \(url)")
                    }

                    self.state.log("importing: \(url.path)")
                    self.state.presenter = Presenter(url: url, logger: self.state.logger)
                    
                    NSFileCoordinator.addFilePresenter(self.state.presenter!)
                    print("==> presenters: \(NSFileCoordinator.filePresenters)")

                case .failure:
                    self.state.logger.yield("import failed")
                }
            }
            Button("Append Something") {
                self.coordinateSomething(write: true)
                
            }
            Button("Read Something") {
                self.coordinateSomething(write: false)
            }
        }
        .padding()
    }
    
    func coordinateSomething(write: Bool) {
        let id = Int.random(in: 0..<1000000)
        let logger = self.state.logger
        @Sendable func log(_ message: String) {
            let message = "\(id) \(message)"
            print("\(message)")
            logger.yield(message)
        }
        guard let presenter = self.state.presenter, let baseURL = presenter.presentedItemURL else {
            log("no presenter/url")
            return
        }
        Task {
            do {
                guard baseURL.startAccessingSecurityScopedResource() else {
                    log("startAccessingSecurityScopedResource failed")
                    return
                }
                defer {
                    log("stopAccessingSecurityScopedResource")
                    baseURL.stopAccessingSecurityScopedResource()
                }
                /*
                let supportedSyncControls = try baseURL.resourceValues(forKeys: [.ubiquitousItemSupportedSyncControlsKey])
                log("supportedSyncControls=\(supportedSyncControls)")
                return
                log("will pauseSyncForUbiquitousItem")
                try await FileManager.default.pauseSyncForUbiquitousItem(at: baseURL)
                */
                log("will coordinateAsync")

                try await coordinateAsync(url: baseURL, filePresenter: nil, write: write, idForDebugging: id) { url in
                    log("coordinateAsync callback with url=\(url)")
                    if write {
                        let fh = try FileHandle(forUpdating: url)
                        try fh.seekToEnd()
                        
                        let data = "\(id)\n".data(using: .utf8)!
                        for c in data {
                            log("wrote: \(String(data: Data([c]), encoding: .utf8)!)")
                            try fh.write(contentsOf: Data([c]))
                            try! await Task.sleep(for: .milliseconds(200))
                        }
                        try fh.close()
                    } else {
                        let fh = try FileHandle(forReadingFrom: url)
                        let data = try fh.readToEnd()
                        try fh.close()
                        log("read: \(String(data: data ?? Data(), encoding: .utf8)!)")
                    }
                    log("coordinateAsync callback finished r/w")
                }
                log("coordinateAsync finished")
                
            } catch let e {
                log("coordinateAsync error: \(e)")
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
