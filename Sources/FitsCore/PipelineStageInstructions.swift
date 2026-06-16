import Foundation

public enum PipelineStageInstructions {
    public static func instructions(for column: BoardColumn) -> String {
        switch column.id {
        case BoardColumn.spec.id:
            """
            Produce planning context for the task.
            Check the live spec when product behavior is involved.
            Identify assumptions, open questions, target artifacts, and verification commands.
            Do not execute the requested work in this stage.
            Say clearly that execution has not happened yet.
            """
        case BoardColumn.plan.id:
            """
            Break the plan into small executable pieces.
            Execute the pieces when local execution is possible.
            Use parallel sub-agents when the tool supports them and the pieces are independent.
            If parallel sub-agents are not available, execute the pieces sequentially.
            Do not stop at planning.
            Make the required file, repository, or workspace changes using local tools.
            Keep changes scoped to the task.
            Verify the requested result before finishing.
            If verification fails, fix the issue before reporting success.
            """
        case BoardColumn.agentQA.id:
            """
            Verify the user's original request was completed.
            Run automated tests when available.
            Run manual checks when automation is not available.
            Compare the observed result against the task objective, not just against implementation details.
            Report exact evidence from verification.
            If the requested result is missing, create or fix it when the fix is straightforward, then verify again.
            """
        case BoardColumn.review.id:
            """
            Run a strong code review before the task reaches a human.
            Review the completed work against the original task, project context, and live spec.
            If there is a git repository, inspect the diff and identify what a pull request would need.
            Do not expand scope.
            Report findings, risks, pull request notes, and whether the task is ready for human review.
            """
        case BoardColumn.humanReview.id:
            """
            Wait for human review.
            Do not run an agent automatically in this stage.
            """
        case BoardColumn.done.id:
            """
            Mark the task as shipped.
            Do not run an agent automatically in this stage.
            """
        default:
            """
            Capture or organize the task according to this column.
            """
        }
    }
}
