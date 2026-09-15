import Cocoa

if CommandLine.arguments.contains("--rectangle-blur-renderer") {
    WindowFrostRenderer.run()
}

// Recovery runs before AppKit loads the storyboard or creates the normal app delegate.
// The helper uses the same signed executable and never starts another Rectangle UI.
if CommandLine.arguments.contains("--rectangle-window-recovery-standby") {
    WindowRecoveryHelper.runStandby()
}

if let index = CommandLine.arguments.firstIndex(of: "--rectangle-window-recovery") {
    guard CommandLine.arguments.indices.contains(index + 1) else {
        fputs("Missing window recovery request.\n", stderr)
        exit(64)
    }
    WindowRecoveryHelper.run(requestPath: CommandLine.arguments[index + 1])
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
