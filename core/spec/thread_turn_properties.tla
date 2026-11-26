---- MODULE thread_turn_properties ----
EXTENDS thread_turn

IdleStates == {"IdleEmpty", "IdleQueued"}
RunningStates == {"RunningEmpty", "RunningQueued"}
ApprovalStates == {"AwaitingApprovalEmpty", "AwaitingApprovalQueued"}
FailedStates == {"FailedEmpty", "FailedQueued"}
QueuedStates == {"IdleQueued", "RunningQueued", "AwaitingApprovalQueued", "FailedQueued"}
EmptyStates == {"IdleEmpty", "RunningEmpty", "AwaitingApprovalEmpty", "FailedEmpty"}

SamePhase(a, b) ==
    \/ (a \in IdleStates /\ b \in IdleStates)
    \/ (a \in RunningStates /\ b \in RunningStates)
    \/ (a \in ApprovalStates /\ b \in ApprovalStates)
    \/ (a \in FailedStates /\ b \in FailedStates)

SameQueuePresence(a, b) ==
    (a \in QueuedStates) <=> (b \in QueuedStates)

noOverlapTurnStart ==
    (moved /\ outcome = "TurnStarted") =>
        (previous \in {"IdleQueued", "FailedQueued"}
            /\ event \in {"StartLastQueued", "StartMoreQueued"}
            /\ state \in RunningStates)

enqueuePreservesPhase ==
    (moved /\ event = "Enqueue") =>
        (outcome = "Queued"
            /\ SamePhase(previous, state)
            /\ state \in QueuedStates)

finishPreservesQueue ==
    (moved /\ outcome \in {"TurnCompleted", "TurnFailed"}) =>
        (previous \in RunningStates /\ SameQueuePresence(previous, state))

approvalRequestedOnlyWhileRunning ==
    (moved /\ outcome = "ApprovalRequested") =>
        (previous \in RunningStates
            /\ state \in ApprovalStates
            /\ SameQueuePresence(previous, state))

approvalDecisionSound ==
    (moved /\ outcome \in {"ApprovalGranted", "ApprovalDenied"}) =>
        (previous \in ApprovalStates
            /\ SameQueuePresence(previous, state)
            /\ ((outcome = "ApprovalGranted" /\ state \in RunningStates)
                \/ (outcome = "ApprovalDenied" /\ state \in FailedStates)))

cancelPreservesPhase ==
    (moved /\ outcome = "QueueItemRemoved") =>
        (previous \in QueuedStates
            /\ SamePhase(previous, state)
            /\ ((event = "CancelLastQueued" /\ state \in EmptyStates)
                \/ (event = "CancelMoreQueued" /\ state \in QueuedStates)))

noopNeverMutatesState ==
    (moved /\ outcome = "Noop") => state = previous

neverMidTurnQueueComplete ==
    ~(moved /\ previous = "RunningQueued" /\ outcome = "TurnCompleted" /\ state = "IdleQueued")

neverApprovalGranted ==
    ~(moved /\ outcome = "ApprovalGranted" /\ state = "RunningQueued")

neverApprovalDenied ==
    ~(moved /\ outcome = "ApprovalDenied" /\ state = "FailedQueued")

neverQueueCancelledWhileRunning ==
    ~(moved /\ previous = "RunningQueued" /\ outcome = "QueueItemRemoved" /\ state = "RunningEmpty")
====
