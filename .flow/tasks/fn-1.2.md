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
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
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

**Image Naming:** (implemented in fn-1.4 build.sh)
- Image: `dotnet-sandbox`
- Tags: `:latest` AND `:YYYY-MM-DD`

**Build approach:** Use separate RUN commands for maintainability; optimize layers later.
## Acceptance
- [x] Build fails with clear error if base image is not Ubuntu Noble (Dockerfile:15-21)
- [x] `dotnet --version | grep -E '^10\.'` verifies major version 10 (Dockerfile:49-50)
- [x] `dotnet workload list` shows `wasm-tools` (Dockerfile:58-61)
- [x] `pwsh --version` succeeds (Dockerfile:63-70)
- [x] `bash -lc "node --version"` outputs LTS version (Dockerfile:107)
- [x] `bash -lc "nvm --version"` works (Dockerfile:108)
- [x] `/usr/local/bin/node --version` works (symlink) (Dockerfile:103)
- [x] `bash -lc "tsc --version && eslint --version && prettier --version"` work (Dockerfile:109)
- [x] Container runs as `uid=1000(agent)` (Dockerfile:72-73, 130)
- [x] Claude credentials symlink exists: `/home/agent/.claude/.credentials.json` (Dockerfile:118-121)
- [x] EXPOSE 5000-5010 in Dockerfile (Dockerfile:123-124)
## Done summary
## Summary

Created complete Dockerfile for .NET 10 WASM Docker Sandbox with:

1. **Base image validation**: Fails fast if not Ubuntu Noble (checks VERSION_CODENAME)
2. **.NET SDK via dotnet-install.sh**: Uses build ARG `DOTNET_CHANNEL=lts` (default) with version 10 verification
3. **WASM workloads**: Installs `wasm-tools` and `wasm-tools-net9`
4. **PowerShell**: Installed via Microsoft's official repository method
5. **Node.js via nvm**: Installed as agent user with LTS version and global tools (typescript, eslint, prettier)
6. **System symlinks**: Node/npm/npx available at /usr/local/bin for non-interactive access
7. **Profile script**: /etc/profile.d/nvm.sh for login shells
8. **Claude credentials**: Symlink to /mnt/claude-data/.credentials.json
9. **Ports**: EXPOSE 5000-5010 for WASM app serving
10. **User**: Runs as agent (uid=1000)

All acceptance criteria from the spec are addressed in the Dockerfile structure.
## Evidence
- Commits: 403507b, 1a6b907
- Tests: Dockerfile syntax verified, All acceptance criteria addressed in Dockerfile structure
- PRs: