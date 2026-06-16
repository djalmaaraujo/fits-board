import XCTest
import FitsCore

final class AgentOutputAccumulatorTests: XCTestCase {
    func testBuffersPartialChunksUntilLineIsComplete() {
        var accumulator = AgentOutputAccumulator()

        XCTAssertEqual(accumulator.append("H"), [])
        XCTAssertEqual(accumulator.append("el"), [])
        XCTAssertEqual(accumulator.append("lo\nW"), ["Hello"])
        XCTAssertEqual(accumulator.append("orld\n"), ["World"])
    }

    func testCollapsesCarriageReturnRedrawsToStableLine() {
        var accumulator = AgentOutputAccumulator()

        XCTAssertEqual(accumulator.append("thinking\rthinking.\rDone\n"), ["Done"])
    }

    func testFlushEmitsRemainingBufferedLine() {
        var accumulator = AgentOutputAccumulator()

        XCTAssertEqual(accumulator.append("partial"), [])
        XCTAssertEqual(accumulator.flush(), ["partial"])
        XCTAssertEqual(accumulator.flush(), [])
    }
}
