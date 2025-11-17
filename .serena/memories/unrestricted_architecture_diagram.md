# Hardened Architecture Diagram (Mermaid)

```mermaid
flowchart LR
    subgraph Host
        repo[(Source Repo)]
        auth[(OAuth Broker + Secrets)]
        proxylogs[(Proxy Logs)]
        ctrl[(Launcher + Kill Switch)]
    end

    subgraph Container
        direction TB
        sandbox[(agentuser namespace\ncap-drop=ALL\nseccomp+AppArmor)]
        workspace[/ /workspace (git snapshot) /]
        safeSh[[safe_sh wrapper]]
        safeNet[[safe_net proxy client]]
        mcp[(MCP Servers)]
    end

    subgraph ProxyNet
        squid[[Squid/Egress Proxy]]
    end

    repo -->|copy (ro) | sandbox
    auth -->|scoped tokens| sandbox
    ctrl -->|docker run| sandbox
    sandbox --> workspace
    safeSh --> workspace
    workspace --> mcp
    sandbox -->|HTTP(S) via safe_net| squid -->|filtered domains| Internet[(Allowed Domains)]
    squid --> proxylogs
    sandbox -->|git push local| repo
    ctrl <-->|kill switch| sandbox
```
