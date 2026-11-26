---- MODULE factory_run_properties ----
EXTENDS factory_run

noDoubleRunnerStart ==
    (moved /\ outcome = "LaunchRunnerAndPoll") =>
        (previous \notin {"RunningAttached", "RunningDetached", "Publishing"})

noDoublePublish ==
    (moved /\ outcome = "LaunchPublishAndPoll") =>
        (previous = "PreviewReady")

publishedNeverDiscarded ==
    (moved /\ previous = "Published" /\ event = "DiscardRequested") =>
        (outcome = "Noop" /\ state = "Published")

detachedReloadAlwaysPolls ==
    (moved /\ previous \in {"Draft", "RunningDetached"} /\ event = "DiskReloadRunning") =>
        (state = "RunningDetached" /\ outcome = "ResumePoll")

uiReloadNeverKillsRunning ==
    (moved /\ previous \in {"RunningAttached", "Publishing"} /\ event = "UiReloaded") =>
        (state = "RunningDetached" /\ outcome = "DetachKeepingRunner")

publishFailureAlwaysMarksFailed ==
    (moved /\ previous \in {"RunningAttached", "Publishing"} /\ event = "RunnerExitedNonZero") =>
        (state = "Failed" /\ outcome = "MarkFailed")

noopNeverMutatesState ==
    (moved /\ outcome = "Noop") => (state = previous)

neverLaunched ==
    ~(moved /\ previous = "Draft" /\ event = "StartRequested" /\ outcome = "LaunchRunnerAndPoll")

neverResumedPollAfterRestart ==
    ~(moved /\ previous = "Draft" /\ event = "DiskReloadRunning" /\ state = "RunningDetached" /\ outcome = "ResumePoll")

neverPreviewReady ==
    ~(moved /\ previous = "RunningDetached" /\ event = "DiskReloadPreviewReady" /\ state = "PreviewReady" /\ outcome = "NotifyPreviewReady")

neverPublished ==
    ~(moved /\ previous = "Publishing" /\ event = "DiskReloadPublished" /\ state = "Published" /\ outcome = "CompletePublish")

neverDiscarded ==
    ~(moved /\ previous = "PreviewReady" /\ event = "DiscardRequested" /\ state = "Discarded" /\ outcome = "StopAndMarkDiscarded")

neverFailedFromPublish ==
    ~(moved /\ previous = "Publishing" /\ event = "RunnerExitedNonZero" /\ state = "Failed")

neverRecoveredAfterFailure ==
    ~(moved /\ previous = "Failed" /\ event = "StartRequested" /\ state = "RunningAttached")
====
