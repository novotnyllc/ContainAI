#!/usr/bin/env bash
# Common functions for agent management scripts
set -euo pipefail

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

# Check if Docker is running
check_docker_running() {
    if ! docker info > /dev/null 2>&1; then
        echo "❌ Docker is not running!"
        echo "   Please start Docker and try again"
        return 1
    fi
    return 0
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
    
    if ! container_exists "$container_name"; then
        echo "❌ Container '$container_name' does not exist"
        return 1
    fi
    
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
