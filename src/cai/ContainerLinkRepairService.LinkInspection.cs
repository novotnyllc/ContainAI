namespace ContainAI.Cli.Host;

internal sealed partial class ContainerLinkRepairService
{
    private async Task<EntryState> GetEntryStateAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        CancellationToken cancellationToken)
    {
        var isSymlink = await ExecTestAsync(containerName, "-L", entry.Link, cancellationToken).ConfigureAwait(false);
        if (isSymlink)
        {
            var readResult = await ExecAsync(containerName, ["readlink", "--", entry.Link], cancellationToken).ConfigureAwait(false);
            if (readResult.ExitCode != 0)
            {
                return EntryState.FromError($"Failed to read symlink target for {entry.Link}: {readResult.StandardError.Trim()}");
            }

            var currentTarget = readResult.StandardOutput.Trim();
            if (string.Equals(currentTarget, entry.Target, StringComparison.Ordinal))
            {
                var targetExists = await ExecTestAsync(containerName, "-e", entry.Link, cancellationToken).ConfigureAwait(false);
                return targetExists ? EntryState.Ok() : EntryState.Dangling();
            }

            return EntryState.Wrong(currentTarget);
        }

        if (await ExecTestAsync(containerName, "-d", entry.Link, cancellationToken).ConfigureAwait(false))
        {
            return EntryState.Directory();
        }

        if (await ExecTestAsync(containerName, "-f", entry.Link, cancellationToken).ConfigureAwait(false))
        {
            return EntryState.File();
        }

        return EntryState.Missing();
    }

    private async Task<bool> ExecTestAsync(
        string containerName,
        string testOption,
        string path,
        CancellationToken cancellationToken)
    {
        var result = await ExecAsync(containerName, ["test", testOption, "--", path], cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    private Task<CommandExecutionResult> ExecAsync(
        string containerName,
        IReadOnlyList<string> command,
        CancellationToken cancellationToken)
    {
        var args = new List<string>(command.Count + 2)
        {
            "exec",
            containerName,
        };
        args.AddRange(command);
        return executeDocker(args, null, cancellationToken);
    }

    private readonly record struct EntryState(EntryStateKind Kind, string? CurrentTarget, string? Error)
    {
        public static EntryState Ok() => new(EntryStateKind.Ok, null, null);
        public static EntryState Missing() => new(EntryStateKind.Missing, null, null);
        public static EntryState Directory() => new(EntryStateKind.DirectoryConflict, null, null);
        public static EntryState File() => new(EntryStateKind.FileConflict, null, null);
        public static EntryState Dangling() => new(EntryStateKind.DanglingSymlink, null, null);
        public static EntryState Wrong(string? currentTarget) => new(EntryStateKind.WrongTarget, currentTarget, null);
        public static EntryState FromError(string message) => new(EntryStateKind.Error, null, message);
    }
}
