# Implementation Plan: Unified Logging & Audit Shim

## Overview
Implement the "Unified Logging Architecture" defined in `docs/security/architecture.md`. This involves creating a central Log Collector (C# NativeAOT), a Userspace Audit Shim (Rust) for WSL2/fallback, and updating the Agent Task Runner (Rust) to stream events to the collector.

## Components

### 1. Shared Protocol
*   **Concept**: JSON-based protocol for audit events.
*   **Rust Side**: `docker/runtime/audit-protocol` (Crate) - Shared types for Shim and Runner.
*   **C# Side**: `docker/runtime/log-collector/Models` - Equivalent DTOs for the Collector.
*   **Structure**:
    ```json
    {
      "timestamp": "2025-12-01T12:00:00Z",
      "source": "Shim|Runner",
      "event_type": "Exec|Connect|Open|Deny",
      "metadata": { "session_id": "...", "agent": "..." },
      "payload": { ... }
    }
    ```

### 2. Log Collector (`log-collector`)
*   **Location**: `docker/runtime/log-collector` (New C# Project)
*   **Type**: .NET 10 Console App (NativeAOT)
*   **Responsibilities**:
    *   Bind Unix Domain Socket: `/run/containai/audit.sock`
    *   Listen for incoming connections.
    *   Aggregate events from multiple sources.
    *   Write structured logs to `/mnt/logs/session-<id>.jsonl`.
*   **Build**: `dotnet publish -r linux-x64 /p:PublishAot=true`
*   **Dependencies**: `System.Net.Sockets`, `System.Text.Json`.

### 3. Audit Shim (`audit-shim`)
*   **Location**: `docker/base/audit-shim` (New Rust Crate)
*   **Type**: Rust `cdylib`
*   **Responsibilities**:
    *   Export `LD_PRELOAD` hooks for `execve`, `execveat`, `connect`, `open`, `openat`.
    *   Capture arguments and environment.
    *   Connect to `/run/containai/audit.sock` and send JSON events.
    *   **Safety**: Handle recursion and signal safety.
*   **Dependencies**: `libc`, `serde`, `audit-protocol`.

### 4. Agent Task Runner Update (`agent-task-runner`)
*   **Modification**: Update `agent-task-runnerd` (Rust) to stream events to `/run/containai/audit.sock`.
*   **Modification**: Update `agentcli_exec.rs` (Rust) to:
    *   Detect WSL2/Seccomp failure.
    *   Set `LD_PRELOAD=/usr/lib/libauditshim.so`.

### 5. Build & Integration
*   **Workspace**: Convert `docker/runtime` to a Cargo Workspace for the Rust components.
*   **Dockerfile**:
    *   **Build Stage (Rust)**: Build `audit-shim` and `agent-task-runner`.
    *   **Build Stage (.NET)**: Build `log-collector` (NativeAOT).
    *   **Runtime**: Copy artifacts (`libauditshim.so`, `log-collector`, `agent-task-runnerd`) to final image.
    *   **Setup**: Ensure `/run/containai` exists.

## Execution Steps

1.  **Scaffold Projects**:
    *   Create Cargo Workspace for `audit-shim` and `audit-protocol`.
    *   Create C# Project for `log-collector`.
2.  **Implement Protocol**: Define JSON schema in Rust and C# DTOs.
3.  **Implement Log Collector (C#)**: Socket listener and file writer.
4.  **Implement Audit Shim (Rust)**: `execve` hook.
5.  **Update Runner (Rust)**: Wire up socket logging.
6.  **Update Launcher**: Inject shim on WSL2.
7.  **Integration Test**: Verify end-to-end flow.

## Future Roadmap
*   **Shell Script Migration**: Begin replacing complex shell scripts (e.g., `entrypoint.sh`, `setup-mcp-configs.sh`) with C# NativeAOT binaries for better maintainability and testability.

## Testing Plan
*   **Unit**: Serialization tests in `audit-protocol` and C# Models.
*   **Integration**:
    *   Test 1: Start collector, write to socket, verify file.
    *   Test 2: `LD_PRELOAD` shim, run `ls`, verify `exec` event in log.
    *   Test 3: Full container launch, verify `agent-task-runner` events in log.
