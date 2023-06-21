import CryptoKit
import Foundation
import RegexBuilder
import UniformTypeIdentifiers

actor FileService {
    static let live = FileService()
    private static let hashValuePattern = Regex {
        "SHA1 digest: "
        Capture {
            OneOrMore(.anyNonNewline)
        }
        Anchor.endOfLine
    }

    struct ResourcedURL: Sendable {
        let url: URL
        let isDirectory: Bool
        let contentType: UTType
        let contentModificationDate: Date
        let isRegularFile: Bool
        let originalName: String
        
        func replacing(url: URL) -> Self {
            return ResourcedURL(
                url: url,
                isDirectory: self.isDirectory,
                contentType: self.contentType,
                contentModificationDate: self.contentModificationDate,
                isRegularFile: self.isRegularFile,
                originalName: self.originalName
            )
        }
    }
    typealias URLCopySet = (src: URL, dest: URL)
    typealias NameChangeSet = (prev: String, next: String)
    struct RootNotDirectory: Error {}
    struct DestinationCreationFailure: Error {}
    struct TextFileDecodeError: Error {}

    func replaceNames(using namePairs: [NameChangeSet], atURL url: URL) throws -> Bool {
        let fileData = try Data(contentsOf: url)
        guard let originalContent = String(data: fileData, encoding: .utf8) else { throw TextFileDecodeError() }
        var content = originalContent
        // Note: this will replace even mentions to the same names in written content
        // If overly ambitous replaces are a common scenario, a more sophisticated file-type-based RegEx will be implemented
        // Short-term workaround are using entity escaping for written content
        for pair in namePairs {
            let filenameBoundaryRegex = try NSRegularExpression(pattern: "\\b\(pair.prev)\\b", options: NSRegularExpression.Options.caseInsensitive)
            let range = NSRange(content.startIndex..., in: content)
            content = filenameBoundaryRegex.stringByReplacingMatches(
                in: content,
                options: [],
                range: range,
                withTemplate: pair.next
            )
        }
        if content == originalContent {
            return false
        }
        try content.data(using: .utf8)?.write(to: url, options: .atomic)
        return true
    }
    
    func createDirectory(at rootURL: URL) throws {
        if FileManager.default.fileExists(atPath: rootURL.absoluteString) {
            try FileManager.default.removeItem(at: rootURL)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
    }

    func copyFiles(_ urlPairs: [URLCopySet]) throws -> Void {
        
        for pair in urlPairs {
            if FileManager.default.fileExists(atPath: pair.dest.absoluteString) {
                continue
            }
            let parent = pair.dest.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.absoluteString) {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            try FileManager.default.copyItem(at: pair.src, to: pair.dest)
        }
    }

    func removeFiles(_ urls: [URL]) throws -> Void {
        for url in urls {
            try FileManager.default.removeItem(at: url)
        }
    }

    
    func retrieveFiles(from rootURL: URL) throws -> [ResourcedURL] {
        let fileManager = FileManager.default
        guard let resourceValues = try? rootURL.resourceValues(forKeys: [.isDirectoryKey]),
              let isDirectory = resourceValues.isDirectory,
              isDirectory else {
            throw RootNotDirectory()
        }
        let resourceKeys = Set<URLResourceKey>([
            .isRegularFileKey,
            .nameKey,
            .isDirectoryKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentTypeKey
        ])
        let directoryEnumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: .skipsHiddenFiles
        )!
         
        var urls: [ResourcedURL] = []
        for case let url as URL in directoryEnumerator {
            guard let resourceValues = try? url.resourceValues(forKeys: resourceKeys),
                  let contentType = resourceValues.contentType,
                  let contentModificationDate = resourceValues.contentModificationDate,
                  let isRegularFile = resourceValues.isRegularFile,
                  let name = resourceValues.name
                else { continue }
            let isDirectory = resourceValues.isDirectory ?? false
            let resourcedURL = ResourcedURL(
                url: url,
                isDirectory: isDirectory,
                contentType: contentType,
                contentModificationDate: contentModificationDate,
                isRegularFile: isRegularFile,
                originalName: name
            )
            urls.append(resourcedURL)
        }
        return urls
    }
    
    func createRevisedResourcedURL(_ resourced: ResourcedURL, _ bareName: String, _ nameMap: [URL : ResourcedURL]) -> [URL : ResourcedURL] {
        var nameMap = nameMap
        if let contentData = try? Data(contentsOf: resourced.url) {
            let hashed = Insecure.SHA1.hash(data: contentData)
            if let hashQueryResult = String(describing: hashed).firstMatch(of: Self.hashValuePattern) {
                let (_, hashValue) = hashQueryResult.output
                let nameComponents = bareName.split(separator: ".")
                let baseName = nameComponents.prefix(upTo: nameComponents.endIndex.advanced(by: -1))
                let extensionName = nameComponents.last ?? ""
                let revisedName = baseName.joined(separator: ".") + "-\(hashValue)" + "." + extensionName
                var revisedURL = resourced.url.deletingLastPathComponent()
                revisedURL = revisedURL.appending(path: revisedName)
                nameMap[resourced.url] = resourced.replacing(url: revisedURL)
            }
        }
        return nameMap
    }
}
