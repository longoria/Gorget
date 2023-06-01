import Dependencies
import RegexBuilder
import XCTestDynamicOverlay
import XCTest
@testable import Gorget

final class GorgetTests: XCTestCase {
    static let inputURL = Bundle.module.resourceURL!.appending(path: "Resources").appending(path: "Input")
    
    func testPlanReflectsBasicInput() async throws {
        let library = withDependencies {
            $0.fileClient = .testValue
        } operation: {
            Gorget()
        }
        let plan = await library.generateRevisionPlan(for: Self.inputURL, using: ["2.html", "3.rss"])
        
        XCTAssertNotNil(try revisionPlanRegex.wholeMatch(in: plan.description))
    }
    
    func testExecute() async throws {
        let library = withDependencies {
            $0.fileClient = .testValue
        } operation: {
            Gorget()
        }
        let plan = await library.generateRevisionPlan(for: Self.inputURL, using: ["2.html", "3.rss"])
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
        let plan = await library.generateRevisionPlan(for: Self.inputURL, using: ["2.html", "3.rss"])
        do {
            try await plan.execute()
            XCTFail("Failed destination creation didn't throw")
        } catch {}
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
        let plan = await library.generateRevisionPlan(for: Self.inputURL, using: ["2.html", "3.rss"])
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
        let plan = await library.generateRevisionPlan(for: Self.inputURL, using: ["2.html", "3.rss"])
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
        let plan = await library.generateRevisionPlan(for: Self.inputURL, using: ["2.html", "3.rss"])
        try await plan.execute()
        XCTAssertTrue(destinations.allSatisfy({ !$1.lastPathComponent.contains(".jpg") && !$1.lastPathComponent.contains(".png") }))
    }
}
