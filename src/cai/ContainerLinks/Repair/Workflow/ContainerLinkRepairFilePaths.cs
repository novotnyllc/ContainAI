namespace ContainAI.Cli.Host;

internal static class ContainerLinkRepairFilePaths
{
    public const string BuiltinSpecPath = "/usr/local/lib/containai/link-spec.json";

    public const string UserSpecPath = "/mnt/agent-data/containai/user-link-spec.json";

    public const string CheckedAtFilePath = "/mnt/agent-data/.containai-links-checked-at";
}
