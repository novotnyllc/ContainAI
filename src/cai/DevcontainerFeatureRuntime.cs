using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private const string DefaultDataVolume = "containai-data";
    private const string DefaultConfigPath = "/usr/local/share/containai/config.json";
    private const string DefaultLinkSpecPath = "/usr/local/lib/containai/link-spec.json";
    private const string DefaultDataDir = "/mnt/agent-data";
    private const string DefaultSshPidFile = "/var/run/sshd/containai-sshd.pid";
    private const string DefaultDockerPidFile = "/var/run/docker.pid";
    private const string DefaultDockerLogFile = "/var/log/containai-dockerd.log";


    private static readonly HashSet<string> CredentialTargets = new(StringComparer.Ordinal)
    {
        "/mnt/agent-data/config/gh/hosts.yml",
        "/mnt/agent-data/claude/credentials.json",
        "/mnt/agent-data/codex/config.toml",
        "/mnt/agent-data/codex/auth.json",
        "/mnt/agent-data/local/share/opencode/auth.json",
        "/mnt/agent-data/gemini/settings.json",
        "/mnt/agent-data/gemini/oauth_creds.json",
    };

    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly DevcontainerFeatureConfigService configService;
    private readonly DevcontainerProcessHelpers processHelpers;
    private readonly DevcontainerUserEnvironmentSetup userEnvironmentSetup;
    private readonly DevcontainerServiceBootstrap serviceBootstrap;

    public DevcontainerFeatureRuntime(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput;
        stderr = standardError;
        configService = new DevcontainerFeatureConfigService();
        processHelpers = new DevcontainerProcessHelpers();
        userEnvironmentSetup = new DevcontainerUserEnvironmentSetup(processHelpers, stdout);
        serviceBootstrap = new DevcontainerServiceBootstrap(processHelpers, stdout, stderr);
    }
}
