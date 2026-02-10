namespace ContainAI.Cli.Host;

internal static class DevcontainerFeaturePaths
{
    public const string DefaultDataVolume = "containai-data";
    public const string DefaultConfigPath = "/usr/local/share/containai/config.json";
    public const string DefaultLinkSpecPath = "/usr/local/lib/containai/link-spec.json";
    public const string DefaultDataDir = "/mnt/agent-data";
    public const string DefaultSshPidFile = "/var/run/sshd/containai-sshd.pid";
    public const string DefaultDockerPidFile = "/var/run/docker.pid";
    public const string DefaultDockerLogFile = "/var/log/containai-dockerd.log";

    public static IReadOnlySet<string> CredentialTargets { get; } = new HashSet<string>(StringComparer.Ordinal)
    {
        "/mnt/agent-data/config/gh/hosts.yml",
        "/mnt/agent-data/claude/credentials.json",
        "/mnt/agent-data/codex/config.toml",
        "/mnt/agent-data/codex/auth.json",
        "/mnt/agent-data/local/share/opencode/auth.json",
        "/mnt/agent-data/gemini/settings.json",
        "/mnt/agent-data/gemini/oauth_creds.json",
    };
}
