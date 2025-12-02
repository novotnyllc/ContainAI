use std::collections::BTreeMap;
use std::env;
use std::io::{self, Read, Write};
use std::os::fd::{AsRawFd, OwnedFd};
use std::process;
use std::thread;

use agent_task_runner::channel::SeqPacketChannel;
use agent_task_runner::protocol::{
    MSG_RUN_ERROR, MSG_RUN_EXIT, MSG_RUN_REQUEST, MSG_RUN_STARTED, MSG_RUN_STDERR, MSG_RUN_STDIN,
    MSG_RUN_STDIN_CLOSE, MSG_RUN_STDOUT,
};
use agent_task_runner::DEFAULT_SOCKET_PATH;
use anyhow::{anyhow, bail, Context, Result};
use nix::sys::socket::{self, AddressFamily, SockFlag, SockType, UnixAddr};
use serde::Deserialize;
use serde_json::json;

/// Entry point that reports any fatal error before exiting with code 1.
fn main() {
    if let Err(err) = real_main() {
        let _ = writeln!(io::stderr(), "agent-task-runnerctl: {err}");
        process::exit(1);
    }
}

/// Parses CLI options, connects to the daemon, and proxies stdio for the
/// lifetime of the remote command.
fn real_main() -> Result<()> {
    let options = parse_args()?;
    let payload = build_payload(&options)?;
    let conn = connect_socket(&options.socket_path)?;
    let mut channel = SeqPacketChannel::new(conn);
    channel
        .send_message(MSG_RUN_REQUEST, &payload)
        .context("failed to send run request")?;

    let stdin_channel = channel
        .try_clone()
        .context("failed to clone channel for stdin")?;
    let stdin_handle = spawn_stdin(stdin_channel);

    let exit_status = pump_session(&mut channel)?;
    let _ = stdin_handle.join();
    match exit_status {
        RunOutcome::Exit { code } => {
            if code == 0 {
                Ok(())
            } else {
                process::exit(code)
            }
        }
        RunOutcome::Error(err) => Err(err),
    }
}

/// All configuration derived from CLI flags and environment variables.
struct Options {
    socket_path: String,
    cwd: Option<String>,
    session_id: Option<String>,
    agent: Option<String>,
    binary: Option<String>,
    env: Vec<(String, String)>,
    argv: Vec<String>,
}

/// Parses command line arguments and environment defaults into `Options`.
fn parse_args() -> Result<Options> {
    let mut args = env::args().skip(1);
    let mut socket_path =
        env::var("AGENT_TASK_RUNNER_SOCKET").unwrap_or_else(|_| DEFAULT_SOCKET_PATH.into());
    let mut cwd = None;
    let mut session_id = env::var("HOST_SESSION_ID").ok();
    let mut agent = env::var("CONTAINAI_AGENT_NAME").ok();
    let mut binary = env::var("CONTAINAI_AGENT_BINARY").ok();
    let mut env_pairs = Vec::new();
    let mut argv: Vec<String> = Vec::new();

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--socket" => {
                socket_path = args.next().context("--socket requires a value")?;
            }
            "--cwd" => {
                cwd = Some(args.next().context("--cwd requires a value")?);
            }
            "--session" => {
                session_id = Some(args.next().context("--session requires a value")?);
            }
            "--agent" => {
                agent = Some(args.next().context("--agent requires a value")?);
            }
            "--binary" => {
                binary = Some(args.next().context("--binary requires a value")?);
            }
            "--env" => {
                let pair = args.next().context("--env requires KEY=VALUE")?;
                env_pairs.push(parse_env_pair(&pair)?);
            }
            "--" => {
                argv.extend(args.map(|v| v.to_string()));
                break;
            }
            other if other.starts_with('-') => {
                bail!("unknown option {other}");
            }
            value => {
                argv.push(value.to_string());
                argv.extend(args.map(|v| v.to_string()));
                break;
            }
        }
    }

    if argv.is_empty() {
        bail!("missing command to run");
    }

    Ok(Options {
        socket_path,
        cwd,
        session_id,
        agent,
        binary,
        env: env_pairs,
        argv,
    })
}

/// Validates a `KEY=VALUE` string and enforces the uppercase
/// `CONTAINAI_*` style environment requirements.
fn parse_env_pair(pair: &str) -> Result<(String, String)> {
    let mut parts = pair.splitn(2, '=');
    let key = parts
        .next()
        .map(str::to_string)
        .filter(|k| !k.is_empty())
        .ok_or_else(|| anyhow!("environment key missing"))?;
    if !key
        .chars()
        .all(|c| c == '_' || c.is_ascii_uppercase() || c.is_ascii_digit())
    {
        bail!("environment key '{key}' contains invalid characters");
    }
    let value = parts.next().unwrap_or("");
    Ok((key, value.to_string()))
}

/// Converts the desired command invocation into the JSON payload the daemon
/// expects.
fn build_payload(options: &Options) -> Result<Vec<u8>> {
    let mut env_map = BTreeMap::new();
    for (key, value) in &options.env {
        env_map.insert(key.clone(), value.clone());
    }

    let payload = json!({
        "argv": options.argv,
        "env": if env_map.is_empty() { None } else { Some(env_map) },
        "cwd": options.cwd,
        "session_id": options.session_id,
        "agent": options.agent,
        "binary": options.binary,
    });
    Ok(serde_json::to_vec(&payload)?)
}

/// Opens a seqpacket socket and connects it to the daemon path.
fn connect_socket(path: &str) -> Result<OwnedFd> {
    let owned = socket::socket(
        AddressFamily::Unix,
        SockType::SeqPacket,
        SockFlag::empty(),
        None,
    )
    .map_err(|e| anyhow!(e))?;
    let addr = UnixAddr::new(path).context("invalid socket path")?;
    socket::connect(owned.as_raw_fd(), &addr).map_err(|e| anyhow!(e))?;
    Ok(owned)
}

/// Streams local stdin into the remote session until EOF or an error occurs.
fn spawn_stdin(channel: SeqPacketChannel) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        let mut stdin = io::stdin();
        let mut buf = [0u8; 16 * 1024];
        loop {
            match stdin.read(&mut buf) {
                Ok(0) => {
                    let _ = channel.send_message(MSG_RUN_STDIN_CLOSE, &[]);
                    break;
                }
                Ok(n) => {
                    if channel.send_message(MSG_RUN_STDIN, &buf[..n]).is_err() {
                        break;
                    }
                }
                Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => {
                    let _ = channel.send_message(MSG_RUN_STDIN_CLOSE, &[]);
                    break;
                }
            }
        }
    })
}

/// Simplified result emitted by `pump_session` so callers can translate it to
/// shell exit codes.
enum RunOutcome {
    Exit { code: i32 },
    Error(anyhow::Error),
}

#[derive(Deserialize)]
/// JSON payload returned by the daemon when the sandbox process exits.
struct RunExitPayload {
    code: Option<i32>,
    signal: Option<i32>,
    success: bool,
}

/// Pumps the message loop, forwarding stdout/stderr and interpreting control
/// frames until the session ends.
fn pump_session(channel: &mut SeqPacketChannel) -> Result<RunOutcome> {
    let mut stdout = io::stdout();
    let mut stderr = io::stderr();
    loop {
        match channel.recv_message() {
            Ok(Some((header, payload))) => match header.msg_type {
                MSG_RUN_STARTED => continue,
                MSG_RUN_STDOUT => {
                    stdout.write_all(&payload)?;
                    stdout.flush()?;
                }
                MSG_RUN_STDERR => {
                    stderr.write_all(&payload)?;
                    stderr.flush()?;
                }
                MSG_RUN_ERROR => {
                    let message = String::from_utf8_lossy(&payload).into_owned();
                    return Ok(RunOutcome::Error(anyhow!(message)));
                }
                MSG_RUN_EXIT => {
                    let exit: RunExitPayload =
                        serde_json::from_slice(&payload).context("malformed exit payload")?;
                    let code = exit
                        .code
                        .or_else(|| exit.success.then_some(0))
                        .unwrap_or_else(|| exit.signal.unwrap_or(1) + 128);
                    return Ok(RunOutcome::Exit { code });
                }
                other => {
                    eprintln!("agent-task-runnerctl: ignoring unexpected message {other}");
                }
            },
            Ok(None) => {
                return Ok(RunOutcome::Error(anyhow!("runner socket closed")));
            }
            Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
            Err(err) => return Ok(RunOutcome::Error(err.into())),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::parse_env_pair;

    #[test]
    fn parse_env_pair_handles_simple_values() {
        let (k, v) = parse_env_pair("FOO=bar").unwrap();
        assert_eq!(k, "FOO");
        assert_eq!(v, "bar");
    }

    #[test]
    fn parse_env_pair_rejects_lowercase_keys() {
        assert!(parse_env_pair("foo=bar").is_err());
    }
}
