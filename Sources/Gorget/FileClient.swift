import Foundation
import Dependencies

struct FileClient {
    var replaceNames: ([FileService.NameChangeSet], URL) async throws -> Bool
    var createDirectory: (URL) async throws -> Void
    var copyFiles: ([FileService.URLCopySet]) async throws -> Void
    var removeFiles: ([URL]) async throws -> Void
    var retrieveFiles: (URL) async throws -> [FileService.ResourcedURL]
    var createRevisedResourcedURL: (FileService.ResourcedURL, String, [URL : FileService.ResourcedURL]) async -> [URL: FileService.ResourcedURL]
}

// live
extension FileClient {
    static let liveValue = Self(
        replaceNames: { nameChangeSets, destination in
            try await FileService.live.replaceNames(using: nameChangeSets, atURL: destination)
        },
        createDirectory: { destination in
            try await FileService.live.createDirectory(at: destination)
        },
        copyFiles: { copySets in
            try await FileService.live.copyFiles(copySets)
        },
        removeFiles: { urls in
            try await FileService.live.removeFiles(urls)
        },
        retrieveFiles: { source in
            try await FileService.live.retrieveFiles(from: source)
        },
        createRevisedResourcedURL: { resourcedURL, bareName, nameMap in
            await FileService.live.createRevisedResourcedURL(resourcedURL, bareName, nameMap)
        }
    )
}

private enum FileClientKey: DependencyKey {
    static let liveValue = FileClient.liveValue
    static let testValue = FileClient.testValue
}

extension DependencyValues {
  var fileClient: FileClient {
    get { self[FileClientKey.self] }
    set { self[FileClientKey.self] = newValue }
  }
}


extension FileClient: TestDependencyKey {
    static let testURLs: (URL) -> [FileService.ResourcedURL] = { source in
        [
            FileService.ResourcedURL(
                url: source.appending(path: "1.txt"),
                isDirectory: false,
                contentType: .text,
                contentModificationDate: Date.now,
                isRegularFile: true,
                originalName: "1.txt"
            ),
            FileService.ResourcedURL(
                url: source.appending(path: "2.html"),
                isDirectory: false,
                contentType: .text,
                contentModificationDate: Date.now,
                isRegularFile: true,
                originalName: "2.html"
            ),
            FileService.ResourcedURL(
                url: source.appending(path: "3.rss"),
                isDirectory: false,
                contentType: .xml,
                contentModificationDate: Date.now,
                isRegularFile: true,
                originalName: "3.rss"
            ),
            FileService.ResourcedURL(
                url: source.appending(path: "4.jpg"),
                isDirectory: false,
                contentType: .jpeg,
                contentModificationDate: Date.now,
                isRegularFile: true,
                originalName: "4.jpg"
            ),
            FileService.ResourcedURL(
                url: source.appending(path: "5.png"),
                isDirectory: false,
                contentType: .png,
                contentModificationDate: Date.now,
                isRegularFile: true,
                originalName: "5.png"
            ),
        ]
    }
    static let testValue = Self(
        replaceNames: { nameChangeSet, url in
            return true
        },
        createDirectory: { rootUrl in
            
        },
        copyFiles: { copySets in
            
        },
        removeFiles: { urls in
            
        },
        retrieveFiles: testURLs,
        createRevisedResourcedURL: { resourcedURL, bareName, nameMap in
            return nameMap
        }
    )
}
