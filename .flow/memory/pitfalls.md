# Pitfalls

Lessons learned from NEEDS_WORK feedback. Things models tend to miss.

<!-- Entries added automatically by hooks or manually via `flowctl memory add` -->

## 2026-01-14 manual [pitfall]
ERE grep -E does not support \s for whitespace; use POSIX [[:space:]] instead

## 2026-01-16 manual [pitfall]
In sourced bash scripts, all loop variables (for/while) and read targets must be declared local to prevent shell pollution

## 2026-01-16 manual [pitfall]
BuildKit cache mounts for non-root USER must include uid/gid to avoid permission issues on parent directories

## 2026-01-16 manual [pitfall]
BuildKit cache mounts exclude content from final image layer - do not cache directories needed at runtime

## 2026-01-16 manual [pitfall]
Dynamic ARGs/LABELs (BUILD_DATE, VCS_REF) invalidate layer cache - place them at end of Dockerfile

## 2026-01-16 manual [pitfall]
Shell precedence: 'cmd1 && cmd2 || true' masks cmd1 failures; use 'cmd1 && (cmd2 || true)' to only mask cmd2

## 2026-01-18 manual [pitfall]
ln -sfn to directory paths needs rm -rf first if destination may exist as real directory (ln -sfn creates link INSIDE existing dir)

## 2026-01-19 manual [pitfall]
Git worktrees and submodules use .git file (not directory); use -e test instead of -d for git root detection

## 2026-01-19 manual [pitfall]
With set -e, capturing exit code via var=$(cmd); rc=$? is dead code - use if ! var=$(cmd); then for error handling

## 2026-01-19 manual [pitfall]
Tests checking env var/config precedence must clear external env vars (env -u) to be hermetic

## 2026-01-19 manual [pitfall]
grep -v with empty input fails under set -euo pipefail; use sed -e '/pattern/d' instead for filter pipelines

## 2026-01-19 manual [pitfall]
Functions returning non-zero for valid control flow (not just errors) need if/else guards for set -e: if func; then rc=0; else rc=$?; fi

## 2026-01-19 manual [pitfall]
Bash read command returns non-zero on EOF; guard with 'if ! read -r var; then' for set -e safety

## 2026-01-19 manual [pitfall]
base64 -w0 is not portable (BSD/macOS lacks -w flag); use 'base64 | tr -d \n' for cross-platform encoding

## 2026-01-19 manual [pitfall]
BASH_SOURCE check must come AFTER BASH_VERSION check - BASH_SOURCE is bash-only and fails in sh/dash

## 2026-01-19 manual [pitfall]
Use 'cd -- "$path"' not 'cd "$path"' - paths starting with - can be misinterpreted as cd options

## 2026-01-19 manual [pitfall]
When capturing function output to a variable, use stdout-only capture; mixing stderr with 2>&1 can pollute the value with warning messages

## 2026-01-20 manual [pitfall]
Systemd drop-in ExecStart= clears then replaces - extract existing command and APPEND flags to preserve distro/user settings

## 2026-01-20 manual [pitfall]
When validating runtime availability, check .Runtimes contains the runtime, don't assume DefaultRuntime - explicit --runtime flags are needed when runtime is NOT set as default

## 2026-01-20 manual [pitfall]
Docker sandbox commands require forcing default context (DOCKER_CONTEXT= DOCKER_HOST=) since they only work with Docker Desktop, not custom contexts

## 2026-01-20 manual [pitfall]
Verify by specific IDs not by attributes (workspace/name) to avoid false negatives from concurrent operations

## 2026-01-20 manual [pitfall]
When adding platform-specific code paths, update ALL downstream consumers (validation, doctor, tests) to handle the new platform's configuration

## 2026-01-20 manual [pitfall]
dockerd fails if hosts is set in both daemon.json and -H flag; specify in exactly one place

## 2026-01-20 manual [pitfall]
When removing legacy paths, update ALL tests that reference them, including full-sync directory checks

## 2026-01-20 manual [pitfall]
env -u only works with external commands, not shell functions; use DOCKER_CONTEXT= DOCKER_HOST= func_call for temporary env override

## 2026-01-20 manual [pitfall]
When preserving original variable for error message, save it BEFORE the assignment that may clobber it (workspace_input=workspace before cd fails)

## 2026-01-20 manual [pitfall]
When detecting multiline quoted values in env file parsing, check for ANY matching quote in the remainder of the line (not just at end) - values like FOO="bar" #comment are valid single-line

## 2026-01-20 manual [pitfall]
When overriding HOME for tests, preserve DOCKER_CONFIG pointing to real home to avoid breaking Docker CLI context

## 2026-01-20 manual [pitfall]
In bash -c wrappers, use "$@" with proper argument passing (bash -c 'cmd "$@"' _ arg1 arg2) not $* which loses argument boundaries


## 2026-01-22 manual [pitfall]
When checking if a path exists in a config file, use grep -qF with full path to avoid false positives from partial matches (e.g., ~/.local/bin matching /usr/local/bin)

## 2026-01-22 manual [pitfall]
When comparing git branches for ahead/behind commits, compare the named branch refs not HEAD - HEAD may be on a different branch

## 2026-01-22 manual [pitfall]
When removing a feature, search docs/ for references - architecture diagrams, decision docs, and quickstart guides often lag behind code changes

## 2026-01-22 manual [pitfall]
Inside containers, creating files/symlinks in host-style paths (e.g., /home/user/) requires root privileges - use sudo/run_as_root wrappers

## 2026-01-22 manual [pitfall]
Docker volume root is often root-owned; write as root then chown to target user instead of running container as non-root user

## 2026-01-22 manual [pitfall]
When writing config files, use native tools (git config -f, jq) instead of templating raw values to prevent injection via newlines/control characters

## 2026-01-22 manual [pitfall]
Docker volume .Source is host path (e.g., /var/lib/docker/volumes/name/_data), not volume name; use .Name field for named volume identification

## 2026-01-22 manual [pitfall]
When detecting user-editable config lines, use case-insensitive patterns that handle whitespace/path variants - exact matching fails for legitimate variations

## 2026-01-22 manual [pitfall]
During Docker build, systemctl mask/enable fail because systemd isn't PID 1; use symlinks to /dev/null (mask) or multi-user.target.wants (enable) instead

## 2026-01-22 manual [pitfall]
SSH host keys generated at docker build time are baked into the image - all containers share keys, creating MITM risk; delete at build, generate on first boot via systemd oneshot

## 2026-01-22 manual [pitfall]
Systemd services with User= don't set HOME env var - add Environment=HOME=/path or set default in script with : "${HOME:=/default}"

## 2026-01-22 manual [pitfall]
Systemd Wants= is advisory - unit starts even if wanted unit doesn't exist; use Requires= for hard dependencies

## 2026-01-22 manual [pitfall]
When using return codes to distinguish error types (e.g., 0=ok, 1=conflict, 2=cannot-check), callers must handle all codes explicitly to avoid wrong actions on tool unavailability

## 2026-01-23 manual [pitfall]
Dry-run simulations must mirror exact runtime logic (e.g., port allocation with ignore flags for running vs stopped containers)

## 2026-01-23 manual [pitfall]
Never use 'source' or 'eval' on .env files - use safe line-by-line KEY=VALUE parsing to prevent command injection

## 2026-01-23 manual [pitfall]
Alpine/BusyBox wget uses -T for timeout (not --timeout which is GNU wget only)

## 2026-01-23 manual [pitfall]
When using docker run --pull=never for reproducibility, pre-pull the image in prerequisites to avoid false failures on fresh systems

## 2026-01-23 manual [pitfall]
Security documentation should avoid absolute claims ('zero risk', 'completely inaccessible') - qualify with 'dramatically reduces', 'for most escapes', or note exceptions (kernel bugs, mounted volumes)

## 2026-01-23 manual [pitfall]
Nested markdown code fences (triple backticks inside triple backticks) cause rendering issues - use quadruple backticks for outer fence when documenting code containing fenced blocks

## 2026-01-23 manual [pitfall]
String prefix checks (case "$path" in "$prefix"*) don't prevent ../ path escapes - must explicitly reject paths containing /../ or /.. segments

## 2026-01-23 manual [pitfall]
POSIX sh case patterns with variable prefixes break if the variable has trailing slash - normalize paths by stripping trailing slash (except root) before pattern matching

## 2026-01-23 manual [pitfall]
When stripping trailing slash with ${var%/}, root path / becomes empty - use case statement to handle root specially

## 2026-01-23 manual [pitfall]
macOS lacks the timeout command by default - use a portable wrapper that checks command -v timeout or falls back to running without timeout

## 2026-01-24 manual [pitfall]
POSIX awk doesn't support /regex/i case-insensitive flag; use IGNORECASE=1 in BEGIN block instead

## 2026-01-25 manual [pitfall]
When sudo mv moves files from user-owned temp dir to root locations, ownership is preserved - must chown/chmod after to prevent privilege escalation

## 2026-01-25 manual [pitfall]
Version comparison must use semver logic (sort -V) not string equality - checking != instead of > causes false positives on downgrades

## 2026-01-25 manual [pitfall]
apt-get upgrade -y can still prompt (dpkg conffile/needrestart); use DEBIAN_FRONTEND=noninteractive and -o Dpkg::Options::=--force-confdef/confold for truly non-interactive updates

## 2026-01-25 manual [pitfall]
sudo VAR=value cmd does not pass VAR to cmd; use sudo env VAR=value cmd instead

## 2026-01-25 manual [pitfall]
ln -sfn creates symlinks INSIDE existing directories; always rm -rf target dir before ln -sfn for directory symlinks

## 2026-01-25 manual [pitfall]
Git config values can span multiple lines via trailing backslash - when filtering config entries, must track and skip continuation lines until a line without trailing backslash

## 2026-01-25 manual [pitfall]
trap RETURN fires on EVERY function return including nested calls - use explicit cleanup instead

## 2026-01-25 manual [pitfall]
test -e returns false for broken symlinks; use test -L to check if a symlink exists regardless of target validity

## 2026-01-25 manual [pitfall]
Relative path computation must use common-prefix algorithm (not just walk up to root) to get minimal paths between two absolute paths

## 2026-01-25 manual [pitfall]
User-provided paths in colon-delimited formats (src:dst:flags) must reject colons to prevent injection attacks

## 2026-01-25 manual [pitfall]
Bash -d and -f tests follow symlinks; check -L FIRST to detect symlinks before other file type tests

## 2026-01-26 manual [pitfall]
When function can fail for distinct reasons (not found vs multiple matches), use distinct exit codes so callers can respond appropriately

## 2026-01-26 manual [pitfall]
When using docker inspect to check container existence, always use --type container to avoid matching images with the same name

## 2026-01-26 manual [pitfall]
When passing user-controlled names to docker commands (stop/rm/inspect), always use -- to prevent option injection if name starts with dash

## 2026-01-26 manual [pitfall]
When using docker --context, also clear DOCKER_CONTEXT and DOCKER_HOST env vars to prevent override (use DOCKER_CONTEXT= DOCKER_HOST= prefix)

## 2026-01-26 manual [pitfall]
Piping to tee without 'set -o pipefail' masks upstream command failures - add pipefail or check PIPESTATUS

## 2026-01-26 manual [pitfall]
GitHub Actions upload-artifact preserves directory structure; download-artifact extracts to specified path with same structure - adjust consumer paths accordingly

## 2026-01-26 manual [pitfall]
Environment variables set inline (VAR=value cmd) only apply to the immediate command, not to subsequent commands in a pipeline; use 'export VAR=value;' for pipeline-wide scope

## 2026-01-26 manual [pitfall]
When managing Docker containers, use DOCKER_HOST directly with socket path instead of relying on docker context - contexts can be misconfigured and lead to operating on wrong engine

## 2026-01-27 manual [pitfall]
When embedding variables in bash -c scripts (e.g., limactl shell -- bash -c), pass them as positional parameters (bash -c 'script' _ "$var") to prevent command injection, not string interpolation

## 2026-01-27 manual [pitfall]
Docker Config.User can be a name (e.g., 'agent') not numeric UID - resolve via container exec before using in host chown
