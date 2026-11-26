---- MODULE webview_sync_properties ----
EXTENDS webview_sync

CompilingStates == {"CompilingRulesEmpty", "CompilingRulesPending"}
LoadingStates == {"LoadingPageEmpty", "LoadingPagePending"}

failClosedIsAbsorbing ==
    (moved /\ previous = "Blocked") => (state = "Blocked" /\ outcome = "Noop")

loadPageOnlyAfterRulesCompile ==
    (moved /\ outcome = "LoadPage") =>
        (previous \in CompilingStates
            /\ event = "RulesCompiled"
            /\ state \in LoadingStates)

renderOnlyWhenPageReady ==
    (moved /\ outcome = "RenderNow") =>
        \/ (previous = "LoadingPagePending" /\ event = "PageFinished" /\ state = "RenderingClean")
        \/ (previous = "ReadyIdle" /\ event = "SnapshotRequested" /\ state = "RenderingClean")
        \/ (previous = "RenderingStale" /\ event = "RenderCompleted" /\ state = "RenderingClean")

staleRenderAlwaysRedraws ==
    (moved /\ previous = "RenderingStale" /\ event = "RenderCompleted") =>
        (outcome = "RenderNow" /\ state = "RenderingClean")

crashRecoveryPreservesPending ==
    (moved /\ event = "ProcessTerminated"
        /\ previous \in {"LoadingPagePending", "RenderingClean", "RenderingStale"}) =>
        (outcome = "ReloadPage" /\ state = "LoadingPagePending")

noopNeverMutatesState ==
    (moved /\ outcome = "Noop") => state = previous

neverRenderComplete ==
    ~(moved /\ outcome = "RenderComplete" /\ state = "ReadyIdle")

neverStaleRedraw ==
    ~(moved /\ previous = "RenderingStale" /\ outcome = "RenderNow" /\ state = "RenderingClean")

neverCrashRecovery ==
    ~(moved /\ previous = "RenderingClean" /\ outcome = "ReloadPage" /\ state = "LoadingPagePending")

neverBlockedFailClosed ==
    ~(moved /\ previous = "Blocked" /\ outcome = "Noop" /\ state = "Blocked")
====
