namespace ContainAI.Cli.Host;

internal sealed partial class ContainerLinkRepairOperations
{
    public async Task<ContainerLinkOperationResult> RepairEntryAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        ContainerLinkEntryState state,
        CancellationToken cancellationToken)
    {
        var parent = Path.GetDirectoryName(entry.Link);
        if (!string.IsNullOrWhiteSpace(parent))
        {
            var mkdir = await commandClient.ExecuteInContainerAsync(containerName, ["mkdir", "-p", parent], cancellationToken).ConfigureAwait(false);
            if (mkdir.ExitCode != 0)
            {
                return ContainerLinkOperationResult.Fail($"Failed to create parent directory '{parent}': {mkdir.StandardError.Trim()}");
            }
        }

        if (state.Kind is not EntryStateKind.Missing)
        {
            if (state.Kind == EntryStateKind.DirectoryConflict && !entry.RemoveFirst)
            {
                return ContainerLinkOperationResult.Fail($"Cannot fix - directory exists without R flag: {entry.Link}");
            }

            var remove = await commandClient.ExecuteInContainerAsync(containerName, ["rm", "-rf", "--", entry.Link], cancellationToken).ConfigureAwait(false);
            if (remove.ExitCode != 0)
            {
                return ContainerLinkOperationResult.Fail($"Failed to remove '{entry.Link}': {remove.StandardError.Trim()}");
            }
        }

        var link = await commandClient.ExecuteInContainerAsync(containerName, ["ln", "-sfn", "--", entry.Target, entry.Link], cancellationToken).ConfigureAwait(false);
        if (link.ExitCode != 0)
        {
            return ContainerLinkOperationResult.Fail($"Failed to create symlink '{entry.Link}' -> '{entry.Target}': {link.StandardError.Trim()}");
        }

        return ContainerLinkOperationResult.Ok();
    }
}
