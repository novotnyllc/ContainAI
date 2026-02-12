namespace ContainAI.Cli.Host.Sessions.Models;

internal static class SessionRuntimeConstants
{
    public const string DefaultVolume = "containai-data";
    public const string DefaultImageTag = "latest";
    public const string ContainAiRepo = "containai";
    public const string ManagedLabelKey = "containai.managed";
    public const string ManagedLabelValue = "true";
    public const string WorkspaceLabelKey = "containai.workspace";
    public const string DataVolumeLabelKey = "containai.data-volume";
    public const string SshPortLabelKey = "containai.ssh-port";
    public const string SshHost = "127.0.0.1";
    public const int SshPortRangeStart = 2300;
    public const int SshPortRangeEnd = 2500;

    public static readonly string[] ContextFallbackOrder =
    [
        "containai-docker",
        "containai-secure",
        "docker-containai",
    ];

    public static readonly string[] ContainAiImagePrefixes =
    [
        "containai:",
        "ghcr.io/containai/",
        "ghcr.io/novotnyllc/containai",
    ];
}
