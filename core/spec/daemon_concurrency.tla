---- MODULE daemon_concurrency ----
EXTENDS Naturals, FiniteSets

Launchers == {1, 2}

VARIABLES
    lockHolder,
    liveDaemons,
    guiState,
    turnState,
    providerWait,
    diffState,
    daemonPush,
    restartsLeft,
    approvalsLeft,
    unknownRpcLeft,
    diffChangesLeft

vars == <<
    lockHolder,
    liveDaemons,
    guiState,
    turnState,
    providerWait,
    diffState,
    daemonPush,
    restartsLeft,
    approvalsLeft,
    unknownRpcLeft,
    diffChangesLeft
>>

TypeOK ==
    /\ lockHolder \in {0, 1, 2}
    /\ liveDaemons \subseteq Launchers
    /\ guiState \in {"Disconnected", "Connected"}
    /\ turnState \in {"Idle", "Running", "AwaitingApproval", "Done"}
    /\ providerWait \in {"None", "Permission", "UnknownRpc"}
    /\ diffState \in {"Clean", "InFlightUnchanged", "InFlightChanged"}
    /\ daemonPush \in BOOLEAN
    /\ restartsLeft \in 0..2
    /\ approvalsLeft \in 0..1
    /\ unknownRpcLeft \in 0..1
    /\ diffChangesLeft \in 0..1

Init ==
    /\ lockHolder = 0
    /\ liveDaemons = {}
    /\ guiState = "Disconnected"
    /\ turnState = "Idle"
    /\ providerWait = "None"
    /\ diffState = "Clean"
    /\ daemonPush = FALSE
    /\ restartsLeft = 2
    /\ approvalsLeft = 1
    /\ unknownRpcLeft = 1
    /\ diffChangesLeft = 1

TryAcquireLock(l) ==
    /\ l \in Launchers
    /\ lockHolder = 0
    /\ liveDaemons = {}
    /\ turnState = "Idle"
    /\ lockHolder' = l
    /\ liveDaemons' = {l}
    /\ UNCHANGED <<guiState, turnState, providerWait, diffState, daemonPush, restartsLeft, approvalsLeft, unknownRpcLeft, diffChangesLeft>>

LoseLockRace(l) ==
    /\ l \in Launchers
    /\ lockHolder /= 0
    /\ l \notin liveDaemons
    /\ UNCHANGED vars

GuiConnect ==
    /\ liveDaemons /= {}
    /\ guiState = "Disconnected"
    /\ guiState' = "Connected"
    /\ UNCHANGED <<lockHolder, liveDaemons, turnState, providerWait, diffState, daemonPush, restartsLeft, approvalsLeft, unknownRpcLeft, diffChangesLeft>>

GuiRestart ==
    /\ guiState = "Connected"
    /\ restartsLeft > 0
    /\ guiState' = "Disconnected"
    /\ restartsLeft' = restartsLeft - 1
    /\ UNCHANGED <<lockHolder, liveDaemons, turnState, providerWait, diffState, daemonPush, approvalsLeft, unknownRpcLeft, diffChangesLeft>>

GuiStartTurn ==
    /\ liveDaemons /= {}
    /\ guiState = "Connected"
    /\ turnState = "Idle"
    /\ turnState' = "Running"
    /\ daemonPush' = TRUE
    /\ UNCHANGED <<lockHolder, liveDaemons, guiState, providerWait, diffState, restartsLeft, approvalsLeft, unknownRpcLeft, diffChangesLeft>>

ProviderRequestPermission ==
    /\ liveDaemons /= {}
    /\ turnState = "Running"
    /\ providerWait = "None"
    /\ approvalsLeft > 0
    /\ turnState' = "AwaitingApproval"
    /\ providerWait' = "Permission"
    /\ daemonPush' = TRUE
    /\ approvalsLeft' = approvalsLeft - 1
    /\ UNCHANGED <<lockHolder, liveDaemons, guiState, diffState, restartsLeft, unknownRpcLeft, diffChangesLeft>>

ProviderSendUnknownRpc ==
    /\ liveDaemons /= {}
    /\ turnState = "Running"
    /\ providerWait = "None"
    /\ unknownRpcLeft > 0
    /\ providerWait' = "UnknownRpc"
    /\ unknownRpcLeft' = unknownRpcLeft - 1
    /\ UNCHANGED <<lockHolder, liveDaemons, guiState, turnState, diffState, daemonPush, restartsLeft, approvalsLeft, diffChangesLeft>>

DaemonReplyMethodNotFound ==
    /\ liveDaemons /= {}
    /\ providerWait = "UnknownRpc"
    /\ providerWait' = "None"
    /\ UNCHANGED <<lockHolder, liveDaemons, guiState, turnState, diffState, daemonPush, restartsLeft, approvalsLeft, unknownRpcLeft, diffChangesLeft>>

GuiResolveApproval ==
    /\ liveDaemons /= {}
    /\ guiState = "Connected"
    /\ turnState = "AwaitingApproval"
    /\ providerWait = "Permission"
    /\ turnState' = "Running"
    /\ providerWait' = "None"
    /\ daemonPush' = TRUE
    /\ UNCHANGED <<lockHolder, liveDaemons, guiState, diffState, restartsLeft, approvalsLeft, unknownRpcLeft, diffChangesLeft>>

ProviderCompleteTurn ==
    /\ liveDaemons /= {}
    /\ turnState = "Running"
    /\ providerWait = "None"
    /\ turnState' = "Done"
    /\ daemonPush' = TRUE
    /\ diffState' = IF diffChangesLeft > 0 THEN "InFlightChanged" ELSE "InFlightUnchanged"
    /\ diffChangesLeft' = IF diffChangesLeft > 0 THEN diffChangesLeft - 1 ELSE 0
    /\ UNCHANGED <<lockHolder, liveDaemons, guiState, providerWait, restartsLeft, approvalsLeft, unknownRpcLeft>>

DiffCompleteChanged ==
    /\ liveDaemons /= {}
    /\ diffState = "InFlightChanged"
    /\ diffState' = "Clean"
    /\ daemonPush' = TRUE
    /\ UNCHANGED <<lockHolder, liveDaemons, guiState, turnState, providerWait, restartsLeft, approvalsLeft, unknownRpcLeft, diffChangesLeft>>

DiffCompleteUnchanged ==
    /\ liveDaemons /= {}
    /\ diffState = "InFlightUnchanged"
    /\ diffState' = "Clean"
    /\ UNCHANGED <<lockHolder, liveDaemons, guiState, turnState, providerWait, daemonPush, restartsLeft, approvalsLeft, unknownRpcLeft, diffChangesLeft>>

GuiConsumePush ==
    /\ liveDaemons /= {}
    /\ guiState = "Connected"
    /\ daemonPush = TRUE
    /\ daemonPush' = FALSE
    /\ UNCHANGED <<lockHolder, liveDaemons, guiState, turnState, providerWait, diffState, restartsLeft, approvalsLeft, unknownRpcLeft, diffChangesLeft>>

DaemonIdleShutdown ==
    /\ liveDaemons /= {}
    /\ guiState = "Disconnected"
    /\ turnState = "Done"
    /\ providerWait = "None"
    /\ diffState = "Clean"
    /\ ~daemonPush
    /\ lockHolder' = 0
    /\ liveDaemons' = {}
    /\ UNCHANGED <<guiState, turnState, providerWait, diffState, daemonPush, restartsLeft, approvalsLeft, unknownRpcLeft, diffChangesLeft>>

QuiescentStutter ==
    /\ turnState = "Done"
    /\ providerWait = "None"
    /\ diffState = "Clean"
    /\ ~daemonPush
    /\ UNCHANGED vars

Next ==
    \/ \E l \in Launchers : TryAcquireLock(l)
    \/ \E l \in Launchers : LoseLockRace(l)
    \/ GuiConnect
    \/ GuiRestart
    \/ GuiStartTurn
    \/ ProviderRequestPermission
    \/ ProviderSendUnknownRpc
    \/ DaemonReplyMethodNotFound
    \/ GuiResolveApproval
    \/ ProviderCompleteTurn
    \/ DiffCompleteChanged
    \/ DiffCompleteUnchanged
    \/ GuiConsumePush
    \/ DaemonIdleShutdown
    \/ QuiescentStutter

FairSpec ==
    /\ Init
    /\ [][Next]_vars
    /\ WF_vars(\E l \in Launchers : TryAcquireLock(l))
    /\ WF_vars(GuiConnect)
    /\ WF_vars(GuiStartTurn)
    /\ WF_vars(DaemonReplyMethodNotFound)
    /\ WF_vars(GuiResolveApproval)
    /\ WF_vars(ProviderCompleteTurn)
    /\ WF_vars(DiffCompleteChanged)
    /\ WF_vars(DiffCompleteUnchanged)
    /\ WF_vars(GuiConsumePush)

AtMostOneDaemon ==
    Cardinality(liveDaemons) <= 1

LockMatchesLiveDaemon ==
    liveDaemons /= {} => (lockHolder \in liveDaemons)

ActiveTurnNeverLosesDaemon ==
    (turnState \in {"Running", "AwaitingApproval"}) => (Cardinality(liveDaemons) = 1)

DoneHasNoPendingProviderWait ==
    (turnState = "Done") => (providerWait = "None")

UnknownRpcAlwaysAnswered ==
    (providerWait = "UnknownRpc") ~> (providerWait = "None")

ApprovalSurvivesGuiRestart ==
    (turnState = "AwaitingApproval") ~> (turnState \in {"Running", "Done"})

TurnEventuallyTerminates ==
    (turnState = "Running") ~> (turnState = "Done")

DiffSyncEventuallyQuiesces ==
    (turnState = "Done" /\ (diffState /= "Clean" \/ daemonPush)) ~>
        (diffState = "Clean" /\ ~daemonPush)
====
