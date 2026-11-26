import Foundation

enum FactoryMachineState: String, CaseIterable {
    case draft = "Draft"
    case runningAttached = "RunningAttached"
    case runningDetached = "RunningDetached"
    case previewReady = "PreviewReady"
    case publishing = "Publishing"
    case published = "Published"
    case discarded = "Discarded"
    case failed = "Failed"
}

enum FactoryMachineEvent: String, CaseIterable {
    case startRequested = "StartRequested"
    case runnerMissing = "RunnerMissing"
    case diskReloadRunning = "DiskReloadRunning"
    case diskReloadPreviewReady = "DiskReloadPreviewReady"
    case diskReloadPublished = "DiskReloadPublished"
    case diskReloadFailed = "DiskReloadFailed"
    case runnerExitedNonZero = "RunnerExitedNonZero"
    case stopRequested = "StopRequested"
    case publishRequested = "PublishRequested"
    case discardRequested = "DiscardRequested"
    case uiReloaded = "UiReloaded"
}

enum FactoryMachineOutcome: String, CaseIterable {
    case noop = "Noop"
    case launchRunnerAndPoll = "LaunchRunnerAndPoll"
    case resumePoll = "ResumePoll"
    case launchPublishAndPoll = "LaunchPublishAndPoll"
    case notifyPreviewReady = "NotifyPreviewReady"
    case completePublish = "CompletePublish"
    case markFailed = "MarkFailed"
    case stopAndMarkFailed = "StopAndMarkFailed"
    case stopAndMarkDiscarded = "StopAndMarkDiscarded"
    case detachKeepingRunner = "DetachKeepingRunner"
}

enum FactoryRunMachine {
    static func advance(_ state: FactoryMachineState, _ event: FactoryMachineEvent) -> (
        state: FactoryMachineState, outcome: FactoryMachineOutcome
    ) {
        switch state {
        case .draft:
            switch event {
            case .startRequested:
                return (.runningAttached, .launchRunnerAndPoll)
            case .runnerMissing:
                return (.failed, .markFailed)
            case .diskReloadRunning:
                return (.runningDetached, .resumePoll)
            case .diskReloadPreviewReady:
                return (.previewReady, .notifyPreviewReady)
            case .diskReloadPublished:
                return (.published, .completePublish)
            case .diskReloadFailed:
                return (.failed, .markFailed)
            case .discardRequested:
                return (.discarded, .stopAndMarkDiscarded)
            case .runnerExitedNonZero, .stopRequested, .publishRequested, .uiReloaded:
                return (.draft, .noop)
            }

        case .runningAttached:
            switch event {
            case .runnerMissing, .diskReloadFailed, .runnerExitedNonZero:
                return (.failed, .markFailed)
            case .diskReloadRunning:
                return (.runningAttached, .resumePoll)
            case .diskReloadPreviewReady:
                return (.previewReady, .notifyPreviewReady)
            case .diskReloadPublished:
                return (.published, .completePublish)
            case .stopRequested:
                return (.failed, .stopAndMarkFailed)
            case .discardRequested:
                return (.discarded, .stopAndMarkDiscarded)
            case .uiReloaded:
                return (.runningDetached, .detachKeepingRunner)
            case .startRequested, .publishRequested:
                return (.runningAttached, .noop)
            }

        case .runningDetached:
            switch event {
            case .diskReloadRunning:
                return (.runningDetached, .resumePoll)
            case .diskReloadPreviewReady:
                return (.previewReady, .notifyPreviewReady)
            case .diskReloadPublished:
                return (.published, .completePublish)
            case .diskReloadFailed:
                return (.failed, .markFailed)
            case .stopRequested:
                return (.failed, .stopAndMarkFailed)
            case .discardRequested:
                return (.discarded, .stopAndMarkDiscarded)
            case .startRequested, .runnerMissing, .runnerExitedNonZero, .publishRequested,
                .uiReloaded:
                return (.runningDetached, .noop)
            }

        case .previewReady:
            switch event {
            case .startRequested:
                return (.runningAttached, .launchRunnerAndPoll)
            case .publishRequested:
                return (.publishing, .launchPublishAndPoll)
            case .discardRequested:
                return (.discarded, .stopAndMarkDiscarded)
            case .diskReloadRunning:
                return (.runningDetached, .resumePoll)
            case .diskReloadPublished:
                return (.published, .completePublish)
            case .diskReloadFailed:
                return (.failed, .markFailed)
            case .runnerMissing, .diskReloadPreviewReady, .runnerExitedNonZero, .stopRequested,
                .uiReloaded:
                return (.previewReady, .noop)
            }

        case .publishing:
            switch event {
            case .diskReloadRunning:
                return (.publishing, .resumePoll)
            case .diskReloadPublished:
                return (.published, .completePublish)
            case .diskReloadFailed, .runnerExitedNonZero:
                return (.failed, .markFailed)
            case .stopRequested:
                return (.failed, .stopAndMarkFailed)
            case .uiReloaded:
                return (.runningDetached, .detachKeepingRunner)
            case .startRequested, .runnerMissing, .diskReloadPreviewReady, .publishRequested,
                .discardRequested:
                return (.publishing, .noop)
            }

        case .published:
            switch event {
            case .startRequested:
                return (.runningAttached, .launchRunnerAndPoll)
            case .diskReloadRunning:
                return (.runningDetached, .resumePoll)
            case .runnerMissing, .diskReloadPreviewReady, .diskReloadPublished, .diskReloadFailed,
                .runnerExitedNonZero, .stopRequested, .publishRequested, .discardRequested,
                .uiReloaded:
                return (.published, .noop)
            }

        case .discarded:
            switch event {
            case .startRequested:
                return (.runningAttached, .launchRunnerAndPoll)
            case .diskReloadRunning:
                return (.runningDetached, .resumePoll)
            case .runnerMissing, .diskReloadPreviewReady, .diskReloadPublished, .diskReloadFailed,
                .runnerExitedNonZero, .stopRequested, .publishRequested, .discardRequested,
                .uiReloaded:
                return (.discarded, .noop)
            }

        case .failed:
            switch event {
            case .startRequested:
                return (.runningAttached, .launchRunnerAndPoll)
            case .diskReloadRunning:
                return (.runningDetached, .resumePoll)
            case .discardRequested:
                return (.discarded, .stopAndMarkDiscarded)
            case .runnerMissing, .diskReloadPreviewReady, .diskReloadPublished, .diskReloadFailed,
                .runnerExitedNonZero, .stopRequested, .publishRequested, .uiReloaded:
                return (.failed, .noop)
            }
        }
    }

    static func table() -> StateMachineTable {
        StateMachineTable.build(
            start: FactoryMachineState.draft,
            ends: [],
            advance: advance
        )
    }

    static func runSelfTests() -> Bool {
        let s1 = advance(.draft, .startRequested)
        let doubleStart = advance(s1.state, .startRequested)
        let detached = advance(s1.state, .uiReloaded)
        let repoll = advance(.draft, .diskReloadRunning)
        let preview = advance(detached.state, .diskReloadPreviewReady)
        let pubStart = advance(preview.state, .publishRequested)
        let doublePub = advance(pubStart.state, .publishRequested)
        let pubDone = advance(pubStart.state, .diskReloadPublished)
        let badDiscard = advance(pubDone.state, .discardRequested)
        let pubFail = advance(pubStart.state, .runnerExitedNonZero)
        let retry = advance(pubFail.state, .startRequested)
        return s1.state == .runningAttached
            && s1.outcome == .launchRunnerAndPoll
            && doubleStart.state == .runningAttached
            && doubleStart.outcome == .noop
            && detached.state == .runningDetached
            && detached.outcome == .detachKeepingRunner
            && repoll.state == .runningDetached
            && repoll.outcome == .resumePoll
            && preview.state == .previewReady
            && preview.outcome == .notifyPreviewReady
            && pubStart.state == .publishing
            && pubStart.outcome == .launchPublishAndPoll
            && doublePub.state == .publishing
            && doublePub.outcome == .noop
            && pubDone.state == .published
            && pubDone.outcome == .completePublish
            && badDiscard.state == .published
            && badDiscard.outcome == .noop
            && pubFail.state == .failed
            && pubFail.outcome == .markFailed
            && retry.state == .runningAttached
            && retry.outcome == .launchRunnerAndPoll
    }
}
