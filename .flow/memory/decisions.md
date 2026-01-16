# Decisions

Architectural choices with rationale. Why we chose X over Y.

<!-- Entries added manually via `flowctl memory add` -->

## 2026-01-16 manual [decision]
sdk-manifests NOT cache-mounted: cache mounts exclude content from final image, breaking dotnet workloads at runtime
