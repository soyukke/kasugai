import Foundation

enum WebViewSyncState: String, CaseIterable {
    case compilingRulesEmpty = "CompilingRulesEmpty"
    case compilingRulesPending = "CompilingRulesPending"
    case loadingPageEmpty = "LoadingPageEmpty"
    case loadingPagePending = "LoadingPagePending"
    case readyIdle = "ReadyIdle"
    case renderingClean = "RenderingClean"
    case renderingStale = "RenderingStale"
    case blocked = "Blocked"
}

enum WebViewSyncEvent: String, CaseIterable {
    case rulesCompiled = "RulesCompiled"
    case rulesFailed = "RulesFailed"
    case pageFinished = "PageFinished"
    case snapshotRequested = "SnapshotRequested"
    case renderCompleted = "RenderCompleted"
    case processTerminated = "ProcessTerminated"
}

enum WebViewSyncOutcome: String, CaseIterable {
    case noop = "Noop"
    case loadPage = "LoadPage"
    case pageReady = "PageReady"
    case blockFailClosed = "BlockFailClosed"
    case bufferSnapshot = "BufferSnapshot"
    case renderNow = "RenderNow"
    case renderComplete = "RenderComplete"
    case reloadPage = "ReloadPage"
}

enum WebViewSyncMachine {
    static func advance(_ state: WebViewSyncState, _ event: WebViewSyncEvent) -> (
        state: WebViewSyncState, outcome: WebViewSyncOutcome
    ) {
        switch state {
        case .compilingRulesEmpty:
            switch event {
            case .rulesCompiled:
                return (.loadingPageEmpty, .loadPage)
            case .rulesFailed:
                return (.blocked, .blockFailClosed)
            case .snapshotRequested:
                return (.compilingRulesPending, .bufferSnapshot)
            case .pageFinished, .renderCompleted, .processTerminated:
                return (.compilingRulesEmpty, .noop)
            }

        case .compilingRulesPending:
            switch event {
            case .rulesCompiled:
                return (.loadingPagePending, .loadPage)
            case .rulesFailed:
                return (.blocked, .blockFailClosed)
            case .snapshotRequested:
                return (.compilingRulesPending, .bufferSnapshot)
            case .pageFinished, .renderCompleted, .processTerminated:
                return (.compilingRulesPending, .noop)
            }

        case .loadingPageEmpty:
            switch event {
            case .pageFinished:
                return (.readyIdle, .pageReady)
            case .snapshotRequested:
                return (.loadingPagePending, .bufferSnapshot)
            case .processTerminated:
                return (.loadingPageEmpty, .reloadPage)
            case .rulesCompiled, .rulesFailed, .renderCompleted:
                return (.loadingPageEmpty, .noop)
            }

        case .loadingPagePending:
            switch event {
            case .pageFinished:
                return (.renderingClean, .renderNow)
            case .snapshotRequested:
                return (.loadingPagePending, .bufferSnapshot)
            case .processTerminated:
                return (.loadingPagePending, .reloadPage)
            case .rulesCompiled, .rulesFailed, .renderCompleted:
                return (.loadingPagePending, .noop)
            }

        case .readyIdle:
            switch event {
            case .snapshotRequested:
                return (.renderingClean, .renderNow)
            case .processTerminated:
                return (.loadingPagePending, .reloadPage)
            case .rulesCompiled, .rulesFailed, .pageFinished, .renderCompleted:
                return (.readyIdle, .noop)
            }

        case .renderingClean:
            switch event {
            case .snapshotRequested:
                return (.renderingStale, .bufferSnapshot)
            case .renderCompleted:
                return (.readyIdle, .renderComplete)
            case .processTerminated:
                return (.loadingPagePending, .reloadPage)
            case .rulesCompiled, .rulesFailed, .pageFinished:
                return (.renderingClean, .noop)
            }

        case .renderingStale:
            switch event {
            case .snapshotRequested:
                return (.renderingStale, .bufferSnapshot)
            case .renderCompleted:
                return (.renderingClean, .renderNow)
            case .processTerminated:
                return (.loadingPagePending, .reloadPage)
            case .rulesCompiled, .rulesFailed, .pageFinished:
                return (.renderingStale, .noop)
            }

        case .blocked:
            return (.blocked, .noop)
        }
    }

    static func table() -> StateMachineTable {
        StateMachineTable.build(
            start: WebViewSyncState.compilingRulesEmpty,
            ends: [],
            advance: advance
        )
    }

    static func runSelfTests() -> Bool {
        let failed = advance(.compilingRulesPending, .rulesFailed)
        guard failed.state == .blocked && failed.outcome == .blockFailClosed else {
            return false
        }
        for event in WebViewSyncEvent.allCases {
            let after = advance(.blocked, event)
            guard after.state == .blocked && after.outcome == .noop else {
                return false
            }
        }
        let s1 = advance(.compilingRulesEmpty, .snapshotRequested)
        let s2 = advance(s1.state, .rulesCompiled)
        let s3 = advance(s2.state, .pageFinished)
        let s4 = advance(s3.state, .snapshotRequested)
        let s5 = advance(s4.state, .renderCompleted)
        let s6 = advance(s5.state, .renderCompleted)
        return s1.state == .compilingRulesPending
            && s2.state == .loadingPagePending
            && s2.outcome == .loadPage
            && s3.state == .renderingClean
            && s3.outcome == .renderNow
            && s4.state == .renderingStale
            && s5.state == .renderingClean
            && s5.outcome == .renderNow
            && s6.state == .readyIdle
            && s6.outcome == .renderComplete
    }
}
