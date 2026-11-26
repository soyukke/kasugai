import Darwin
import Foundation

@_silgen_name("kasugai_core_create")
func kasugaiCoreCreate(
    _ defaultProjectName: UnsafePointer<CChar>?,
    _ defaultProjectPath: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer?

@_silgen_name("kasugai_core_create_with_store")
func kasugaiCoreCreateWithStore(
    _ defaultProjectName: UnsafePointer<CChar>?,
    _ defaultProjectPath: UnsafePointer<CChar>?,
    _ storePath: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer?

@_silgen_name("kasugai_core_destroy")
func kasugaiCoreDestroy(_ handle: UnsafeMutableRawPointer?)

@_silgen_name("kasugai_core_add_project")
func kasugaiCoreAddProject(
    _ handle: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>?,
    _ rootPath: UnsafePointer<CChar>?
) -> Int64

@_silgen_name("kasugai_core_select_project")
func kasugaiCoreSelectProject(
    _ handle: UnsafeMutableRawPointer?,
    _ projectId: Int64
) -> UInt8

@_silgen_name("kasugai_core_create_thread")
func kasugaiCoreCreateThread(
    _ handle: UnsafeMutableRawPointer?,
    _ projectId: Int64,
    _ title: UnsafePointer<CChar>?,
    _ provider: UnsafePointer<CChar>?,
    _ model: UnsafePointer<CChar>?,
    _ effort: UnsafePointer<CChar>?
) -> Int64

@_silgen_name("kasugai_core_select_thread")
func kasugaiCoreSelectThread(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64
) -> UInt8

@_silgen_name("kasugai_core_rename_thread")
func kasugaiCoreRenameThread(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64,
    _ title: UnsafePointer<CChar>?
) -> UInt8

@_silgen_name("kasugai_core_set_thread_provider")
func kasugaiCoreSetThreadProvider(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64,
    _ provider: UnsafePointer<CChar>?,
    _ model: UnsafePointer<CChar>?,
    _ effort: UnsafePointer<CChar>?
) -> UInt8

@_silgen_name("kasugai_core_send_message")
func kasugaiCoreSendMessage(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64,
    _ text: UnsafePointer<CChar>?,
    _ attachmentsNewline: UnsafePointer<CChar>?
) -> Int64

@_silgen_name("kasugai_core_enqueue_message")
func kasugaiCoreEnqueueMessage(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64,
    _ text: UnsafePointer<CChar>?,
    _ attachmentsNewline: UnsafePointer<CChar>?
) -> Int64

@_silgen_name("kasugai_core_process_next_queued")
func kasugaiCoreProcessNextQueued(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64
) -> UInt8

@_silgen_name("kasugai_core_cancel_queued_turn")
func kasugaiCoreCancelQueuedTurn(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64,
    _ turnId: Int64
) -> UInt8

@_silgen_name("kasugai_core_resolve_approval")
func kasugaiCoreResolveApproval(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64,
    _ approve: UInt8
) -> UInt8

@_silgen_name("kasugai_core_cancel_active_turn")
func kasugaiCoreCancelActiveTurn(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64
) -> UInt8

@_silgen_name("kasugai_core_poll_providers")
func kasugaiCorePollProviders(_ handle: UnsafeMutableRawPointer?) -> UInt8

@_silgen_name("kasugai_core_provider_wakeup_fds")
func kasugaiCoreProviderWakeupFds(
    _ handle: UnsafeMutableRawPointer?
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("kasugai_core_set_provider_command_override")
func kasugaiCoreSetProviderCommandOverride(
    _ handle: UnsafeMutableRawPointer?,
    _ provider: UnsafePointer<CChar>?,
    _ executable: UnsafePointer<CChar>?,
    _ argsNewline: UnsafePointer<CChar>?
) -> UInt8

@_silgen_name("kasugai_core_set_telemetry_suppression")
func kasugaiCoreSetTelemetrySuppression(
    _ handle: UnsafeMutableRawPointer?,
    _ enabled: UInt8
) -> UInt8

@_silgen_name("kasugai_core_set_auto_approve_tools")
func kasugaiCoreSetAutoApproveTools(
    _ handle: UnsafeMutableRawPointer?,
    _ enabled: UInt8
) -> UInt8

@_silgen_name("kasugai_core_set_orchestrator_bridge")
func kasugaiCoreSetOrchestratorBridge(
    _ handle: UnsafeMutableRawPointer?,
    _ socketPath: UnsafePointer<CChar>?,
    _ ctlBin: UnsafePointer<CChar>?
) -> UInt8

@_silgen_name("kasugai_core_bind_worktree")
func kasugaiCoreBindWorktree(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64,
    _ branch: UnsafePointer<CChar>?,
    _ baseRef: UnsafePointer<CChar>?,
    _ worktreePath: UnsafePointer<CChar>?
) -> UInt8

@_silgen_name("kasugai_core_reset_worktree")
func kasugaiCoreResetWorktree(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64
) -> UInt8

@_silgen_name("kasugai_core_update_diff_stats")
func kasugaiCoreUpdateDiffStats(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64,
    _ filesChanged: Int64,
    _ insertions: Int64,
    _ deletions: Int64
) -> UInt8

@_silgen_name("kasugai_core_snapshot_json")
func kasugaiCoreSnapshotJson(_ handle: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("kasugai_core_events_jsonl")
func kasugaiCoreEventsJsonl(
    _ handle: UnsafeMutableRawPointer?,
    _ threadId: Int64
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("kasugai_term_create")
func kasugaiTermCreate(
    _ cwd: UnsafePointer<CChar>?,
    _ cols: UInt16,
    _ rows: UInt16
) -> UnsafeMutableRawPointer?

@_silgen_name("kasugai_term_create_command")
func kasugaiTermCreateCommand(
    _ cwd: UnsafePointer<CChar>?,
    _ command: UnsafePointer<CChar>?,
    _ cols: UInt16,
    _ rows: UInt16
) -> UnsafeMutableRawPointer?

@_silgen_name("kasugai_term_destroy")
func kasugaiTermDestroy(_ handle: UnsafeMutableRawPointer?)

@_silgen_name("kasugai_term_wakeup_fd")
func kasugaiTermWakeupFd(_ handle: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("kasugai_term_drain")
func kasugaiTermDrain(_ handle: UnsafeMutableRawPointer?) -> UInt8

@_silgen_name("kasugai_term_write")
func kasugaiTermWrite(
    _ handle: UnsafeMutableRawPointer?,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int
) -> UInt8

@_silgen_name("kasugai_term_resize")
func kasugaiTermResize(
    _ handle: UnsafeMutableRawPointer?,
    _ cols: UInt16,
    _ rows: UInt16
) -> UInt8

@_silgen_name("kasugai_term_scroll")
func kasugaiTermScroll(
    _ handle: UnsafeMutableRawPointer?,
    _ deltaLines: Int64
) -> UInt8

@_silgen_name("kasugai_term_exited")
func kasugaiTermExited(_ handle: UnsafeMutableRawPointer?) -> UInt8

@_silgen_name("kasugai_term_snapshot_json")
func kasugaiTermSnapshotJson(_ handle: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("kasugai_string_free")
func kasugaiStringFree(_ value: UnsafeMutablePointer<CChar>?)
