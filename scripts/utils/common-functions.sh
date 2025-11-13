#!/usr/bin/env bash
# Common functions for agent management scripts
set -euo pipefail

# Detect container runtime (docker or podman)
get_container_runtime() {
    # Check for CONTAINER_RUNTIME environment variable first
    if [ -n "${CONTAINER_RUNTIME:-}" ]; then
        if command -v "$CONTAINER_RUNTIME" &> /dev/null; then
            echo "$CONTAINER_RUNTIME"
            return 0
        fi
    fi
    
    # Auto-detect: prefer docker, fall back to podman
    if command -v docker &> /dev/null && docker info > /dev/null 2>&1; then
        echo "docker"
        return 0
    elif command -v podman &> /dev/null && podman info > /dev/null 2>&1; then
        echo "podman"
        return 0
    fi
    
    # Check if either exists but not running
    if command -v docker &> /dev/null; then
        echo "docker"
        return 0
    elif command -v podman &> /dev/null; then
        echo "podman"
        return 0
    fi
    
    # Neither found
    return 1
}

# Validate container name
validate_container_name() {
    local name="$1"
    # Container names must match: [a-zA-Z0-9][a-zA-Z0-9_.-]*
    if [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        return 0
    fi
    return 1
}

# Validate branch name
validate_branch_name() {
    local branch="$1"
    # Basic git branch name validation
    if [[ "$branch" =~ ^[a-zA-Z0-9][a-zA-Z0-9/_.-]*$ ]] && [[ ! "$branch" =~ \.\. ]] && [[ ! "$branch" =~ /$ ]]; then
        return 0
    fi
    return 1
}

# Validate image name
validate_image_name() {
    local image="$1"
    # Docker image name validation
    if [[ "$image" =~ ^[a-z0-9]+(([._-]|__)[a-z0-9]+)*(:[a-zA-Z0-9_.-]+)?$ ]]; then
        return 0
    fi
    return 1
}

# Sanitize branch name for use in container names
sanitize_branch_name() {
    local branch="$1"
    local sanitized
    
    # Replace slashes with dashes
    sanitized="${branch//\//-}"
    sanitized="${sanitized//\\/-}"
    
    # Replace any other invalid characters with dashes
    sanitized=$(echo "$sanitized" | sed 's/[^a-zA-Z0-9._-]/-/g')
    
    # Collapse multiple dashes
    sanitized=$(echo "$sanitized" | sed 's/-\+/-/g')
    
    # Remove leading special characters
    sanitized=$(echo "$sanitized" | sed 's/^[._-]\+//')
    
    # Remove trailing special characters
    sanitized=$(echo "$sanitized" | sed 's/[._-]\+$//')
    
    # Convert to lowercase
    sanitized=$(echo "$sanitized" | tr '[:upper:]' '[:lower:]')
    
    # Ensure non-empty result
    if [ -z "$sanitized" ]; then
        sanitized="branch"
    fi
    
    echo "$sanitized"
}

# Check if git branch exists in repository
branch_exists() {
    local repo_path="$1"
    local branch_name="$2"
    
    (cd "$repo_path" && git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null)
    return $?
}

# Get unmerged commits between branches
get_unmerged_commits() {
    local repo_path="$1"
    local base_branch="$2"
    local compare_branch="$3"
    
    (cd "$repo_path" && git log "$base_branch..$compare_branch" --oneline 2>/dev/null)
}

# Remove git branch
remove_git_branch() {
    local repo_path="$1"
    local branch_name="$2"
    local force="${3:-false}"
    
    local flag="-d"
    if [ "$force" = "true" ]; then
        flag="-D"
    fi
    
    (cd "$repo_path" && git branch "$flag" "$branch_name" 2>/dev/null)
    return $?
}

# Rename git branch
rename_git_branch() {
    local repo_path="$1"
    local old_name="$2"
    local new_name="$3"
    
    (cd "$repo_path" && git branch -m "$old_name" "$new_name" 2>/dev/null)
    return $?
}

# Create new git branch
create_git_branch() {
    local repo_path="$1"
    local branch_name="$2"
    local start_point="${3:-HEAD}"
    
    (cd "$repo_path" && git branch "$branch_name" "$start_point" 2>/dev/null)
    return $?
}

# Get repository name from path
get_repo_name() {
    local repo_path="$1"
    basename "$repo_path"
}

# Get current git branch
get_current_branch() {
    local repo_path="$1"
    cd "$repo_path" && git branch --show-current 2>/dev/null || echo "main"
}

# Convert Windows path to WSL path
convert_to_wsl_path() {
    local path="$1"
    if [[ "$path" =~ ^[A-Z]: ]]; then
        local drive=$(echo "$path" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
        local rest=$(echo "$path" | cut -d: -f2 | tr '\\' '/')
        echo "/mnt/${drive}${rest}"
    else
        echo "$path"
    fi
}

# Check if container runtime (Docker/Podman) is running
check_docker_running() {
    local runtime
    runtime=$(get_container_runtime 2>/dev/null || echo "")
    
    if [ -n "$runtime" ]; then
        # Check if runtime is running
        if $runtime info > /dev/null 2>&1; then
            return 0
        fi
    fi
    
    echo "⚠️  Container runtime not running. Checking installation..."
    
    # Try docker first
    if command -v docker &> /dev/null; then
        runtime="docker"
    elif command -v podman &> /dev/null; then
        runtime="podman"
        echo "ℹ️  Using Podman as container runtime"
        
        # Podman doesn't need a daemon on Linux
        if podman info > /dev/null 2>&1; then
            return 0
        fi
        
        echo "❌ Podman is installed but not working properly"
        echo "   Try: podman system reset"
        return 1
    else
        echo "❌ No container runtime found. Please install one:"
        echo "   Docker: https://www.docker.com/products/docker-desktop"
        echo "   Podman: https://podman.io/getting-started/installation"
        return 1
    fi
    
    # Check if we're on WSL and can access Docker Desktop
    if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "🔍 Detected WSL environment. Checking Docker Desktop..."
        
        # Try to start Docker Desktop via Windows
        if command -v powershell.exe &> /dev/null; then
            local docker_desktop_path="/mnt/c/Program Files/Docker/Docker/Docker Desktop.exe"
            
            if [ -f "$docker_desktop_path" ]; then
                echo "🚀 Starting Docker Desktop..."
                powershell.exe -Command "Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'" 2>/dev/null || true
                
                # Wait for Docker to start (max 60 seconds)
                local max_wait=60
                local waited=0
                while [ $waited -lt $max_wait ]; do
                    sleep 2
                    waited=$((waited + 2))
                    if docker info > /dev/null 2>&1; then
                        echo "✅ Docker started successfully"
                        return 0
                    fi
                    echo "  Waiting for Docker... ($waited/$max_wait seconds)"
                done
                
                echo "❌ Docker failed to start within $max_wait seconds"
                echo "   Please start Docker Desktop manually and try again"
                return 1
            fi
        fi
    fi
    
    # On Linux, check if docker service can be started
    if [ -f /etc/init.d/docker ] || systemctl list-unit-files docker.service &> /dev/null; then
        echo "💡 Docker service is installed but not running."
        echo "   Try starting it with: sudo systemctl start docker"
        echo "   Or: sudo service docker start"
        return 1
    fi
    
    echo "❌ Docker is installed but not running."
    echo "   Please start Docker and try again"
    return 1
}

# Pull and tag image with retry logic
pull_and_tag_image() {
    local agent="$1"
    local max_retries="${2:-3}"
    local retry_delay="${3:-2}"
    local registry_image="ghcr.io/novotnyllc/coding-agents-${agent}:latest"
    local local_image="coding-agents-${agent}:local"
    
    echo "📦 Checking for image updates..."
    
    local attempt=0
    local pulled=false
    
    while [ $attempt -lt $max_retries ] && [ "$pulled" = "false" ]; do
        attempt=$((attempt + 1))
        
        if [ $attempt -gt 1 ]; then
            echo "  ⚠️  Retry attempt $attempt of $max_retries..."
        fi
        
        if docker pull --quiet "$registry_image" 2>/dev/null; then
            docker tag "$registry_image" "$local_image" 2>/dev/null || true
            pulled=true
        else
            if [ $attempt -lt $max_retries ]; then
                sleep $retry_delay
            fi
        fi
    done
    
    if [ "$pulled" = "false" ]; then
        echo "  ⚠️  Warning: Could not pull latest image, using cached version"
    fi
}

# Check if container exists
container_exists() {
    local container_name="$1"
    docker ps -a --filter "name=^${container_name}$" --format "{{.Names}}" 2>/dev/null | grep -q "^${container_name}$"
}

# Get container status
get_container_status() {
    local container_name="$1"
    docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "not-found"
}

# Push changes to local remote
push_to_local() {
    local container_name="$1"
    local skip_push="${2:-false}"
    
    if [ "$skip_push" = "true" ]; then
        echo "⏭️  Skipping git push (--no-push specified)"
        return 0
    fi
    
    echo "💾 Pushing changes to local remote..."
    docker exec "$container_name" bash -c '
        cd /workspace
        if [ -n "$(git status --porcelain)" ]; then
            echo "📝 Uncommitted changes detected"
            read -p "Commit changes before push? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                read -p "Commit message: " msg
                git add -A
                git commit -m "$msg"
            fi
        fi
        
        if git push 2>&1; then
            echo "✅ Changes pushed to local remote"
        else
            echo "⚠️  Failed to push (may be up to date)"
        fi
    ' 2>/dev/null || echo "⚠️  Could not push changes"
}

# List all agent containers
list_agent_containers() {
    docker ps -a --filter "label=coding-agents.type=agent" \
        --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.CreatedAt}}"
}

# Get proxy container name for agent
get_proxy_container() {
    local agent_container="$1"
    docker inspect -f '{{ index .Config.Labels "coding-agents.proxy-container" }}' "$agent_container" 2>/dev/null
}

# Get proxy network name for agent
get_proxy_network() {
    local agent_container="$1"
    docker inspect -f '{{ index .Config.Labels "coding-agents.proxy-network" }}' "$agent_container" 2>/dev/null
}

# Remove container and associated resources
remove_container_with_sidecars() {
    local container_name="$1"
    local skip_push="${2:-false}"
    local keep_branch="${3:-false}"
    
    if ! container_exists "$container_name"; then
        echo "❌ Container '$container_name' does not exist"
        return 1
    fi
    
    # Get container labels to find repo and branch info
    local agent_branch=$(docker inspect -f '{{ index .Config.Labels "coding-agents.branch" }}' "$container_name" 2>/dev/null || true)
    local repo_path=$(docker inspect -f '{{ index .Config.Labels "coding-agents.repo-path" }}' "$container_name" 2>/dev/null || true)
    
    # Push changes first
    if [ "$(get_container_status "$container_name")" = "running" ]; then
        push_to_local "$container_name" "$skip_push"
    fi
    
    # Get associated resources
    local proxy_container=$(get_proxy_container "$container_name")
    local proxy_network=$(get_proxy_network "$container_name")
    
    # Remove main container
    echo "🗑️  Removing container: $container_name"
    docker rm -f "$container_name" 2>/dev/null || true
    
    # Remove proxy if exists
    if [ -n "$proxy_container" ] && container_exists "$proxy_container"; then
        echo "🗑️  Removing proxy: $proxy_container"
        docker rm -f "$proxy_container" 2>/dev/null || true
    fi
    
    # Remove network if exists and no containers attached
    if [ -n "$proxy_network" ]; then
        local attached=$(docker network inspect -f '{{range .Containers}}{{.Name}} {{end}}' "$proxy_network" 2>/dev/null)
        if [ -z "$attached" ]; then
            echo "🗑️  Removing network: $proxy_network"
            docker network rm "$proxy_network" 2>/dev/null || true
        fi
    fi
    
    # Clean up agent branch in host repo if applicable
    if [ "$keep_branch" != "true" ] && [ -n "$agent_branch" ] && [ -n "$repo_path" ] && [ -d "$repo_path" ]; then
        echo ""
        echo "🌿 Cleaning up agent branch: $agent_branch"
        
        if branch_exists "$repo_path" "$agent_branch"; then
            # Check if branch has unpushed work
            local current_branch
            current_branch=$(cd "$repo_path" && git branch --show-current 2>/dev/null)
            local unmerged_commits
            unmerged_commits=$(get_unmerged_commits "$repo_path" "$current_branch" "$agent_branch")
            
            if [ -n "$unmerged_commits" ]; then
                echo "   ⚠️  Branch has unmerged commits - keeping branch"
                echo "   Manually merge or delete: git branch -D $agent_branch"
            else
                if remove_git_branch "$repo_path" "$agent_branch" "true"; then
                    echo "   ✅ Agent branch removed"
                else
                    echo "   ⚠️  Could not remove agent branch"
                fi
            fi
        fi
    fi
    
    echo ""
    echo "✅ Cleanup complete"
}

# Ensure squid proxy is running (for launch-agent)
ensure_squid_proxy() {
    local network_name="$1"
    local proxy_container="$2"
    local proxy_image="$3"
    local agent_container="$4"
    local squid_allowed_domains="${5:-*.github.com,*.githubcopilot.com,*.nuget.org}"
    
    # Create network if needed
    if ! docker network inspect "$network_name" >/dev/null 2>&1; then
        docker network create "$network_name" >/dev/null
    fi
    
    # Check if proxy exists
    if container_exists "$proxy_container"; then
        local state=$(get_container_status "$proxy_container")
        if [ "$state" != "running" ]; then
            docker start "$proxy_container" >/dev/null
        fi
    else
        # Create new proxy
        docker run -d \
            --name "$proxy_container" \
            --hostname "$proxy_container" \
            --network "$network_name" \
            --restart unless-stopped \
            -e "SQUID_ALLOWED_DOMAINS=$squid_allowed_domains" \
            --label "coding-agents.proxy-of=$agent_container" \
            --label "coding-agents.proxy-image=$proxy_image" \
            "$proxy_image" >/dev/null
    fi
}

# Generate repository setup script for container
generate_repo_setup_script() {
    local source_type="$1"
    local git_url="$2"
    local wsl_path="$3"
    local origin_url="$4"
    local agent_branch="$5"
    
    cat << 'SETUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="/workspace"
mkdir -p "$TARGET_DIR"

# Clean target directory
if [ -d "$TARGET_DIR" ] && [ "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
    find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

if [ "$SOURCE_TYPE" = "url" ]; then
    echo "🌐 Cloning repository from $GIT_URL..."
    git clone "$GIT_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
    if [ -n "$ORIGIN_URL" ]; then
        git remote set-url origin "$ORIGIN_URL"
    fi
else
    echo "📁 Copying repository from host..."
    cp -a /tmp/source-repo/. "$TARGET_DIR/"
    cd "$TARGET_DIR"
    
    # Configure local remote
    if [ -n "$LOCAL_REPO_PATH" ]; then
        if ! git remote get-url local >/dev/null 2>&1; then
            git remote add local "$LOCAL_REPO_PATH"
        fi
        git config remote.pushDefault local
    fi
fi

# Create and checkout branch
if [ -n "$AGENT_BRANCH" ]; then
    BRANCH_NAME="$AGENT_BRANCH"
    if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
        git checkout -b "$BRANCH_NAME"
    else
        git checkout "$BRANCH_NAME"
    fi
fi

echo "✅ Repository setup complete"
SETUP_SCRIPT
}
