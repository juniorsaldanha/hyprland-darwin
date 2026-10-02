import Common
import Darwin

/// posix_spawn into a new process group, so a timeout or stop can kill the plugin's whole process tree
/// (kill(-pid)). POSIX_SPAWN_CLOEXEC_DEFAULT: the child inherits only fds 0-2, so other plugins' pipe ends
/// never leak into it (a leaked write end would keep their stdout from ever reaching EOF).
func spawnPlugin(path: String, environment: [String: String], directory: String, stdin: Int32, stdout: Int32, stderr: Int32) -> ResOrStr<pid_t> {
    var actions: posix_spawn_file_actions_t? = nil
    unsafe posix_spawn_file_actions_init(&actions)
    defer { unsafe posix_spawn_file_actions_destroy(&actions) }
    unsafe posix_spawn_file_actions_adddup2(&actions, stdin, 0)
    unsafe posix_spawn_file_actions_adddup2(&actions, stdout, 1)
    unsafe posix_spawn_file_actions_adddup2(&actions, stderr, 2)
    unsafe posix_spawn_file_actions_addchdir_np(&actions, directory)

    var attributes: posix_spawnattr_t? = nil
    unsafe posix_spawnattr_init(&attributes)
    defer { unsafe posix_spawnattr_destroy(&attributes) }
    unsafe posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
    unsafe posix_spawnattr_setpgroup(&attributes, 0)

    let argv: [UnsafeMutablePointer<CChar>?] = unsafe [strdup(path), nil]
    let envp: [UnsafeMutablePointer<CChar>?] = unsafe environment.map { unsafe strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
        unsafe argv.forEach { unsafe free($0) }
        unsafe envp.forEach { unsafe free($0) }
    }
    var pid: pid_t = 0
    let rc = unsafe posix_spawn(&pid, path, &actions, &attributes, argv, envp)
    return rc == 0 ? .success(pid) : .failure("spawn failed: \(unsafe String(cString: strerror(rc)))")
}
