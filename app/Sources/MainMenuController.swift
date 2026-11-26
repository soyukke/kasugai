import AppKit
import Foundation

enum KasugaiMenuAction {
    case openSettings
    case newThread
    case addProject
    case toggleSidebar
    case toggleDiff
    case toggleTerminal
    case reloadUI
    case restartDaemon
    case searchThreads
    case processQueue
}

final class MainMenuController: NSObject {
    private let handler: (KasugaiMenuAction) -> Void

    init(handler: @escaping (KasugaiMenuAction) -> Void) {
        self.handler = handler
    }

    func install(in application: NSApplication) {
        let mainMenu = NSMenu()

        let appName = KasugaiRuntimePaths.appDisplayName
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(makeItem(title: "設定…", key: ",", action: #selector(handleOpenSettings)))
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "\(appName) を終了",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "ファイル")
        fileMenu.addItem(makeItem(title: "新規スレッド", key: "n", action: #selector(handleNewThread)))
        let addProject = makeItem(
            title: "プロジェクトを追加…",
            key: "o",
            action: #selector(handleAddProject)
        )
        addProject.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(addProject)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(
            NSMenuItem(title: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        )
        let redo = NSMenuItem(title: "やり直す", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(
            NSMenuItem(title: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(
            NSMenuItem(title: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        )
        editMenu.addItem(
            NSMenuItem(title: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        )
        editMenu.addItem(
            NSMenuItem(
                title: "すべてを選択",
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            )
        )
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "表示")
        let sidebar = makeItem(
            title: "サイドバーを切り替え",
            key: "s",
            action: #selector(handleToggleSidebar)
        )
        sidebar.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(sidebar)

        let diff = makeItem(title: "変更差分を切り替え", key: "d", action: #selector(handleToggleDiff))
        diff.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(diff)

        let terminal = makeItem(
            title: "ターミナルを切り替え",
            key: "t",
            action: #selector(handleToggleTerminal)
        )
        terminal.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(terminal)
        viewMenu.addItem(.separator())
        viewMenu.addItem(
            makeItem(title: "再読み込み", key: "r", action: #selector(handleReloadUI))
        )
        let restartDaemon = makeItem(
            title: "コアデーモンを再起動",
            key: "r",
            action: #selector(handleRestartDaemon)
        )
        restartDaemon.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(restartDaemon)
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        let threadItem = NSMenuItem()
        let threadMenu = NSMenu(title: "スレッド")
        threadMenu.addItem(
            makeItem(title: "スレッドを検索", key: "k", action: #selector(handleSearchThreads))
        )
        threadMenu.addItem(.separator())
        let runQueue = makeItem(
            title: "キューを実行",
            key: "\r",
            action: #selector(handleProcessQueue)
        )
        runQueue.keyEquivalentModifierMask = [.command, .option]
        threadMenu.addItem(runQueue)
        threadItem.submenu = threadMenu
        mainMenu.addItem(threadItem)

        application.mainMenu = mainMenu
    }

    private func makeItem(title: String, key: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func handleOpenSettings() {
        handler(.openSettings)
    }

    @objc private func handleNewThread() {
        handler(.newThread)
    }

    @objc private func handleAddProject() {
        handler(.addProject)
    }

    @objc private func handleToggleSidebar() {
        handler(.toggleSidebar)
    }

    @objc private func handleToggleDiff() {
        handler(.toggleDiff)
    }

    @objc private func handleToggleTerminal() {
        handler(.toggleTerminal)
    }

    @objc private func handleReloadUI() {
        handler(.reloadUI)
    }

    @objc private func handleRestartDaemon() {
        handler(.restartDaemon)
    }

    @objc private func handleSearchThreads() {
        handler(.searchThreads)
    }

    @objc private func handleProcessQueue() {
        handler(.processQueue)
    }
}
