use std::env;
use std::ffi::{CString, OsString};
use std::io::{self, IoSlice, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::ffi::OsStringExt;
use std::os::unix::prelude::RawFd;

use agent_task_runner::protocol::{
    AgentTaskRunnerMsgHeader, AgentTaskRunnerRegister, MSG_REGISTER,
};
use agent_task_runner::{struct_bytes, write_cstring_buf};
use anyhow::{bail, Context, Result};
use libc::c_int;
use nix::sys::socket::{
    self, AddressFamily, ControlMessage, MsgFlags, SockFlag, SockType, UnixAddr,
};
use nix::unistd::{execvp, initgroups, setresgid, setresuid, User};

fn main() {
    if let Err(err) = real_main() {
        let _ = writeln!(io::stderr(), "agentcli-exec: {err}");
        std::process::exit(1);
    }
}

fn real_main() -> Result<()> {
    eprintln!("DEBUG: agentcli-exec starting");
    let mut args = env::args_os();
    let _ = args.next();
    let argv: Vec<OsString> = args.collect();
    if argv.is_empty() {
        bail!("Usage: agentcli-exec <command> [args...]");
    }

    if let Some(socket_path) = get_env("AGENT_TASK_RUNNER_SOCKET") {
        setup_runner(&socket_path)?;
        // Restore NoNewPrivs which was removed from seccomp loading to prevent -125 errors.
        // This prevents the user code from gaining privileges via setuid binaries.
        unsafe {
            if libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0 {
                bail!("prctl(PR_SET_NO_NEW_PRIVS) failed: {}", std::io::Error::last_os_error());
            }
        }
    }

    switch_user()?;

    let cstrings: Vec<CString> = argv
        .into_iter()
        .map(|arg| CString::new(arg.into_vec()))
        .collect::<Result<_, _>>()
        .context("argument contained NUL byte")?;
    let (cmd, _) = cstrings
        .split_first()
        .context("missing command after argv parsing")?;
    execvp(cmd, &cstrings)?;
    unreachable!("execvp should not return on success");
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

fn setup_runner(socket_path: &str) -> Result<()> {
    let notify_fd = match install_seccomp_filter() {
        Ok(fd) => fd,
        Err(err) => {
            eprintln!("agentcli-exec: unable to install seccomp filter (continuing without interception): {err}");
            return Ok(());
        }
    };
    let agent_name = get_env("CONTAINAI_AGENT_NAME");
    let binary_name = get_env("CONTAINAI_AGENT_BINARY");
    if let Err(err) = register_with_runner(
        socket_path,
        notify_fd.as_raw_fd(),
        agent_name.as_deref(),
        binary_name.as_deref(),
    ) {
        return Err(err);
    }
    Ok(())
}

fn install_seccomp_filter() -> Result<OwnedFd> {
    use libseccomp_sys::{
        scmp_filter_ctx, seccomp_init, seccomp_load, seccomp_notify_fd, seccomp_release,
        seccomp_rule_add, SCMP_ACT_ALLOW, SCMP_ACT_NOTIFY,
    };

    unsafe {
        let ctx: scmp_filter_ctx = seccomp_init(SCMP_ACT_ALLOW);
        if ctx.is_null() {
            bail!("seccomp_init returned null");
        }
        // let rc = seccomp_attr_set(ctx, SCMP_FLTATR_CTL_NNP, 1);
        // if rc != 0 {
        //     seccomp_release(ctx);
        //     bail!("seccomp_attr_set failed: {rc}");
        // }
        for syscall in [libc::SYS_execve, libc::SYS_execveat] {
            let rc = seccomp_rule_add(ctx, SCMP_ACT_NOTIFY, syscall as c_int, 0);
            if rc != 0 {
                seccomp_release(ctx);
                bail!("seccomp_rule_add failed for syscall {syscall}: {rc}");
            }
        }
        let rc = seccomp_load(ctx);
        if rc != 0 {
            seccomp_release(ctx);
            bail!("seccomp_load failed: {rc}");
        }
        let fd = seccomp_notify_fd(ctx);
        seccomp_release(ctx);
        if fd < 0 {
            bail!("seccomp_notify_fd returned {fd}");
        }
        Ok(OwnedFd::from_raw_fd(fd))
    }
}

fn register_with_runner(
    socket_path: &str,
    notify_fd: RawFd,
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
    eprintln!("DEBUG: agentcli-exec connected to socket");

    let header = AgentTaskRunnerMsgHeader::new(
        MSG_REGISTER,
        std::mem::size_of::<AgentTaskRunnerRegister>() as u32,
    );
    let mut payload = AgentTaskRunnerRegister::empty();
    payload.pid = unsafe { libc::getpid() as u32 };
    write_cstring_buf(&mut payload.agent_name, agent_name, "unknown");
    write_cstring_buf(&mut payload.binary_name, binary_name, "unknown");

    let header_bytes = struct_bytes(&header);
    let payload_bytes = struct_bytes(&payload);
    let iov = [IoSlice::new(header_bytes), IoSlice::new(payload_bytes)];
    let cmsg = [ControlMessage::ScmRights(&[notify_fd])];
    socket::sendmsg::<UnixAddr>(sock.as_raw_fd(), &iov, &cmsg, MsgFlags::empty(), None)
        .map_err(|e| anyhow::anyhow!(e))?;
    eprintln!("DEBUG: agentcli-exec sent message");
    Ok(())
}

fn get_env(name: &str) -> Option<String> {
    match env::var(name).ok().filter(|v| !v.is_empty()) {
        Some(val) => Some(val),
        None => None,
    }
}
