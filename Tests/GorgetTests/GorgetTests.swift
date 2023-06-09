import Dependencies
import RegexBuilder
import XCTestDynamicOverlay
import XCTest
@testable import Gorget

final class GorgetTests: XCTestCase {
    static let inputURL = Bundle.module.resourceURL!.appending(path: "Resources", directoryHint: .isDirectory).appending(path: "Input", directoryHint: .isDirectory)
    
    func testPlanReflectsBasicInput() async throws {
        let library = withDependencies {
            $0.fileClient = .testValue
        } operation: {
            Gorget()
        }
        let plan = await library.generateRevisionPlan(
            for: Self.inputURL,
            skippingRenamingOf: ["2.html", "3.rss"]
        )
        XCTAssertNotNil(try revisionPlanRegex.wholeMatch(in: plan.description))
    }
    
    func testExecute() async throws {
        let library = withDependencies {
            $0.fileClient = .testValue
        } operation: {
            Gorget()
        }
        let plan = await library.generateRevisionPlan(
            for: Self.inputURL,
            skippingRenamingOf: ["2.html", "3.rss"]
        )
        do {
            try await plan.execute()
        } catch {
            XCTFail("Error executing plan: \(error)")
        }
    }
    
    func testThrowsForFailedDestinationCreation() async throws {
        let library = withDependencies {
            $0.fileClient = .testValue
            $0.fileClient.createDirectory = { _ in
                throw FileService.DestinationCreationFailure()
            }
        } operation: {
            Gorget()
        }
        let plan = await library.generateRevisionPlan(
            for: Self.inputURL,
            skippingRenamingOf: ["2.html", "3.rss"]
        )
        do {
            try await plan.execute()
            XCTFail("Failed destination creation didn't throw")
        } catch {}
    }

    func testDestinationCreationUsesInput() async throws {
        var attemptedDestination: URL? = nil
        let library = withDependencies {
            $0.fileClient = .testValue
            $0.fileClient.createDirectory = { destination in
                attemptedDestination = destination
            }
        } operation: {
            Gorget()
        }
        let plan = await library.generateRevisionPlan(
            for: Self.inputURL,
            skippingRenamingOf: ["2.html", "3.rss"]
        )
        try await plan.execute()
        let expected = Self.inputURL.deletingLastPathComponent().appending(path: "Gorget_Revised", directoryHint: .isDirectory)
        XCTAssertEqual(attemptedDestination, expected)
    }

    
    func testGeneratesNoOpForFailedRetrieveFiles() async throws {
        let error = FileService.RootNotDirectory()
        let library = withDependencies {
            $0.fileClient = .testValue
            $0.fileClient.retrieveFiles = { _ in
                throw error
            }
        } operation: {
            Gorget()
        }
        let plan = await library.generateRevisionPlan(
            for: Self.inputURL,
            skippingRenamingOf: ["2.html", "3.rss"]
        )
        XCTAssertEqual(plan.description, "Error encountered retriving files: \(error). Execute is a no-op")
    }
    
    func testCopyFilesMatchesRetrieved() async throws {
        var copySets = [FileService.URLCopySet]()
        let library: Gorget = withDependencies {
            $0.fileClient = .testValue
            
            $0.fileClient.replaceNames = { sets, destination in
                false
            }
            $0.fileClient.copyFiles = { sets in
                copySets += sets
            }
        } operation: {
            return Gorget()
        }
        let plan = await library.generateRevisionPlan(
            for: Self.inputURL,
            skippingRenamingOf: ["2.html", "3.rss"]
        )
        try await plan.execute()
        let sortedSets = copySets.sorted(by: { $0.src.absoluteString > $1.src.absoluteString })
        let sortedInputs = FileClient.testURLs(Self.inputURL).sorted(by: { $0.url.absoluteString > $1.url.absoluteString })
        XCTAssertEqual(sortedSets.map(\.src.absoluteString), sortedInputs.map(\.url.absoluteString))
    }
    
    func testReplaceNamesAffectsOnlyTextFiles() async throws {
        var destinations = [String: URL]()
        let library: Gorget = withDependencies {
            $0.fileClient = .testValue
            
            $0.fileClient.replaceNames = { sets, destination in
                destinations[destination.absoluteString] = destination
                return false
            }
        } operation: {
            return Gorget()
        }
        let plan = await library.generateRevisionPlan(
            for: Self.inputURL,
            skippingRenamingOf: ["2.html", "3.rss"]
        )
        try await plan.execute()
        XCTAssertTrue(destinations.allSatisfy({ !$1.lastPathComponent.contains(".jpg") && !$1.lastPathComponent.contains(".png") }))
    }
    
    func testGeneratesNoOpForNonDirectorySource() async throws {
        let inputURL = Bundle.module.resourceURL!.appending(path: "Resources").appending(path: "Input")
        let library = withDependencies {
            $0.fileClient = .testValue
        } operation: {
            Gorget()
        }
        let plan = await library.generateRevisionPlan(
            for: inputURL,
            skippingRenamingOf: ["2.html", "3.rss"]
        )
        XCTAssertEqual(plan.description, "Please pass a directory-hinted file URL. Execute is a no-op")
    }
}
