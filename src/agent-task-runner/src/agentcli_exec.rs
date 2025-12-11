use std::env;
use std::ffi::{CString, OsString};
use std::io::{self, IoSlice, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::prelude::RawFd;
use std::os::unix::process::CommandExt;
use std::process::Command;

use agent_task_runner::protocol::{
    AgentTaskRunnerMsgHeader, AgentTaskRunnerRegister, MSG_REGISTER,
};
use agent_task_runner::{struct_bytes, write_cstring_buf};
use anyhow::{bail, Context, Result};
use libc::c_int;
use nix::sys::socket::{
    self, AddressFamily, ControlMessage, MsgFlags, SockFlag, SockType, UnixAddr,
};
use nix::unistd::{getgid, getpid, getuid, initgroups, setresgid, setresuid, User};
use nix::sched::{unshare, CloneFlags};

fn main() {
    if let Err(err) = real_main() {
        let _ = writeln!(io::stderr(), "agentcli-exec: {:#}", err);
        std::process::exit(1);
    }
}

fn real_main() -> Result<()> {
    let mut args = env::args_os();
    let _ = args.next();
    let argv: Vec<OsString> = args.collect();
    if argv.is_empty() {
        bail!("Usage: agentcli-exec <command> [args...]");
    }

    let socket_path = get_env("AGENT_TASK_RUNNER_SOCKET")
        .unwrap_or_else(|| "/run/agent-task-runner.sock".to_string());

    let restricted_mode = setup_runner(&socket_path)?;

    if !restricted_mode {
        // Only attempt to switch user if we are not in a restricted user namespace
        // (i.e. one where we could only map the current user)
        switch_user().context("failed to switch user")?;
    }

    let target_cmd = &argv[0];
    let target_args = &argv[1..];

    let mut command = Command::new(target_cmd);
    command.args(target_args);

    // Always attempt to load the audit shim if present.
    // This provides defense-in-depth logging even if seccomp notifications fail or are bypassed.
    let shim_path = "/usr/lib/containai/libaudit_shim.so";
    if std::path::Path::new(shim_path).exists() {
        let current_preload = env::var("LD_PRELOAD").unwrap_or_default();
        let new_preload = if current_preload.is_empty() {
            shim_path.to_string()
        } else {
            format!("{}:{}", shim_path, current_preload)
        };
        command.env("LD_PRELOAD", new_preload);
    }

    let err = command.exec();
    bail!("exec failed: {}", err);
}

fn switch_user() -> Result<()> {
    let user_name = get_env("CONTAINAI_CLI_USER").unwrap_or_else(|| "agentcli".to_owned());
    let user = User::from_name(&user_name)
        .context("failed to lookup agentcli user")?
        .ok_or_else(|| anyhow::anyhow!("user '{user_name}' not found"))?;
    let user_cstr = CString::new(user.name.clone()).context("user name contains NUL byte")?;
    initgroups(&user_cstr, user.gid).context("initgroups failed")?;
    setresgid(user.gid, user.gid, user.gid).context("setresgid failed")?;
    setresuid(user.uid, user.uid, user.uid).context("setresuid failed")?;
    Ok(())
}

fn setup_runner(socket_path: &str) -> Result<bool> {
    // Unshare user namespace to gain CAP_SYS_ADMIN for seccomp notification
    // This is necessary because the container drops CAP_SYS_ADMIN, but SCMP_ACT_NOTIFY requires it.
    let restricted = unshare_user_namespace().context("failed to unshare user namespace")?;

    let notify_fd = install_seccomp_filter().context("unable to install seccomp filter")?;
    let agent_name = get_env("CONTAINAI_AGENT_NAME");
    let binary_name = get_env("CONTAINAI_AGENT_BINARY");
    register_with_runner(
        socket_path,
        notify_fd.as_ref().map(|fd| fd.as_raw_fd()),
        agent_name.as_deref(),
        binary_name.as_deref(),
    )?;
    Ok(restricted)
}

fn unshare_user_namespace() -> Result<bool> {
    let uid = getuid();
    let gid = getgid();

    unshare(CloneFlags::CLONE_NEWUSER).context("unshare(CLONE_NEWUSER) failed")?;

    // Try mapping root to root (requires CAP_SETUID in parent)
    // If this works, we are not restricted and can switch users.
    let full_map = "0 0 65536";
    if std::fs::write("/proc/self/uid_map", full_map).is_ok() {
        // Try writing gid_map. If it fails, disable setgroups first.
        if std::fs::write("/proc/self/gid_map", full_map).is_err() {
            std::fs::write("/proc/self/setgroups", "deny").context("failed to write setgroups")?;
            std::fs::write("/proc/self/gid_map", full_map).context("failed to write gid_map")?;
        }
        return Ok(false);
    }

    // Fallback: Map 0 inside to current UID outside.
    // This allows us to be root inside (gaining CAP_SYS_ADMIN), but we can't switch to other users.
    let uid_map = format!("0 {} 1", uid);
    std::fs::write("/proc/self/uid_map", uid_map).context("failed to write uid_map")?;

    std::fs::write("/proc/self/setgroups", "deny").context("failed to write setgroups")?;
    let gid_map = format!("0 {} 1", gid);
    std::fs::write("/proc/self/gid_map", gid_map).context("failed to write gid_map")?;

    Ok(true)
}

fn install_seccomp_filter() -> Result<Option<OwnedFd>> {
    use libseccomp_sys::{
        scmp_filter_ctx, seccomp_export_bpf, seccomp_init, seccomp_release, seccomp_rule_add,
        SCMP_ACT_ALLOW, SCMP_ACT_NOTIFY,
    };
    use std::io::Read;

    unsafe {
        let ctx: scmp_filter_ctx = seccomp_init(SCMP_ACT_ALLOW);
        if ctx.is_null() {
            bail!("seccomp_init returned null");
        }

        for syscall in [libc::SYS_execve, libc::SYS_execveat] {
            let rc = seccomp_rule_add(ctx, SCMP_ACT_NOTIFY, syscall as c_int, 0);
            if rc != 0 {
                seccomp_release(ctx);
                bail!("seccomp_rule_add failed for syscall {syscall}: {rc}");
            }
        }

        // Export BPF to a pipe so we can read it back and load it manually.
        // This allows us to bypass libseccomp's seccomp_load which might force
        // flags like TSYNC that cause issues in some environments (e.g. WSL2).
        let (read_fd, write_fd) = nix::unistd::pipe().context("pipe failed")?;
        let rc = seccomp_export_bpf(ctx, write_fd.as_raw_fd());
        // Close write end so read can finish
        drop(write_fd); // Use drop to close OwnedFd correctly

        if rc != 0 {
            // read_fd will be dropped and closed
            seccomp_release(ctx);
            bail!("seccomp_export_bpf failed: {rc}");
        }

        let mut bpf_data = Vec::new();
        let mut f = std::fs::File::from_raw_fd(read_fd.as_raw_fd());
        f.read_to_end(&mut bpf_data).context("failed to read BPF")?;
        // f is dropped here, closing read_fd
        // We need to ensure read_fd is not double closed.
        // File::from_raw_fd takes ownership, so it will close it.
        // But read_fd is an OwnedFd. We should use into_raw_fd() to prevent double close.
        // Or just let File take ownership and forget read_fd.
        std::mem::forget(read_fd);

        seccomp_release(ctx);

        if bpf_data.len() % std::mem::size_of::<libc::sock_filter>() != 0 {
            bail!("BPF data length alignment error");
        }
        let len = bpf_data.len() / std::mem::size_of::<libc::sock_filter>();
        let filter_ptr = bpf_data.as_ptr() as *const libc::sock_filter;

        let prog = libc::sock_fprog {
            len: len as u16,
            filter: filter_ptr as *mut libc::sock_filter,
        };

        // Attempt 1: Try with TSYNC | NEW_LISTENER (standard)
        // SECCOMP_FILTER_FLAG_TSYNC (1) | SECCOMP_FILTER_FLAG_NEW_LISTENER (8) = 9
        let ret_tsync = libc::syscall(
            libc::SYS_seccomp,
            1, // SECCOMP_SET_MODE_FILTER
            9,
            &prog as *const libc::sock_fprog,
        );
        if ret_tsync >= 0 {
            return Ok(Some(OwnedFd::from_raw_fd(ret_tsync as i32)));
        }
        let errno_tsync = std::io::Error::last_os_error().raw_os_error().unwrap_or(0);

        // Attempt 2: Try with NEW_LISTENER only (no TSYNC)
        let ret_no_tsync = libc::syscall(
            libc::SYS_seccomp,
            1, // SECCOMP_SET_MODE_FILTER
            8,
            &prog as *const libc::sock_fprog,
        );
        if ret_no_tsync >= 0 {
            return Ok(Some(OwnedFd::from_raw_fd(ret_no_tsync as i32)));
        }
        let errno_no_tsync = std::io::Error::last_os_error().raw_os_error().unwrap_or(0);

        if errno_no_tsync == libc::EBUSY || errno_tsync == libc::EBUSY {
             if is_wsl() {
                 // WSL2 kernels (as of 5.15.x) often lack CONFIG_SECCOMP_USER_NOTIFICATION or have conflicting
                 // PID 1 seccomp filters (microsoft/WSL#9783). This is a known limitation documented in
                 // docs/security/wsl2-runtime-analysis.md. We suppress the warning to avoid alarming users,
                 // as the system will fall back to the userspace Audit Shim for observability.
                 return Ok(None);
             }
             // For non-WSL systems, EBUSY is unexpected but we still want to proceed with a warning
             // rather than crashing, as the audit shim provides fallback coverage.
             eprintln!("WARNING: Seccomp user notification is unavailable (EBUSY). This is unexpected on non-WSL systems. Continuing without syscall interception.");
             return Ok(None);
        }

        bail!("Seccomp filter load failed (TSYNC: {}, NoTSYNC: {}).", errno_tsync, errno_no_tsync);
    }
}

fn register_with_runner(
    socket_path: &str,
    notify_fd: Option<RawFd>,
    agent_name: Option<&str>,
    binary_name: Option<&str>,
) -> Result<()> {
    let sock = socket::socket(
        AddressFamily::Unix,
        SockType::SeqPacket,
        SockFlag::empty(),
        None,
    )
    .map_err(|e| anyhow::anyhow!(e))?;
    let addr = UnixAddr::new(socket_path).context("invalid socket path")?;
    socket::connect(sock.as_raw_fd(), &addr).map_err(|e| anyhow::anyhow!(e))?;

    let header = AgentTaskRunnerMsgHeader::new(
        MSG_REGISTER,
        std::mem::size_of::<AgentTaskRunnerRegister>() as u32,
    );
    let mut payload = AgentTaskRunnerRegister::empty();
    payload.pid = getpid().as_raw() as u32;
    write_cstring_buf(&mut payload.agent_name, agent_name, "unknown");
    write_cstring_buf(&mut payload.binary_name, binary_name, "unknown");

    let header_bytes = struct_bytes(&header);
    let payload_bytes = struct_bytes(&payload);
    let iov = [IoSlice::new(header_bytes), IoSlice::new(payload_bytes)];

    if let Some(fd) = notify_fd {
        let cmsg = [ControlMessage::ScmRights(&[fd])];
        socket::sendmsg::<UnixAddr>(sock.as_raw_fd(), &iov, &cmsg, MsgFlags::empty(), None)
            .map_err(|e| anyhow::anyhow!(e))?;
    } else {
        socket::sendmsg::<UnixAddr>(sock.as_raw_fd(), &iov, &[], MsgFlags::empty(), None)
            .map_err(|e| anyhow::anyhow!(e))?;
    }
    Ok(())
}

fn is_wsl() -> bool {
    std::fs::read_to_string("/proc/version")
        .map(|s| s.to_lowercase().contains("microsoft") || s.to_lowercase().contains("wsl"))
        .unwrap_or(false)
}

fn get_env(name: &str) -> Option<String> {
    env::var(name).ok().filter(|v| !v.is_empty())
}
