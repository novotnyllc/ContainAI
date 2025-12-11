use std::env;
use std::fs;
use std::os::unix::fs::{chown, MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{bail, Context, Result};
use nix::unistd::{setresgid, setresuid, Gid, Uid};
use sha2::{Digest, Sha256};

const RUNTIME_BASE: &str = "/run/mcp-wrappers";
const WRAPPER_CORE: &str = "/usr/local/libexec/mcp-wrapper-core.py";
const AUDIT_SHIM: &str = "/usr/lib/containai/libaudit_shim.so";
const MIN_UID: u32 = 20000;
const MAX_UID: u32 = 40000;

fn main() {
    if let Err(err) = real_main() {
        eprintln!("mcp-wrapper-runner: {:#}", err);
        std::process::exit(1);
    }
}

pub fn calculate_uid(wrapper_name: &str, attempt: u32) -> u32 {
    let mut hasher = Sha256::new();
    hasher.update(wrapper_name.as_bytes());
    hasher.update(attempt.to_be_bytes());
    let hash = hasher.finalize();
    // Use first 4 bytes to determine offset
    let offset = u32::from_be_bytes(hash[0..4].try_into().unwrap());
    MIN_UID + (offset % (MAX_UID - MIN_UID))
}

fn is_uid_colliding(uid: u32, current_name: &str) -> Result<bool> {
    let base = Path::new(RUNTIME_BASE);
    if !base.exists() {
        return Ok(false);
    }

    for entry in fs::read_dir(base)? {
        let entry = entry?;
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }

        let dir_name = entry.file_name();
        let dir_name_str = dir_name.to_string_lossy();

        // Skip our own directory (if it exists from a previous run)
        if dir_name_str == current_name {
            continue;
        }

        let metadata = entry.metadata()?;
        if metadata.uid() == uid {
            return Ok(true);
        }
    }
    Ok(false)
}

pub fn get_wrapper_name(prog_name: &str, env_name: Option<String>) -> Result<String> {
    let name = if prog_name.starts_with("mcp-wrapper-") && prog_name != "mcp-wrapper-runner" {
        prog_name.strip_prefix("mcp-wrapper-").unwrap().to_string()
    } else {
        env_name
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "default".to_string())
    };

    if !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        bail!("invalid wrapper name: {}", name);
    }
    Ok(name)
}

fn real_main() -> Result<()> {
    // 1. Identify Wrapper Name
    let args: Vec<String> = env::args().collect();
    let prog_name = Path::new(&args[0])
        .file_name()
        .context("invalid program name")?
        .to_string_lossy();

    let wrapper_name = get_wrapper_name(&prog_name, env::var("CONTAINAI_WRAPPER_NAME").ok())?;

    // 2. Calculate Deterministic UID with Collision Detection
    let mut attempt = 0;
    let target_uid = loop {
        let candidate_uid = calculate_uid(&wrapper_name, attempt);
        if !is_uid_colliding(candidate_uid, &wrapper_name)? {
            break candidate_uid;
        }
        attempt += 1;
        if attempt > 100 {
            bail!("failed to find free UID after 100 attempts");
        }
    };
    let target_gid = target_uid;

    // 3. Setup Runtime Directory
    let runtime_dir = PathBuf::from(RUNTIME_BASE).join(&wrapper_name);
    if runtime_dir.exists() {
        // Safety: Ensure we are not following symlinks or traversing out
        if runtime_dir.is_symlink() {
            bail!("runtime directory is a symlink");
        }
        // Clean up previous run if it exists
        fs::remove_dir_all(&runtime_dir).context("failed to clean runtime dir")?;
    }

    fs::create_dir_all(&runtime_dir).context("failed to create runtime dir")?;
    let tmp_dir = runtime_dir.join("tmp");
    fs::create_dir_all(&tmp_dir).context("failed to create tmp dir")?;

    // Set ownership to target UID
    chown(&runtime_dir, Some(target_uid), Some(target_gid)).context("chown runtime failed")?;
    chown(&tmp_dir, Some(target_uid), Some(target_gid)).context("chown tmp failed")?;

    // Set permissions (rwx------)
    fs::set_permissions(&runtime_dir, fs::Permissions::from_mode(0o700))?;
    fs::set_permissions(&tmp_dir, fs::Permissions::from_mode(0o700))?;

    // 4. Copy Capabilities
    // Default location: /home/agentuser/.config/containai/capabilities/<name>
    // We need to copy this to the runtime dir so the isolated user can read it
    let cap_base = env::var("CONTAINAI_CAP_ROOT").unwrap_or_else(|_| {
        "/home/agentuser/.config/containai/capabilities".to_string()
    });
    let cap_src = Path::new(&cap_base).join(&wrapper_name);

    let cap_dst_root = runtime_dir.join("caps");
    if cap_src.exists() {
        let cap_dst = cap_dst_root.join(&wrapper_name);
        fs::create_dir_all(&cap_dst_root).context("failed to create caps dir")?;
        chown(&cap_dst_root, Some(target_uid), Some(target_gid)).context("chown caps failed")?;
        fs::set_permissions(&cap_dst_root, fs::Permissions::from_mode(0o700))?;

        copy_dir_recursive(&cap_src, &cap_dst, target_uid, target_gid)?;
    }

    // 5. Prepare Environment
    // We must clear LD_PRELOAD before switching, but we want to re-inject it for the child
    let mut new_env = env::vars().collect::<Vec<_>>();
    new_env.retain(|(k, _)| k != "LD_PRELOAD" && k != "CONTAINAI_CAP_ROOT");

    // Inject runtime variables
    new_env.push(("CONTAINAI_WRAPPER_NAME".to_string(), wrapper_name.to_string()));
    new_env.push(("CONTAINAI_WRAPPER_RUNTIME".to_string(), runtime_dir.to_string_lossy().to_string()));
    new_env.push(("TMPDIR".to_string(), tmp_dir.to_string_lossy().to_string()));
    new_env.push(("XDG_RUNTIME_DIR".to_string(), runtime_dir.to_string_lossy().to_string()));

    // Point child to the isolated capabilities
    if cap_dst_root.exists() {
        new_env.push(("CONTAINAI_CAP_ROOT".to_string(), cap_dst_root.to_string_lossy().to_string()));
    }

    // Re-inject audit shim if it exists
    if Path::new(AUDIT_SHIM).exists() {
        new_env.push(("LD_PRELOAD".to_string(), AUDIT_SHIM.to_string()));
    }

    // 6. Drop Privileges
    // We are currently root (setuid). We need to switch to target_uid.
    // We assume the group exists or we just use the numeric ID.

    // Set GID first
    setresgid(Gid::from_raw(target_gid), Gid::from_raw(target_gid), Gid::from_raw(target_gid))
        .context("failed to setresgid")?;

    // Set UID
    setresuid(Uid::from_raw(target_uid), Uid::from_raw(target_uid), Uid::from_raw(target_uid))
        .context("failed to setresuid")?;

    // 7. Execute Wrapper Core
    // We use execvp to replace the current process
    let mut cmd = Command::new("python3");
    cmd.arg(WRAPPER_CORE);

    // Pass through original arguments
    for arg in env::args().skip(1) {
        cmd.arg(arg);
    }

    cmd.env_clear();
    for (k, v) in new_env {
        cmd.env(k, v);
    }

    use std::os::unix::process::CommandExt;
    let err = cmd.exec();
    bail!("exec failed: {}", err);
}

fn copy_dir_recursive(src: &Path, dst: &Path, uid: u32, gid: u32) -> Result<()> {
    if !dst.exists() {
        fs::create_dir_all(dst)?;
        chown(dst, Some(uid), Some(gid))?;
        fs::set_permissions(dst, fs::Permissions::from_mode(0o700))?;
    }

    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        let dst_path = dst.join(entry.file_name());

        if ty.is_dir() {
            copy_dir_recursive(&entry.path(), &dst_path, uid, gid)?;
        } else if ty.is_file() {
            fs::copy(entry.path(), &dst_path)?;
            chown(&dst_path, Some(uid), Some(gid))?;
            fs::set_permissions(&dst_path, fs::Permissions::from_mode(0o600))?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculate_uid_deterministic() {
        let uid1 = calculate_uid("test-wrapper", 0);
        let uid2 = calculate_uid("test-wrapper", 0);
        assert_eq!(uid1, uid2);
        assert!(uid1 >= MIN_UID);
        assert!(uid1 < MAX_UID);
    }

    #[test]
    fn test_calculate_uid_distribution() {
        let uid1 = calculate_uid("wrapper-a", 0);
        let uid2 = calculate_uid("wrapper-b", 0);
        assert_ne!(uid1, uid2);
    }

    #[test]
    fn test_calculate_uid_attempts() {
        let uid1 = calculate_uid("test-wrapper", 0);
        let uid2 = calculate_uid("test-wrapper", 1);
        assert_ne!(uid1, uid2);
    }

    #[test]
    fn test_get_wrapper_name_from_prog_name() {
        let name = get_wrapper_name("mcp-wrapper-foo", None).unwrap();
        assert_eq!(name, "foo");
    }

    #[test]
    fn test_get_wrapper_name_from_env() {
        let name = get_wrapper_name("mcp-wrapper-runner", Some("bar".to_string())).unwrap();
        assert_eq!(name, "bar");
    }

    #[test]
    fn test_get_wrapper_name_default() {
        let name = get_wrapper_name("mcp-wrapper-runner", None).unwrap();
        assert_eq!(name, "default");
    }

    #[test]
    fn test_get_wrapper_name_validation() {
        assert!(get_wrapper_name("mcp-wrapper-invalid/name", None).is_err());
        assert!(get_wrapper_name("mcp-wrapper-invalid name", None).is_err());
        assert!(get_wrapper_name("mcp-wrapper-valid-name_123", None).is_ok());
    }
}
