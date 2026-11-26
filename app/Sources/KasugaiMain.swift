import AppKit
import Darwin
import Foundation

@main
struct KasugaiApplication {
    private static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        exit(EXIT_FAILURE)
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first {
            if first == "daemon" {
                exit(KasugaiDaemonServer.runCLI(arguments: Array(args.dropFirst())))
            }
            if first == "daemon-status" {
                exit(KasugaiDaemonClient.runStatusCLI(arguments: Array(args.dropFirst())))
            }
            if first == "daemon-restart" {
                exit(KasugaiDaemonClient.runRestartCLI(arguments: Array(args.dropFirst())))
            }
            if first == "ctl" {
                exit(LocalOrchestratorClient.runCLI(arguments: Array(args.dropFirst())))
            }
            if first == "mcp-stdio" {
                exit(LocalOrchestratorClient.runMCPStdio())
            }
            if first == "ui-snapshot" {
                exit(KasugaiUISnapshotRenderer.runCLI(arguments: Array(args.dropFirst())))
            }
        }

        if ProcessInfo.processInfo.environment["KASUGAI_SELF_TEST"] == "1" {
            let tests: [(name: String, run: () -> Bool)] = [
                ("AppSettings", KasugaiAppSettings.runSelfTests),
                ("RateLimitService", RateLimitService.runSelfTests),
                ("Kizu Core FFI", KasugaiCore.runSelfTests),
                ("KasugaiDaemon", KasugaiDaemonClient.runSelfTests),
                ("WebViewSyncMachine", WebViewSyncMachine.runSelfTests),
                ("SyncLoopMachine", SyncLoopMachine.runSelfTests),
                ("MobileBridgeMachine", MobileBridgeMachine.runSelfTests),
                ("FactoryRunMachine", FactoryRunMachine.runSelfTests),
                ("FactoryRunStore", FactoryRunStore.runSelfTests),
                ("MobileBridgeServer", MobileBridgeServer.runSelfTests),
                ("SandboxedChatWebView", SandboxedChatWebView.runSelfTests),
                ("LocalPreviewBrowserView", LocalPreviewBrowserView.runSelfTests),
                ("LocalBrowserBridge", LocalBrowserBridgeServer.runSelfTests),
                ("GitWorkspace", GitWorkspace.runSelfTests),
                ("KasugaiTerminal", KasugaiTerminal.runSelfTests),
                ("TerminalPaneViewController", TerminalPaneViewController.runSelfTests),
                ("LocalOrchestratorBridge", LocalOrchestratorClient.runSelfTests),
                ("ComposerView", ComposerView.runSelfTests),
                ("MainSplitViewController", MainSplitViewController.runSelfTests),
            ]
            for test in tests where !test.run() {
                fail("self-test failed: \(test.name)")
            }
            print("kasugai self-test: ok")
            return
        }

        let app = NSApplication.shared
        let delegate = KasugaiAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
