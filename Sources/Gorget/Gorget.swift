import Dependencies
import Foundation

public struct Gorget {
    public static let live = Gorget()
    private static let divider = "\n\n" + String(repeating: ":", count: 53) + "\n"

    struct RevisionStep {
        public let description: String
        public let execute: @Sendable (RevisionStep?) async throws -> [FileService.NameChangeSet]
        var remainingNameChanges: [FileService.NameChangeSet] = []
    }
    
    public struct RevisionPlan {
        public let description: String
        public let execute: @Sendable () async throws -> Void
    }

    @Dependency(\.fileClient) var fileClient
    
    /**
     Produces a plan and function to revise names if needed using content hash
        and updating content in place
     Output will be the same parent directory of `sourceDirectory`, named `Gorget_Revised`
     - Parameters:
        - sourceDirectory: URL of directory to revise content
        - manifestNames: A list of file names meant never to be renamed based on content
     - Returns: Gorget.RevisionPlan
        
     */
    public func generateRevisionPlan(
        for sourceDirectory: URL,
        skippingRenamingOf manifestNames: Set<String>
    ) async -> RevisionPlan {
        /*
         1. Content hash rev all file names
            - When a file has had it's name revved, and resulted in a change, it's added to a tuple (prev name / new name) list for evaluation in other file content later
         2. For all text-based (public.text UTI), non-manifest files, replace any found name references, save
            - Any modified non-manifest files, that haven't had a content rev already, add to a last pass list
         3. Do a last pass on last pass list and manifest files replacing updated name references
         */
        if !sourceDirectory.hasDirectoryPath {
            return RevisionPlan(description: "Please pass a directory-hinted file URL. Execute is a no-op", execute: {})
        }
        var resourcedURLs: [FileService.ResourcedURL] = []
        let retrieveFiles = Task { () -> [FileService.ResourcedURL] in
            return try await fileClient.retrieveFiles(sourceDirectory)
        }
        do {
            resourcedURLs = try await retrieveFiles.value
        } catch {
            return RevisionPlan(description: "Error encountered retriving files: \(error). Execute is a no-op", execute: {})
        }
        
        let (
            revisionNameLookup,
            nonManifestResourcedURLs,
            manifestResourcedURLs,
            opaqueResourcedURLs
        ) = await marshalResourcedURLs(resourcedURLs, using: manifestNames)
        var steps: [RevisionStep] = []
        // create destination directory
        let destinationDirectory = sourceDirectory.deletingLastPathComponent().appending(path: "Gorget_Revised", directoryHint: .isDirectory)
        let rootMessage = """
        Gorget Revise Content Plan:
        \(Self.divider)
        Creating destination directory: \(destinationDirectory)
        """
        let createDestinationStep = RevisionStep(description: rootMessage) { _ in
            try await fileClient.createDirectory(destinationDirectory)
            return []
        }
        steps.append(createDestinationStep)
        
        let nameChangeSets: [FileService.NameChangeSet] = revisionNameLookup.map { key, value in (prev: key.lastPathComponent, next: value.url.lastPathComponent) }

        // opaque URLs first, we just need to copy, not alter contents
        let opaqueStep = produceStep(
            using: opaqueResourcedURLs,
            nameLookup: revisionNameLookup,
            nameChangeSets: [],
            rootSet: (src: sourceDirectory, dest: destinationDirectory),
            title: "Opaque Files") { opaqueSets, _ in
                try await fileClient.copyFiles(opaqueSets)
                return []
            }
        steps.append(opaqueStep)

        // rev non-manifest text files, copy, then find/replace names
        let nonManifestStep = produceNonManifestStep(
            using: nonManifestResourcedURLs,
            revisionNameLookup: revisionNameLookup,
            nameChangeSets: nameChangeSets,
            rootSet: (src: sourceDirectory, dest: destinationDirectory),
            manifestNames: manifestNames
        )
        steps.append(nonManifestStep)
        
        // handle manifest type files
        let manifestStep = produceStep(
            using: manifestResourcedURLs,
            nameLookup: revisionNameLookup,
            nameChangeSets: nameChangeSets,
            rootSet: (src: sourceDirectory, dest: destinationDirectory),
            title: "Manifest Files"
        ) { manifestSets, nameChangeSets in
            try await fileClient.copyFiles(manifestSets)
            for copySet in manifestSets {
                _ = try await fileClient.replaceNames(nameChangeSets, copySet.dest)
            }
            
            return nameChangeSets
        }
        steps.append(manifestStep)
        
        let composedPlan: ([RevisionStep]) -> @Sendable () async throws -> Void = { revisionSteps in
            return {
                var previous: RevisionStep? = nil
                for var step in revisionSteps {
                    step.remainingNameChanges = try await step.execute(previous)
                    previous = step
                }
            }
        }
        return RevisionPlan(description: steps.reduce("", { $0 + $1.description }), execute: composedPlan(steps))
    }

    private func produceNonManifestStep(
        using resourcedURLs: [FileService.ResourcedURL],
        revisionNameLookup: [URL: FileService.ResourcedURL],
        nameChangeSets: [FileService.NameChangeSet],
        rootSet: FileService.URLCopySet,
        manifestNames: Set<String>
    ) -> RevisionStep {
        return produceStep(
            using: resourcedURLs,
            nameLookup: revisionNameLookup,
            nameChangeSets: nameChangeSets,
            rootSet: rootSet,
            title: "Text Files") { nonManifestSets, nameChangeSets in
                // copy with revised names
                try await fileClient.copyFiles(nonManifestSets)
                var copySetsModified = [FileService.URLCopySet]()
                for copySet in nonManifestSets {
                    if try await fileClient.replaceNames(nameChangeSets, copySet.dest) {
                        copySetsModified.append(copySet)
                    }
                }
                
                // need to fetch URLs again for non-manifest text files, so we can get metadata/content
                // then do last pass, then do manifest after adding some extra name change sets
                var nameLookup = revisionNameLookup
                // copySetsModified we now changed contents, needs revised name once more
                for copySet in copySetsModified {
                    guard let previousResourced = nameLookup[copySet.src] else { continue }
                    if !previousResourced.isDirectory,
                       let copySet = convertURL(
                        previousResourced.url,
                        using: nameLookup[previousResourced.url]?.url ?? previousResourced.url,
                        rootSet: rootSet
                       ) {
                        let resourced = previousResourced.replacing(url: copySet.dest)
                        nameLookup = await fileClient.createRevisedResourcedURL(resourced, previousResourced.originalName, nameLookup)
                    }
                }
                
                let retrieveFiles = Task { () -> [FileService.ResourcedURL] in
                    return try await fileClient.retrieveFiles(rootSet.dest)
                }
                let resourcedURLs = try await retrieveFiles.value
                let (_, nonManifestResourcedURLs, _, _) = await marshalResourcedURLs(
                    resourcedURLs,
                    using: manifestNames
                )
                let revisedNameChangeSets = nameLookup.map { key, value in (prev: key.lastPathComponent, next: value.url.lastPathComponent) }
                let lastPassNonManifestSets = createCopySets(
                    using: nonManifestResourcedURLs,
                    nameLookup: nameLookup,
                    rootSet: (src: rootSet.dest, dest: rootSet.dest)
                )
                
                // copy last-pass revised to new files names all within destination directory
                try await fileClient.copyFiles(lastPassNonManifestSets)
                // remove the previous revised files
                try await fileClient.removeFiles(lastPassNonManifestSets.map({ $0.src }))
                
                for copySet in lastPassNonManifestSets {
                    _ = try await fileClient.replaceNames(revisedNameChangeSets, copySet.dest)
                }
                
                return revisedNameChangeSets
            }
    }
    
    private func produceStep(
        using resourcedURLs: [FileService.ResourcedURL],
        nameLookup: [URL: FileService.ResourcedURL],
        nameChangeSets: [FileService.NameChangeSet],
        rootSet: FileService.URLCopySet,
        title: String,
        execution: @escaping @Sendable ([FileService.URLCopySet], [FileService.NameChangeSet]) async throws -> [FileService.NameChangeSet]
    ) -> RevisionStep {
        let copySets = createCopySets(
            using: resourcedURLs,
            nameLookup: nameLookup,
            rootSet: rootSet
        )
        let reviseMessage = """
\(Self.divider)
\(title):
Copying:
\(copySets)
Finding/Replacing:
In above copy set:
\(nameChangeSets)
\(Self.divider)
Note: A last pass for files modified due to name revision changes in it's content may reflect outside above set
"""
        return RevisionStep(description: reviseMessage) { previousStep in
            try await execution(copySets, nameChangeSets + (previousStep?.remainingNameChanges ?? []))
        }
    }
    
    private func createCopySets(
        using resourcedURLs: [FileService.ResourcedURL],
        nameLookup: [URL: FileService.ResourcedURL],
        rootSet: FileService.URLCopySet
    ) -> [FileService.URLCopySet] {
        return resourcedURLs.compactMap { resourcedURL in
            // if it is a directory, skip
            if resourcedURL.isDirectory {
                return nil
            }
            return convertURL(
                resourcedURL.url,
                using: nameLookup[resourcedURL.url]?.url ?? resourcedURL.url,
                rootSet: rootSet
            )
        }
    }
    
    private func convertURL(
        _ sourceURL: URL,
        using revisedURL: URL,
        rootSet: FileService.URLCopySet
    ) -> FileService.URLCopySet? {
        let destinationPath = revisedURL.absoluteString.replacingOccurrences(of: rootSet.src.absoluteString, with: rootSet.dest.absoluteString)
        guard let destinationURL = URL(string: destinationPath),
              destinationURL.absoluteString != sourceURL.absoluteString else {
            return nil
        }
        return (src: sourceURL, dest: destinationURL)
    }
    
    private func marshalResourcedURLs(
        _ resourcedURLs: [FileService.ResourcedURL],
        using manifestNames: Set<String>
    ) async -> (
        revisionNameLookup: [URL: FileService.ResourcedURL],
        nonManifestResourcedURLs: [FileService.ResourcedURL],
        manifestResourcedURLs: [FileService.ResourcedURL],
        opaqueResourcedURLs: [FileService.ResourcedURL]
    ) {
        var revisionNameLookup: [URL: FileService.ResourcedURL] = [:]
        var nonManifestResourcedURLs: [FileService.ResourcedURL] = []
        var manifestResourcedURLs: [FileService.ResourcedURL] = []
        var opaqueResourcedURLs: [FileService.ResourcedURL] = []
        for resourced in resourcedURLs {
            // if it is a manifest file, capture regardless
            if manifestNames.contains(resourced.url.lastPathComponent) {
                // we assume manifests to be of text type
                manifestResourcedURLs.append(resourced)
                // manifests don't need any other processing
                continue
            }
            if resourced.contentType.conforms(to: .text) {
                nonManifestResourcedURLs.append(resourced)
            } else {
                opaqueResourcedURLs.append(resourced)
            }
            revisionNameLookup = await fileClient.createRevisedResourcedURL(resourced, resourced.originalName, revisionNameLookup)
        }
        return (
            revisionNameLookup: revisionNameLookup,
            nonManifestResourcedURLs: nonManifestResourcedURLs,
            manifestResourcedURLs: manifestResourcedURLs,
            opaqueResourcedURLs: opaqueResourcedURLs
        )
    }
    
}
