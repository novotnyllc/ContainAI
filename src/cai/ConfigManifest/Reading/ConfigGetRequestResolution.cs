namespace ContainAI.Cli.Host.ConfigManifest.Reading;

internal readonly record struct ConfigGetRequestResolution(
    string? NormalizedKey,
    string? Workspace,
    bool IsGlobal,
    string? Error = null)
{
    public bool ShouldReadWorkspace => !IsGlobal && !string.IsNullOrWhiteSpace(Workspace);

    public static ConfigGetRequestResolution Invalid(string error) =>
        new(null, null, IsGlobal: false, Error: error);
}
