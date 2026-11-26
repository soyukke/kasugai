import Foundation

enum SyncLoopState: String, CaseIterable {
    case idleClean = "IdleClean"
    case idleDiffPending = "IdleDiffPending"
    case busyClean = "BusyClean"
    case busyDiffPending = "BusyDiffPending"
}

enum SyncLoopEvent: String, CaseIterable {
    case remoteChangedBusy = "RemoteChangedBusy"
    case remoteChangedBusyDiffOpen = "RemoteChangedBusyDiffOpen"
    case remoteChangedIdle = "RemoteChangedIdle"
    case diffComputedUnchanged = "DiffComputedUnchanged"
    case diffComputedChanged = "DiffComputedChanged"
    case manualDiffRefresh = "ManualDiffRefresh"
}

enum SyncLoopOutcome: String, CaseIterable {
    case noop = "Noop"
    case startDiff = "StartDiff"
    case emitStatsChanged = "EmitStatsChanged"
    case suppressUnchangedStats = "SuppressUnchangedStats"
}

enum SyncLoopMachine {
    static func advance(_ state: SyncLoopState, _ event: SyncLoopEvent) -> (
        state: SyncLoopState, outcome: SyncLoopOutcome
    ) {
        switch state {
        case .idleClean:
            switch event {
            case .remoteChangedBusy:
                return (.busyClean, .noop)
            case .remoteChangedBusyDiffOpen:
                return (.busyDiffPending, .startDiff)
            case .remoteChangedIdle:
                return (.idleClean, .noop)
            case .diffComputedUnchanged:
                return (.idleClean, .suppressUnchangedStats)
            case .diffComputedChanged:
                return (.idleClean, .emitStatsChanged)
            case .manualDiffRefresh:
                return (.idleDiffPending, .startDiff)
            }

        case .idleDiffPending:
            switch event {
            case .remoteChangedBusy:
                return (.busyDiffPending, .noop)
            case .remoteChangedBusyDiffOpen:
                return (.busyDiffPending, .startDiff)
            case .remoteChangedIdle:
                return (.idleDiffPending, .noop)
            case .diffComputedUnchanged:
                return (.idleClean, .suppressUnchangedStats)
            case .diffComputedChanged:
                return (.idleClean, .emitStatsChanged)
            case .manualDiffRefresh:
                return (.idleDiffPending, .startDiff)
            }

        case .busyClean:
            switch event {
            case .remoteChangedBusy:
                return (.busyClean, .noop)
            case .remoteChangedBusyDiffOpen:
                return (.busyDiffPending, .startDiff)
            case .remoteChangedIdle:
                return (.idleDiffPending, .startDiff)
            case .diffComputedUnchanged:
                return (.busyClean, .suppressUnchangedStats)
            case .diffComputedChanged:
                return (.busyClean, .emitStatsChanged)
            case .manualDiffRefresh:
                return (.busyDiffPending, .startDiff)
            }

        case .busyDiffPending:
            switch event {
            case .remoteChangedBusy:
                return (.busyDiffPending, .noop)
            case .remoteChangedBusyDiffOpen:
                return (.busyDiffPending, .startDiff)
            case .remoteChangedIdle:
                return (.idleDiffPending, .startDiff)
            case .diffComputedUnchanged:
                return (.busyClean, .suppressUnchangedStats)
            case .diffComputedChanged:
                return (.busyClean, .emitStatsChanged)
            case .manualDiffRefresh:
                return (.busyDiffPending, .startDiff)
            }
        }
    }

    static func table() -> StateMachineTable {
        StateMachineTable.build(
            start: SyncLoopState.idleClean,
            ends: [],
            advance: advance
        )
    }

    static func runSelfTests() -> Bool {
        let idleLoop = advance(.idleClean, .remoteChangedIdle)
        let turnStart = advance(.idleClean, .remoteChangedBusy)
        let turnFinish = advance(turnStart.state, .remoteChangedIdle)
        let unchanged = advance(turnFinish.state, .diffComputedUnchanged)
        let afterUnchanged = advance(unchanged.state, .remoteChangedIdle)
        let changed = advance(.idleDiffPending, .diffComputedChanged)
        return idleLoop.state == .idleClean
            && idleLoop.outcome == .noop
            && turnStart.state == .busyClean
            && turnFinish.state == .idleDiffPending
            && turnFinish.outcome == .startDiff
            && unchanged.state == .idleClean
            && unchanged.outcome == .suppressUnchangedStats
            && afterUnchanged.state == .idleClean
            && afterUnchanged.outcome == .noop
            && changed.state == .idleClean
            && changed.outcome == .emitStatsChanged
    }
}
