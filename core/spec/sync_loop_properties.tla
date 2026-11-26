---- MODULE sync_loop_properties ----
EXTENDS sync_loop

noIdleBroadcastDiffLoop ==
    (moved /\ previous = "IdleClean" /\ event = "RemoteChangedIdle") =>
        (outcome = "Noop" /\ state = "IdleClean")

unchangedStatsNeverBroadcast ==
    (moved /\ event = "DiffComputedUnchanged") =>
        (outcome = "SuppressUnchangedStats")

turnFinishRefreshesDiffOnce ==
    (moved /\ previous = "BusyClean" /\ event = "RemoteChangedIdle") =>
        (outcome = "StartDiff" /\ state = "IdleDiffPending")

diffCompletionAlwaysQuiescesWhenIdle ==
    (moved /\ previous = "IdleDiffPending"
        /\ event \in {"DiffComputedUnchanged", "DiffComputedChanged"}) =>
        (state = "IdleClean")

emitStatsOnlyWhenChanged ==
    (moved /\ outcome = "EmitStatsChanged") =>
        (event = "DiffComputedChanged")

neverTurnFinishRefresh ==
    ~(moved /\ previous = "BusyClean" /\ event = "RemoteChangedIdle" /\ outcome = "StartDiff")

neverSuppressUnchanged ==
    ~(moved /\ previous = "IdleDiffPending" /\ event = "DiffComputedUnchanged" /\ outcome = "SuppressUnchangedStats")

neverEmitStatsChanged ==
    ~(moved /\ previous = "IdleDiffPending" /\ event = "DiffComputedChanged" /\ outcome = "EmitStatsChanged")

neverBusyDiffOpen ==
    ~(moved /\ previous = "IdleClean" /\ event = "RemoteChangedBusyDiffOpen" /\ outcome = "StartDiff")
====
