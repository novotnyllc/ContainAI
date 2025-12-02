use std::collections::BTreeMap;
use std::env;
use std::ffi::{CString, OsString};
use std::fs;
use std::io::{self, Write};
use std::os::unix::ffi::OsStringExt;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};
use caps::{CapSet, CapsHashSet, Capability};
use nix::errno::Errno;
use nix::mount::{mount, umount2, MntFlags, MsFlags};
use nix::unistd::{chdir, initgroups, setresgid, setresuid, User};
use serde::Deserialize;
use std::os::unix::fs::PermissionsExt;

fn main() {
    if let Err(err) = real_main() {
        let _ = writeln!(io::stderr(), "agent-task-sandbox: {err}");
        std::process::exit(1);
    }
}

fn real_main() -> Result<()> {
    let config = Config::parse()?;
    let env_map = load_environment()?;
    prepare_mounts(&config)?;
    drop_privileges(&config.user)?;
    ensure_capabilities_dropped()?;
    apply_environment(&env_map)?;
    change_directory(&config.cwd)?;
    exec_command(&config)
}

struct Config {
    user: String,
    cwd: PathBuf,
    hide_paths: Vec<PathBuf>,
    apparmor_profile: Option<String>,
    command: Vec<OsString>,
}

impl Config {
    fn parse() -> Result<Self> {
        let mut args = env::args_os().skip(1);
        let default_user =
            env::var("CONTAINAI_RUNNER_USER").unwrap_or_else(|_| "agentuser".to_string());
        let default_cwd =
            env::var("CONTAINAI_WORKSPACE_DIR").unwrap_or_else(|_| "/workspace".to_string());
        let default_profile = match env::var("CONTAINAI_TASK_APPARMOR") {
            Ok(value) if value.eq_ignore_ascii_case("none") || value.trim().is_empty() => None,
            Ok(value) => Some(value),
            Err(_) => Some("containai-task".to_string()),
        };
        let hide_env = env::var("CONTAINAI_RUNNER_HIDE_PATHS").ok();
        let mut hide_paths = parse_hide_paths(hide_env);

        let mut user = default_user;
        let mut cwd = PathBuf::from(default_cwd);
        let mut apparmor_profile = default_profile;
        let mut command: Vec<OsString> = Vec::new();
        while let Some(arg) = args.next() {
            match arg.to_str() {
                Some("--user") => {
                    user = args
                        .next()
                        .map(|v| v.to_string_lossy().to_string())
                        .context("--user requires a value")?;
                }
                Some("--cwd") => {
                    cwd = PathBuf::from(
                        args.next()
                            .map(|v| v.to_string_lossy().to_string())
                            .context("--cwd requires a value")?,
                    );
                }
                Some("--hide") => {
                    let value = args
                        .next()
                        .map(PathBuf::from)
                        .context("--hide requires a path")?;
                    hide_paths.push(value);
                }
                Some("--apparmor-profile") => {
                    apparmor_profile = args.next().map(|v| v.to_string_lossy().to_string());
                }
                Some("--") => {
                    command.extend(args);
                    break;
                }
                _ => {
                    command.push(arg);
                    command.extend(args);
                    break;
                }
            }
        }

        dedup_paths(&mut hide_paths);

        if command.is_empty() {
            bail!("missing command for sandbox execution");
        }

        Ok(Self {
            user,
            cwd,
            hide_paths,
            apparmor_profile,
            command,
        })
    }
}

fn parse_hide_paths(raw: Option<String>) -> Vec<PathBuf> {
    let fallback = "/run/agent-secrets:/run/agent-data:/run/agent-data-export".to_string();
    let source = raw.unwrap_or(fallback);
    source
        .split(':')
        .filter_map(|entry| {
            let trimmed = entry.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(PathBuf::from(trimmed))
            }
        })
        .collect()
}

fn dedup_paths(paths: &mut Vec<PathBuf>) {
    paths.sort();
    paths.dedup();
}

fn load_environment() -> Result<BTreeMap<String, String>> {
    #[derive(Deserialize)]
    struct EnvPayload(BTreeMap<String, String>);

    let env_json = env::var("RUNNER_ENV_JSON").unwrap_or_default();
    if env_json.is_empty() {
        let mut defaults = BTreeMap::new();
        defaults.insert(
            "PATH".into(),
            "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin".into(),
        );
        defaults.insert("HOME".into(), "/home/agentuser".into());
        defaults.insert("USER".into(), "agentuser".into());
        defaults.insert("LOGNAME".into(), "agentuser".into());
        defaults.insert("SHELL".into(), "/bin/bash".into());
        defaults.insert("TERM".into(), "xterm-256color".into());
        return Ok(defaults);
    }
    let payload: EnvPayload =
        serde_json::from_str(&env_json).context("invalid RUNNER_ENV_JSON payload")?;
    Ok(payload.0)
}

fn prepare_mounts(config: &Config) -> Result<()> {
    mount(
        Option::<&str>::None,
        "/",
        Option::<&str>::None,
        MsFlags::MS_REC | MsFlags::MS_PRIVATE,
        Option::<&str>::None,
    )
    .context("failed to remount root private")?;

    for path in &config.hide_paths {
        mask_sensitive_path(path)?;
    }
    Ok(())
}

fn mask_sensitive_path(path: &Path) -> Result<()> {
    if !path.exists() {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("unable to create parent for {}", path.display()))?;
        }
        fs::create_dir_all(path)
            .with_context(|| format!("unable to create mask path {}", path.display()))?;
    }
    if let Err(err) = umount2(path, MntFlags::MNT_DETACH) {
        match err {
            Errno::ENOENT | Errno::EINVAL => {}
            _ => {
                return Err(anyhow!("failed to unmount {}: {err}", path.display()));
            }
        }
    }
    mount(
        Some("tmpfs"),
        path,
        Some("tmpfs"),
        MsFlags::MS_NODEV | MsFlags::MS_NOSUID | MsFlags::MS_NOEXEC,
        Some("size=1,mode=000"),
    )
    .with_context(|| format!("failed to mask {}", path.display()))?;
    let perms = fs::Permissions::from_mode(0o000);
    fs::set_permissions(path, perms)
        .with_context(|| format!("failed to set permissions on {}", path.display()))?;
    Ok(())
}

fn drop_privileges(user_name: &str) -> Result<()> {
    let user = User::from_name(user_name)
        .context("failed to lookup sandbox user")?
        .ok_or_else(|| anyhow::anyhow!("user '{user_name}' not found"))?;
    let user_cstr = CString::new(user.name.clone()).context("user name contained NUL byte")?;
    initgroups(&user_cstr, user.gid).context("initgroups failed")?;
    setresgid(user.gid, user.gid, user.gid).context("setresgid failed")?;
    setresuid(user.uid, user.uid, user.uid).context("setresuid failed")?;
    enforce_no_new_privs()?;
    Ok(())
}

fn enforce_no_new_privs() -> Result<()> {
    let rc = unsafe { libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) };
    if rc != 0 {
        return Err(anyhow!(
            "prctl(PR_SET_NO_NEW_PRIVS) failed: {}",
            io::Error::last_os_error()
        ));
    }
    Ok(())
}

fn ensure_capabilities_dropped() -> Result<()> {
    let effective = caps::read(None, CapSet::Effective)
        .context("failed to query effective capabilities")?;
    if effective.contains(&Capability::CAP_SYS_ADMIN) {
        bail!("sandbox still has CAP_SYS_ADMIN; refusing to launch user command");
    }
    if !effective.is_empty() {
        bail!(
            "sandbox still has capabilities enabled: {}",
            format_capability_set(&effective)
        );
    }
    Ok(())
}

fn format_capability_set(set: &CapsHashSet) -> String {
    let mut names: Vec<String> = set.iter().map(|cap| format!("{cap:?}")).collect();
    names.sort();
    names.join(", ")
}

fn apply_environment(env_map: &BTreeMap<String, String>) -> Result<()> {
    unsafe {
        libc::clearenv();
    }
    for (key, value) in env_map {
        env::set_var(key, value);
    }
    Ok(())
}

fn change_directory(target: &Path) -> Result<()> {
    if let Err(err) = chdir(target) {
        eprintln!(
            "agent-task-sandbox: warning: failed to chdir to {}: {err}; falling back to /workspace",
            target.display()
        );
        chdir(Path::new("/workspace")).context("failed to change directory to /workspace")?;
    }
    Ok(())
}

fn exec_command(config: &Config) -> Result<()> {
    let mut argv: Vec<OsString> = Vec::new();
    if let Some(profile) = &config.apparmor_profile {
        let aa_exec =
            env::var("CONTAINAI_AA_EXEC_PATH").unwrap_or_else(|_| "/usr/bin/aa-exec".into());
        if Path::new(&aa_exec).exists() {
            argv.push(OsString::from(aa_exec));
            argv.push(OsString::from("-p"));
            argv.push(OsString::from(profile));
            argv.push(OsString::from("--"));
        } else {
            eprintln!("agent-task-sandbox: warning: aa-exec missing, running without AppArmor");
        }
    }
    argv.extend(config.command.iter().cloned());

    let cstrings: Vec<CString> = argv
        .iter()
        .map(|arg| CString::new(arg.clone().into_vec()))
        .collect::<Result<_, _>>()
        .context("argument contained NUL byte")?;
    if cstrings.is_empty() {
        bail!("no command resolved after applying AppArmor wrapper");
    }

    let c_refs: Vec<&std::ffi::CStr> = cstrings.iter().map(|s| s.as_c_str()).collect();
    let (cmd, rest) = c_refs.split_first().context("missing executable in argv")?;
    match nix::unistd::execvp(cmd, rest) {
        Ok(_) => unreachable!("execvp returned unexpectedly"),
        Err(err) => Err(anyhow::anyhow!(err)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_hide_paths_include_sensitive_mounts() {
        let parsed = parse_hide_paths(None);
        assert!(parsed.contains(&PathBuf::from("/run/agent-secrets")));
        assert!(parsed.contains(&PathBuf::from("/run/agent-data")));
        assert!(parsed.contains(&PathBuf::from("/run/agent-data-export")));
    }

    #[test]
    fn dedup_paths_removes_duplicates_and_whitespace() {
        let mut parsed = parse_hide_paths(Some(
            " /run/agent-secrets ::/tmp/custom :: /run/agent-secrets ".into(),
        ));
        dedup_paths(&mut parsed);
        let occurrences = parsed
            .iter()
            .filter(|p| *p == &PathBuf::from("/run/agent-secrets"))
            .count();
        assert_eq!(occurrences, 1);
        assert!(parsed.contains(&PathBuf::from("/tmp/custom")));
    }
}
