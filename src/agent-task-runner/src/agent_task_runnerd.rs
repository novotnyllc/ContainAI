use std::collections::BTreeMap;
use std::env;
use std::ffi::CString;
use std::fs::{File, OpenOptions};
use std::io::{self, ErrorKind, IoSliceMut, Read, Write};
use std::os::fd::{AsFd, AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

use agent_task_runner::channel::SeqPacketChannel;
use agent_task_runner::protocol::{
    AgentTaskRunnerMsgHeader, AgentTaskRunnerRegister, MSG_REGISTER, MSG_RUN_ERROR, MSG_RUN_EXIT,
    MSG_RUN_REQUEST, MSG_RUN_STARTED, MSG_RUN_STDERR, MSG_RUN_STDIN, MSG_RUN_STDIN_CLOSE,
    MSG_RUN_STDOUT,
};
use agent_task_runner::seccomp::{
    recv_notification, send_response, SeccompNotif, SeccompNotifResp,
    SECCOMP_USER_NOTIF_FLAG_CONTINUE,
};
use agent_task_runner::{struct_bytes_mut, DEFAULT_SOCKET_PATH, MAX_MESSAGE_SIZE};
use anyhow::{anyhow, bail, Context, Result};
use nix::errno::Errno;
use nix::poll::{poll, PollFd, PollFlags, PollTimeout};
use nix::sys::signal::{kill, Signal};
use nix::sys::socket::{
    self, AddressFamily, Backlog, ControlMessageOwned, MsgFlags, SockFlag, SockType, UnixAddr,
};
use nix::unistd::{self, Pid};
use serde::{Deserialize, Serialize};
use serde_json::json;
use signal_hook::flag;
use audit_protocol::AuditEvent;
use chrono::Utc;
use std::os::unix::net::UnixStream;

const MAX_CLIENTS: usize = 64;
const DEFAULT_LOG_PATH: &str = "/run/agent-task-runner/events.log";
const AUDIT_SOCKET_PATH: &str = "/run/containai/audit.sock";
const PATH_MAX: usize = 4096;

#[derive(Clone, Copy)]
enum PolicyMode {
    Observe,
    Enforce,
}

impl PolicyMode {
    fn from_str(value: &str) -> Self {
        match value {
            "enforce" => PolicyMode::Enforce,
            _ => PolicyMode::Observe,
        }
    }
}

/// Tracks an agent process that registered for seccomp notifications.
#[derive(Debug)]
struct RunnerClient {
    notify_fd: Option<OwnedFd>,
    pid: libc::pid_t,
    agent: String,
    binary: String,
}

/// Serialized event record written to the daemon's audit log.
#[derive(Serialize)]
struct Event<'a> {
    ts: i64,
    pid: i32,
    agent: &'a str,
    binary: &'a str,
    path: &'a str,
    action: &'a str,
}

/// User-facing run request that arrives over the seqpacket control socket.
#[derive(Deserialize)]
struct RunRequest {
    argv: Vec<String>,
    env: Option<BTreeMap<String, String>>,
    cwd: Option<String>,
    session_id: Option<String>,
    agent: Option<String>,
    binary: Option<String>,
}

fn main() {
    if let Err(err) = real_main() {
        let _ = writeln!(io::stderr(), "agent-task-runnerd: {err}");
        std::process::exit(1);
    }
}

fn real_main() -> Result<()> {
    let args: Vec<String> = env::args().collect();
    let options = parse_args(&args)?;
    let running = Arc::new(AtomicBool::new(true));
    for sig in [libc::SIGTERM, libc::SIGINT] {
        flag::register(sig, Arc::clone(&running))?;
    }

    let log_file = Arc::new(Mutex::new(
        OpenOptions::new()
            .create(true)
            .append(true)
            .open(&options.log_path)
            .with_context(|| format!("unable to open log file {}", options.log_path))?,
    ));

    let listen_fd = create_listener(&options.socket_path)?;
    let mut clients: Vec<Option<RunnerClient>> =
        std::iter::repeat_with(|| None).take(MAX_CLIENTS).collect();

    while running.load(Ordering::Relaxed) {
        let mut poll_fds: Vec<PollFd> = Vec::with_capacity(MAX_CLIENTS + 1);
        let mut index_map: Vec<usize> = Vec::with_capacity(MAX_CLIENTS);
        poll_fds.push(PollFd::new(listen_fd.as_fd(), PollFlags::POLLIN));
        for (idx, client) in clients.iter().enumerate() {
            if let Some(client) = client {
                if let Some(fd) = &client.notify_fd {
                    poll_fds.push(PollFd::new(fd.as_fd(), PollFlags::POLLIN));
                    index_map.push(idx);
                }
            }
        }

        let mut accept_ready = false;
        let mut ready_clients: Vec<(usize, PollFlags)> = Vec::new();

        let ready = poll(&mut poll_fds, PollTimeout::from(500u16));
        match ready {
            Ok(0) => continue,
            Ok(n) => {
                eprintln!("DEBUG: poll returned {}", n);
            }
            Err(Errno::EINTR) => continue,
            Err(err) => return Err(anyhow!(err)),
        }

        if poll_fds[0]
            .revents()
            .unwrap_or(PollFlags::empty())
            .contains(PollFlags::POLLIN)
        {
            eprintln!("DEBUG: listener POLLIN");
            accept_ready = true;
        }

        for (poll_entry, client_index) in poll_fds.iter().skip(1).zip(index_map.iter()) {
            let revents = poll_entry.revents().unwrap_or(PollFlags::empty());
            if revents.is_empty() {
                continue;
            }
            ready_clients.push((*client_index, revents));
        }

        drop(poll_fds);
        drop(index_map);

        if accept_ready {
            if let Err(err) =
                accept_client(listen_fd.as_raw_fd(), &mut clients, &log_file, &options)
            {
                eprintln!("agent-task-runnerd: failed to accept client: {err}");
            }
        }

        for (client_index, revents) in ready_clients {
            let remove = if revents
                .intersects(PollFlags::POLLERR | PollFlags::POLLHUP | PollFlags::POLLNVAL)
            {
                true
            } else {
                match clients[client_index].as_mut() {
                    Some(client) => handle_notification(client, &log_file, options.policy_mode),
                    None => Ok(()),
                }
                .is_err()
            };
            if remove {
                if let Some(client) = clients[client_index].take() {
                    drop(client);
                }
            }
        }
    }

    unistd::unlink(Path::new(&options.socket_path)).ok();
    Ok(())
}

/// Resolved daemon configuration derived from CLI flags and environment vars.
#[derive(Clone)]
struct Options {
    socket_path: String,
    log_path: String,
    policy_mode: PolicyMode,
    sandbox_bin: String,
    unshare_bin: String,
    agent_user: String,
    workspace_dir: String,
    home_dir: String,
    apparmor_profile: Option<String>,
    hide_paths: Vec<String>,
}

/// Parses command line arguments and environment overrides into `Options`.
fn parse_args(argv: &[String]) -> Result<Options> {
    let mut socket_path = DEFAULT_SOCKET_PATH.to_string();
    let mut log_path = DEFAULT_LOG_PATH.to_string();
    let mut policy_mode = PolicyMode::Observe;
    let sandbox_bin = env::var("CONTAINAI_RUNNER_SANDBOX")
        .unwrap_or_else(|_| "/usr/local/bin/agent-task-sandbox".into());
    let unshare_bin = env::var("CONTAINAI_UNSHARE_BIN").unwrap_or_else(|_| "unshare".into());
    let agent_user = env::var("CONTAINAI_RUNNER_USER").unwrap_or_else(|_| "agentuser".into());
    let workspace_dir =
        env::var("CONTAINAI_WORKSPACE_DIR").unwrap_or_else(|_| "/workspace".into());
    let home_dir =
        env::var("CONTAINAI_AGENT_HOME").unwrap_or_else(|_| format!("/home/{agent_user}"));
    let apparmor_profile = match env::var("CONTAINAI_TASK_APPARMOR") {
        Ok(value) if value.eq_ignore_ascii_case("none") || value.trim().is_empty() => None,
        Ok(value) => Some(value),
        Err(_) => Some("containai-task".into()),
    };
    let hide_paths = env::var("CONTAINAI_RUNNER_HIDE_PATHS")
        .unwrap_or_else(|_| "/run/agent-secrets:/run/agent-data:/run/agent-data-export".into())
        .split(':')
        .filter(|p| !p.is_empty())
        .map(|p| p.to_string())
        .collect::<Vec<_>>();

    let mut iter = argv.iter().skip(1);
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--socket" => {
                let value = iter.next().context("--socket requires a path")?;
                socket_path = value.clone();
            }
            "--log" => {
                let value = iter.next().context("--log requires a path")?;
                log_path = value.clone();
            }
            "--policy" => {
                let value = iter.next().context("--policy requires a mode")?;
                policy_mode = PolicyMode::from_str(value);
            }
            "--help" => {
                print_usage(&argv[0]);
                std::process::exit(0);
            }
            other => {
                return Err(anyhow!("unknown argument {other}"));
            }
        }
    }

    Ok(Options {
        socket_path,
        log_path,
        policy_mode,
        sandbox_bin,
        unshare_bin,
        agent_user,
        workspace_dir,
        home_dir,
        apparmor_profile,
        hide_paths,
    })
}

/// Prints basic usage information when the daemon is invoked incorrectly.
fn print_usage(prog: &str) {
    eprintln!("Usage: {prog} [--socket PATH] [--log PATH] [--policy observe|enforce]");
}

/// Creates the well-known seqpacket listening socket and readies it for use.
fn create_listener(socket_path: &str) -> Result<OwnedFd> {
    let owned = socket::socket(
        AddressFamily::Unix,
        SockType::SeqPacket,
        SockFlag::empty(),
        None,
    )
    .map_err(|e| anyhow!(e))?;
    unistd::unlink(Path::new(socket_path)).ok();
    let addr = UnixAddr::new(socket_path)?;
    socket::bind(owned.as_raw_fd(), &addr).map_err(|e| anyhow!(e))?;
    let _ = unsafe { libc::chmod(CString::new(socket_path)?.as_ptr(), 0o666) };
    let backlog = Backlog::new(16).map_err(|e| anyhow!(e))?;
    socket::listen(&owned, backlog).map_err(|e| anyhow!(e))?;
    Ok(owned)
}

/// Accepts a new control connection, handling either registration or run
/// requests inline.
fn accept_client(
    listen_fd: RawFd,
    clients: &mut [Option<RunnerClient>],
    log_file: &Arc<Mutex<File>>,
    options: &Options,
) -> Result<()> {
    eprintln!("DEBUG: accept_client called");
    let conn_fd = socket::accept(listen_fd).map_err(|e| anyhow!(e))?;
    let conn = unsafe { OwnedFd::from_raw_fd(conn_fd) };
    let mut header = AgentTaskRunnerMsgHeader::new(0, 0);
    let mut header_buf = [0u8; std::mem::size_of::<AgentTaskRunnerMsgHeader>()];
    let mut payload_buf = vec![0u8; MAX_MESSAGE_SIZE];
    let mut cmsg_space = nix::cmsg_space!([RawFd; 1]);
    let mut received_fd: Option<OwnedFd> = None;
    let (msg_bytes, msg_flags) = {
        let mut iov = [
            IoSliceMut::new(&mut header_buf),
            IoSliceMut::new(&mut payload_buf),
        ];
        let msg = socket::recvmsg::<UnixAddr>(
            conn.as_raw_fd(),
            &mut iov,
            Some(&mut cmsg_space),
            MsgFlags::empty(),
        )
        .map_err(|e| anyhow!(e))?;
        let mut cmsgs = msg.cmsgs().map_err(|e| anyhow!(e))?;
        while let Some(cmsg) = cmsgs.next() {
            if let ControlMessageOwned::ScmRights(fds) = cmsg {
                if let Some(fd) = fds.first() {
                    received_fd = Some(unsafe { OwnedFd::from_raw_fd(*fd) });
                    break;
                }
            }
        }
        (msg.bytes, msg.flags)
    };

    if msg_bytes >= std::mem::size_of::<AgentTaskRunnerMsgHeader>() {
        header = unsafe {
            std::ptr::read_unaligned(header_buf.as_ptr() as *const AgentTaskRunnerMsgHeader)
        };
    }

    if msg_bytes < std::mem::size_of::<AgentTaskRunnerMsgHeader>() {
        bail!("incomplete header from client");
    }

    if msg_flags.contains(MsgFlags::MSG_TRUNC) {
        bail!("message truncated");
    }

    let payload_size = msg_bytes - std::mem::size_of::<AgentTaskRunnerMsgHeader>();
    payload_buf.truncate(payload_size);

    match header.msg_type {
        MSG_REGISTER => {
            eprintln!("DEBUG: MSG_REGISTER received");
            // let notify_fd = received_fd.ok_or_else(|| anyhow!("missing SCM_RIGHTS fd"))?;
            let notify_fd = received_fd;
            let mut payload = AgentTaskRunnerRegister::empty();
            if payload_buf.len() != std::mem::size_of::<AgentTaskRunnerRegister>() {
                bail!("invalid payload length {}", payload_buf.len());
            }
            struct_bytes_mut(&mut payload).copy_from_slice(&payload_buf);
            add_client(clients, notify_fd, &payload, log_file)?;
        }
        MSG_RUN_REQUEST => {
            if header.length as usize != payload_buf.len() {
                bail!("invalid run payload length {}", header.length);
            }
            spawn_run_session(conn, payload_buf, options.clone(), Arc::clone(log_file));
            return Ok(());
        }
        other => {
            bail!("unexpected message type {other}");
        }
    }

    Ok(())
}

/// Stores a newly registered client in the fixed-size table.
fn add_client(
    clients: &mut [Option<RunnerClient>],
    notify_fd: Option<OwnedFd>,
    payload: &AgentTaskRunnerRegister,
    log_file: &Arc<Mutex<File>>,
) -> Result<()> {
    for slot in clients.iter_mut() {
        if slot.is_none() {
            let agent = cstring_from_buf(&payload.agent_name);
            let binary = cstring_from_buf(&payload.binary_name);
            let client = RunnerClient {
                notify_fd,
                pid: payload.pid as libc::pid_t,
                agent,
                binary,
            };
            log_event(
                log_file,
                client.pid,
                &client.agent,
                &client.binary,
                "<register>",
                "register",
            )?;
            *slot = Some(client);
            return Ok(());
        }
    }
    bail!("too many clients");
}

/// Converts the fixed-size C strings in registration messages to Rust `String`s.
fn cstring_from_buf(buf: &[u8]) -> String {
    let len = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    String::from_utf8_lossy(&buf[..len]).to_string()
}

/// Splits the accepted seqpacket connection off to a worker thread so the main
/// loop can keep polling for seccomp notifications.
fn spawn_run_session(
    conn: OwnedFd,
    payload: Vec<u8>,
    options: Options,
    log_file: Arc<Mutex<File>>,
) {
    if let Err(err) = thread::Builder::new()
        .name("agent-runner-session".into())
        .spawn(move || {
            if let Err(err) = handle_run_session(conn, payload, options, &log_file) {
                eprintln!("agent-task-runnerd: run session failed: {err}");
            }
        })
    {
        eprintln!("agent-task-runnerd: unable to spawn session thread: {err}");
    }
}

/// Handles a single run request, spawning the sandbox helper and proxying data
/// between the remote command and the client.
fn handle_run_session(
    conn: OwnedFd,
    payload: Vec<u8>,
    options: Options,
    log_file: &Arc<Mutex<File>>,
) -> Result<()> {
    let request: RunRequest =
        serde_json::from_slice(&payload).context("malformed run request payload")?;
    if request.argv.is_empty() {
        bail!("run request missing argv");
    }

    let agent_name = request
        .agent
        .clone()
        .or_else(|| env::var("AGENT_NAME").ok())
        .unwrap_or_else(|| "unknown-agent".into());
    let binary_name = request
        .binary
        .clone()
        .or_else(|| env::var("CONTAINAI_AGENT_BINARY").ok())
        .unwrap_or_else(|| "agent-cli".into());
    let command_label = request
        .argv
        .get(0)
        .cloned()
        .unwrap_or_else(|| "<unknown>".into());

    log_event(
        log_file,
        0,
        &agent_name,
        &binary_name,
        &command_label,
        "run-start",
    )?;

    let env_map = build_environment_map(&request, &options)?;
    let cwd = sanitize_cwd(request.cwd.as_deref(), &options);

    let channel = SeqPacketChannel::new(conn);
    let recv_channel = channel
        .try_clone()
        .context("failed to dup runner socket for stdin")?;
    let shutdown_channel = recv_channel
        .try_clone()
        .context("failed to dup runner socket for shutdown")?;

    let mut child = match spawn_sandboxed_command(&request, &env_map, &cwd, &options) {
        Ok(child) => child,
        Err(err) => {
            let _ = channel.send_json(MSG_RUN_ERROR, &json!({ "error": err.to_string() }));
            log_event(
                log_file,
                0,
                &agent_name,
                &binary_name,
                &command_label,
                "run-error",
            )?;
            return Err(err);
        }
    };

    let pid = child.id();
    channel
        .send_json(
            MSG_RUN_STARTED,
            &json!({ "pid": pid, "argv": request.argv }),
        )
        .ok();

    let stdout = child
        .stdout
        .take()
        .context("runner child missing stdout pipe")?;
    let stderr = child
        .stderr
        .take()
        .context("runner child missing stderr pipe")?;

    let stdout_sender = channel
        .try_clone()
        .context("failed to dup socket for stdout")?;
    let stderr_sender = channel
        .try_clone()
        .context("failed to dup socket for stderr")?;

    let stdout_handle = stream_output(stdout, stdout_sender, MSG_RUN_STDOUT);
    let stderr_handle = stream_output(stderr, stderr_sender, MSG_RUN_STDERR);
    let stdin_handle = stream_stdin(recv_channel, child.stdin.take(), pid);

    let status = child.wait().context("failed to wait on sandbox child")?;
    shutdown_channel.shutdown_read().ok();

    let _ = stdout_handle.join();
    let _ = stderr_handle.join();
    let _ = stdin_handle.join();

    channel
        .send_json(
            MSG_RUN_EXIT,
            &json!({
                "pid": pid,
                "code": status.code(),
                "signal": status.signal(),
                "success": status.success(),
            }),
        )
        .ok();

    log_event(
        log_file,
        pid as i32,
        &agent_name,
        &binary_name,
        &command_label,
        if status.success() {
            "run-exit"
        } else {
            "run-error"
        },
    )?;
    Ok(())
}

/// Builds the base environment presented to agent workloads.
fn build_environment_map(
    request: &RunRequest,
    options: &Options,
) -> Result<BTreeMap<String, String>> {
    let mut env_map = BTreeMap::new();
    env_map.insert(
        "PATH".into(),
        "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin".into(),
    );
    env_map.insert("HOME".into(), options.home_dir.clone());
    env_map.insert("USER".into(), options.agent_user.clone());
    env_map.insert("LOGNAME".into(), options.agent_user.clone());
    env_map.insert("SHELL".into(), "/bin/bash".into());
    env_map.insert("TERM".into(), "xterm-256color".into());

    if let Some(agent) = request
        .agent
        .clone()
        .or_else(|| env::var("AGENT_NAME").ok())
    {
        env_map.insert("CONTAINAI_AGENT_NAME".into(), agent);
    }
    if let Some(session) = request
        .session_id
        .clone()
        .or_else(|| env::var("HOST_SESSION_ID").ok())
    {
        env_map.insert("CONTAINAI_SESSION_ID".into(), session);
    }

    if let Some(extra_env) = &request.env {
        for (key, value) in extra_env {
            if key.len() > 128 || key.is_empty() || value.len() > 16384 {
                continue;
            }
            if !key
                .chars()
                .all(|c| c == '_' || c.is_ascii_uppercase() || c.is_ascii_digit())
            {
                continue;
            }
            env_map.insert(key.clone(), value.clone());
        }
    }

    Ok(env_map)
}

/// Clamps the requested working directory to the workspace root to avoid
/// escape attempts.
fn sanitize_cwd(requested: Option<&str>, options: &Options) -> PathBuf {
    let default_path = PathBuf::from(&options.workspace_dir);
    if let Some(path) = requested {
        let candidate = PathBuf::from(path);
        if candidate.starts_with(&options.workspace_dir)
            || candidate.starts_with(&options.home_dir)
            || candidate.starts_with("/tmp")
        {
            return candidate;
        }
    }
    default_path
}

/// Launches the sandbox helper via `unshare` with the appropriate command line
/// and environment variables.
fn spawn_sandboxed_command(
    request: &RunRequest,
    env_map: &BTreeMap<String, String>,
    cwd: &Path,
    options: &Options,
) -> Result<Child> {
    let hide_concat = options.hide_paths.join(":");
    let cwd_string = cwd.to_string_lossy().to_string();

    let mut command = Command::new(&options.unshare_bin);
    command.args([
        "--mount",
        "--pid",
        "--fork",
        "--kill-child",
        "--mount-proc",
        "--propagation",
        "private",
    ]);
    command.arg("--");
    command.arg(&options.sandbox_bin);
    command.arg("--user");
    command.arg(&options.agent_user);
    command.arg("--cwd");
    command.arg(&cwd_string);
    for hide in &options.hide_paths {
        command.arg("--hide");
        command.arg(hide);
    }
    if let Some(profile) = &options.apparmor_profile {
        command.arg("--apparmor-profile");
        command.arg(profile);
    }
    command.arg("--");
    for arg in &request.argv {
        command.arg(arg);
    }
    command.stdin(Stdio::piped());
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());
    command.env_clear();
    command.env("RUNNER_ENV_JSON", serde_json::to_string(env_map)?);
    command.env("CONTAINAI_RUNNER_HIDE_PATHS", hide_concat);
    if let Some(profile) = &options.apparmor_profile {
        command.env("CONTAINAI_TASK_APPARMOR", profile);
    }
    command.env("CONTAINAI_WORKSPACE_DIR", &cwd_string);
    command.env("CONTAINAI_RUNNER_USER", &options.agent_user);

    command.spawn().context("failed to spawn sandbox helper")
}

/// Mirrors a child stdout/stderr pipe onto the seqpacket channel.
fn stream_output<R>(
    mut reader: R,
    sender: SeqPacketChannel,
    message_type: u32,
) -> thread::JoinHandle<()>
where
    R: Read + Send + 'static,
{
    thread::spawn(move || {
        let mut buf = [0u8; 16 * 1024];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    if sender.send_message(message_type, &buf[..n]).is_err() {
                        break;
                    }
                }
                Err(err) if err.kind() == ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
    })
}

enum StdinOutcome {
    Graceful,
    Disconnected,
}

/// Forwards incoming `MSG_RUN_STDIN*` frames into the child process stdin.
fn stream_stdin(
    channel: SeqPacketChannel,
    mut stdin_pipe: Option<ChildStdin>,
    child_pid: u32,
) -> thread::JoinHandle<StdinOutcome> {
    thread::spawn(move || loop {
        match channel.recv_message() {
            Ok(Some((header, data))) => match header.msg_type {
                MSG_RUN_STDIN => {
                    if let Some(stdin) = stdin_pipe.as_mut() {
                        if stdin.write_all(&data).is_err() {
                            return StdinOutcome::Graceful;
                        }
                    }
                }
                MSG_RUN_STDIN_CLOSE => {
                    stdin_pipe.take();
                }
                _ => {}
            },
            Ok(None) => {
                if stdin_pipe.is_some() {
                    let _ = kill(Pid::from_raw(child_pid as i32), Signal::SIGTERM);
                }
                return StdinOutcome::Disconnected;
            }
            Err(err) if err.kind() == ErrorKind::Interrupted => continue,
            Err(_) => return StdinOutcome::Disconnected,
        }
    })
}

/// Services a single seccomp user notification and writes an audit log entry.
fn handle_notification(
    client: &mut RunnerClient,
    log_file: &Arc<Mutex<File>>,
    policy_mode: PolicyMode,
) -> Result<()> {
    let notify_fd = match client.notify_fd.as_ref() {
        Some(fd) => fd.as_raw_fd(),
        None => return Ok(()), // Should not happen given poll logic
    };

    let mut req = SeccompNotif::default();
    let mut resp = SeccompNotifResp::default();
    if let Err(err) = recv_notification(notify_fd, &mut req) {
        if err.kind() == io::ErrorKind::Interrupted || err.kind() == io::ErrorKind::WouldBlock {
            return Ok(());
        }
        return Err(err.into());
    }

    resp.id = req.id;
    let syscall = req.data.nr;
    let path = if syscall as i64 == libc::SYS_execve || syscall as i64 == libc::SYS_execveat {
        let addr = req.data.args[0];
        resolve_exec_path(client.pid, addr)
    } else {
        format!("syscall-{syscall}")
    };

    let allow = should_allow_path(&path, &policy_mode);
    log_event(
        log_file,
        client.pid,
        &client.agent,
        &client.binary,
        &path,
        if allow { "allow" } else { "deny" },
    )?;
    if allow {
        resp.flags = SECCOMP_USER_NOTIF_FLAG_CONTINUE;
        resp.val = 0;
        resp.error = 0;
    } else {
        resp.val = -libc::EPERM as i64;
        resp.error = -libc::EPERM;
    }

    if let Err(err) = send_response(notify_fd, &mut resp) {
        if err.raw_os_error() == Some(libc::ENOENT) || err.raw_os_error() == Some(libc::ESRCH) {
            return Ok(());
        }
        return Err(err.into());
    }
    Ok(())
}

/// Returns `true` if the given path is permitted by the current policy.
fn should_allow_path(path: &str, policy: &PolicyMode) -> bool {
    match policy {
        PolicyMode::Observe => true,
        PolicyMode::Enforce => {
            !(path.starts_with("/run/agent-secrets") || path.starts_with("/run/agent-data"))
        }
    }
}

/// Reads a remote process's argv pointer to recover the execve path.
fn resolve_exec_path(pid: libc::pid_t, addr: u64) -> String {
    if addr == 0 {
        return "<unknown>".to_string();
    }
    let mut buffer = vec![0u8; PATH_MAX];
    let mut offset = 0usize;
    while offset < buffer.len() {
        match read_remote(pid, addr + offset as u64, &mut buffer[offset..]) {
            Ok(0) => break,
            Ok(read) => {
                if buffer[offset..offset + read].contains(&0) {
                    break;
                }
                offset += read;
            }
            Err(_) => break,
        }
    }
    let end = buffer.iter().position(|&b| b == 0).unwrap_or(buffer.len());
    if end == 0 {
        "<unknown>".to_string()
    } else {
        String::from_utf8_lossy(&buffer[..end]).to_string()
    }
}

/// Wrapper around `process_vm_readv` that copies memory out of the traced
/// process.
fn read_remote(pid: libc::pid_t, addr: u64, buf: &mut [u8]) -> io::Result<usize> {
    let local = libc::iovec {
        iov_base: buf.as_mut_ptr() as *mut libc::c_void,
        iov_len: buf.len(),
    };
    let remote = libc::iovec {
        iov_base: addr as *mut libc::c_void,
        iov_len: buf.len(),
    };
    let rc = unsafe { libc::process_vm_readv(pid, &local, 1, &remote, 1, 0) };
    if rc < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(rc as usize)
    }
}

/// Appends a JSON event record to the daemon's log file.
fn log_event(
    log_file: &Arc<Mutex<File>>,
    pid: i32,
    agent: &str,
    binary: &str,
    path: &str,
    action: &str,
) -> Result<()> {
    eprintln!("DEBUG: log_event called for action: {}", action);
    let event = Event {
        ts: timestamp_ms(),
        pid,
        agent,
        binary,
        path,
        action,
    };
    let mut guard = log_file.lock().expect("log file poisoned");
    serde_json::to_writer(&mut *guard, &event)?;
    guard.write_all(b"\n")?;
    guard.flush()?;

    // Also send to unified audit log
    send_audit_event(pid, agent, binary, path, action);

    Ok(())
}

fn send_audit_event(pid: i32, agent: &str, binary: &str, path: &str, action: &str) {
    let event = AuditEvent {
        timestamp: Utc::now(),
        source: "agent-task-runner".to_string(),
        event_type: action.to_string(),
        payload: serde_json::json!({
            "pid": pid,
            "agent": agent,
            "binary": binary,
            "path": path
        }),
    };

    if let Ok(json) = serde_json::to_string(&event) {
        if let Ok(mut stream) = UnixStream::connect(AUDIT_SOCKET_PATH) {
            let _ = stream.write_all(json.as_bytes());
            let _ = stream.write_all(b"\n");
        }
    }
}

fn timestamp_ms() -> i64 {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    (now.as_secs() as i64) * 1000 + (now.subsec_millis() as i64)
}
