import XCTest
@testable import SmartQuitCore

final class AudioAttributionTests: XCTestCase {
    private var ancestry: FakeProcessAncestry!

    override func setUp() {
        super.setUp()
        ancestry = FakeProcessAncestry()
    }

    private func attribute(audio: Set<pid_t>, apps: Set<pid_t>) -> Set<pid_t> {
        AudioAttribution.appsPlayingAudio(audioPIDs: audio, appPIDs: apps, ancestry: ancestry)
    }

    func testAttributesAudioToTheAppThatEmitsItDirectly() {
        XCTAssertEqual(attribute(audio: [42], apps: [42, 43]), [42])
    }

    /// Safari, Chrome and every Electron app render audio in a helper process,
    /// so the emitting pid is a descendant of the app the user would name.
    func testAttributesAHelperProcessToItsApplication() {
        ancestry.parents = [99: 42]

        XCTAssertEqual(attribute(audio: [99], apps: [42]), [42])
    }

    func testFollowsAChainOfHelpers() {
        ancestry.parents = [99: 98, 98: 97, 97: 42]

        XCTAssertEqual(attribute(audio: [99], apps: [42]), [42])
    }

    func testIgnoresAudioFromAProcessWithNoTrackedAncestor() {
        ancestry.parents = [99: 98, 98: 1]

        XCTAssertEqual(attribute(audio: [99], apps: [42]), [])
    }

    func testStopsAtTheFirstTrackedAncestor() {
        ancestry.parents = [99: 42, 42: 7]

        XCTAssertEqual(attribute(audio: [99], apps: [42, 7]), [42])
    }

    func testAttributesEveryEmittingProcess() {
        ancestry.parents = [99: 42]

        XCTAssertEqual(attribute(audio: [99, 43], apps: [42, 43]), [42, 43])
    }

    /// A corrupt or cyclic parent chain must not spin the sweep.
    func testTerminatesOnACyclicParentChain() {
        ancestry.parents = [99: 98, 98: 99]

        XCTAssertEqual(attribute(audio: [99], apps: [42]), [])
    }

    /// A chain of `n` links, the emitter being link 0.
    private func chain(_ links: Int) {
        var parents: [pid_t: pid_t] = [:]
        for step in 0..<links {
            parents[pid_t(100 + step)] = pid_t(101 + step)
        }
        ancestry.parents = parents
    }

    /// The last process the walk is willing to look at is the one at
    /// `maxDepth - 1`, the emitter counting as the first.
    func testReachesTheAppAtTheDepthLimit() {
        chain(AudioAttribution.maxDepth - 1)
        let last = pid_t(100 + AudioAttribution.maxDepth - 1)

        XCTAssertEqual(attribute(audio: [100], apps: [last]), [last])
    }

    func testStopsOneProcessPastTheDepthLimit() {
        chain(AudioAttribution.maxDepth)
        let tooFar = pid_t(100 + AudioAttribution.maxDepth)

        XCTAssertEqual(attribute(audio: [100], apps: [tooFar]), [])
    }

    func testReportsNothingWhenNoProcessIsPlaying() {
        XCTAssertEqual(attribute(audio: [], apps: [42]), [])
    }
}
