namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkRepairStats
{
    public int Ok { get; set; }

    public int Broken { get; set; }

    public int Missing { get; set; }

    public int Fixed { get; set; }

    public int Errors { get; set; }
}

internal readonly record struct ContainerLinkSpecReadResult(IReadOnlyList<ContainerLinkSpecEntry> Entries, string? Error)
{
    public static ContainerLinkSpecReadResult Ok(IReadOnlyList<ContainerLinkSpecEntry> entries) => new(entries, null);

    public static ContainerLinkSpecReadResult Fail(string error) => new(Array.Empty<ContainerLinkSpecEntry>(), error);
}

internal readonly record struct ContainerLinkEntryState(EntryStateKind Kind, string? CurrentTarget, string? Error)
{
    public static ContainerLinkEntryState Ok() => new(EntryStateKind.Ok, null, null);

    public static ContainerLinkEntryState Missing() => new(EntryStateKind.Missing, null, null);

    public static ContainerLinkEntryState Directory() => new(EntryStateKind.DirectoryConflict, null, null);

    public static ContainerLinkEntryState File() => new(EntryStateKind.FileConflict, null, null);

    public static ContainerLinkEntryState Dangling() => new(EntryStateKind.DanglingSymlink, null, null);

    public static ContainerLinkEntryState Wrong(string? currentTarget) => new(EntryStateKind.WrongTarget, currentTarget, null);

    public static ContainerLinkEntryState FromError(string message) => new(EntryStateKind.Error, null, message);
}

internal readonly record struct ContainerLinkOperationResult(bool Success, string? Error)
{
    public static ContainerLinkOperationResult Ok() => new(true, null);

    public static ContainerLinkOperationResult Fail(string error) => new(false, error);
}
