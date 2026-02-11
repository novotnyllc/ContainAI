namespace ContainAI.Cli.Host;

internal readonly record struct ImportManifestLoadResult(bool Success, ManifestEntry[]? Entries, string? ErrorMessage)
{
    public static ImportManifestLoadResult SuccessResult(ManifestEntry[] entries)
        => new(true, entries, null);

    public static ImportManifestLoadResult FailureResult(string errorMessage)
        => new(false, null, errorMessage);
}
