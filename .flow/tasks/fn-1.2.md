# fn-1.2 Create Dockerfile with .NET SDK and WASM workloads

## Description
Create Dockerfile for .NET development sandbox with:

**Base Image:**
- `docker/sandbox-templates:claude-code`
- Fail fast if not Ubuntu Noble (check `/etc/os-release` for `VERSION_CODENAME=noble`)

**.NET SDK Installation (via dotnet-install.sh, NOT apt):**
- Use dotnet-install.sh script from Microsoft
- Build ARGs: `DOTNET_CHANNEL=lts` (options: lts, sts, preview, or specific like "10.0")
- Install wasm-tools, wasm-tools-net9 workload
- **NO uno-check during build** (moved to fn-1.5 verification)

**PowerShell:**
- Install via Microsoft's recommended method

**Node.js (install as agent user):**
```dockerfile
# Install nvm and node AS AGENT USER
USER agent
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
    && . ~/.nvm/nvm.sh \
    && nvm install --lts \
    && nvm alias default lts/* \
    && npm install -g typescript eslint prettier

# Create system-wide symlinks for non-interactive access (as root)
USER root
RUN ln -sf /home/agent/.nvm/versions/node/$(ls /home/agent/.nvm/versions/node)/bin/node /usr/local/bin/node \
    && ln -sf /home/agent/.nvm/versions/node/$(ls /home/agent/.nvm/versions/node)/bin/npm /usr/local/bin/npm \
    && ln -sf /home/agent/.nvm/versions/node/$(ls /home/agent/.nvm/versions/node)/bin/npx /usr/local/bin/npx

# Create /etc/profile.d/nvm.sh for login shells
RUN echo 'export NVM_DIR="/home/agent/.nvm"' > /etc/profile.d/nvm.sh \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' >> /etc/profile.d/nvm.sh

USER agent
```

**Claude Credentials Symlink:**
```dockerfile
# Create credentials symlink (same workaround as claude/Dockerfile)
RUN mkdir -p /home/agent/.claude \
    && ln -s /mnt/claude-data/.credentials.json /home/agent/.claude/.credentials.json
```

**Ports:**
- `EXPOSE 5000-5010` for WASM app serving

**Image Naming:**
- Image: `dotnet-sandbox`
- Tags: `:latest` AND `:YYYY-MM-DD`

**Build approach:** Use separate RUN commands for maintainability; optimize layers later.
## Acceptance
- [ ] Build fails with clear error if base image is not Ubuntu Noble
- [ ] `dotnet --version | grep -E '^10\.'` verifies major version 10
- [ ] `dotnet workload list` shows `wasm-tools`
- [ ] `pwsh --version` succeeds
- [ ] `bash -lc "node --version"` outputs LTS version
- [ ] `bash -lc "nvm --version"` works
- [ ] `/usr/local/bin/node --version` works (symlink)
- [ ] `bash -lc "tsc --version && eslint --version && prettier --version"` work
- [ ] Container runs as `uid=1000(agent)`
- [ ] Claude credentials symlink exists: `/home/agent/.claude/.credentials.json`
- [ ] EXPOSE 5000-5010 in Dockerfile
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
