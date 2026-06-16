import XCTest
@testable import FitsCore

final class PipelineStageInstructionsTests: XCTestCase {
    func testPlanningStageDoesNotExecuteTheTask() {
        let instructions = PipelineStageInstructions.instructions(for: BoardColumn.spec)

        XCTAssertTrue(instructions.contains("Do not execute the requested work in this stage."))
        XCTAssertTrue(instructions.contains("Produce planning context"))
    }

    func testAgentFanOutStageBreaksPlanIntoExecutablePieces() {
        let instructions = PipelineStageInstructions.instructions(for: BoardColumn.plan)

        XCTAssertTrue(instructions.contains("Break the plan into small executable pieces."))
        XCTAssertTrue(instructions.contains("Execute the pieces when local execution is possible."))
        XCTAssertTrue(instructions.contains("Use parallel sub-agents when the tool supports them"))
        XCTAssertTrue(instructions.contains("Verify the requested result before finishing."))
    }

    func testAgentQAStageVerifiesOriginalRequest() {
        let instructions = PipelineStageInstructions.instructions(for: BoardColumn.agentQA)

        XCTAssertTrue(instructions.contains("Verify the user's original request was completed."))
        XCTAssertTrue(instructions.contains("automated tests when available"))
        XCTAssertTrue(instructions.contains("manual checks when automation is not available"))
    }

    func testAgentReviewStageRequiresStrongCodeReview() {
        let instructions = PipelineStageInstructions.instructions(for: BoardColumn.review)

        XCTAssertTrue(instructions.contains("Run a strong code review"))
        XCTAssertTrue(instructions.contains("pull request"))
    }
}
