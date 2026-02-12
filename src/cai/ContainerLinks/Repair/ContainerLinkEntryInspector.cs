namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkEntryInspector(IContainerLinkCommandClient commandClient) : IContainerLinkEntryInspector
{
    public async Task<ContainerLinkEntryState> GetEntryStateAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        CancellationToken cancellationToken)
    {
        var isSymlink = await commandClient.TestInContainerAsync(containerName, "-L", entry.Link, cancellationToken).ConfigureAwait(false);
        if (isSymlink)
        {
            var readResult = await commandClient.ExecuteInContainerAsync(containerName, ["readlink", "--", entry.Link], cancellationToken).ConfigureAwait(false);
            if (readResult.ExitCode != 0)
            {
                return ContainerLinkEntryState.FromError($"Failed to read symlink target for {entry.Link}: {readResult.StandardError.Trim()}");
            }

            var currentTarget = readResult.StandardOutput.Trim();
            if (string.Equals(currentTarget, entry.Target, StringComparison.Ordinal))
            {
                var targetExists = await commandClient.TestInContainerAsync(containerName, "-e", entry.Link, cancellationToken).ConfigureAwait(false);
                return targetExists ? ContainerLinkEntryState.Ok() : ContainerLinkEntryState.Dangling();
            }

            return ContainerLinkEntryState.Wrong(currentTarget);
        }

        if (await commandClient.TestInContainerAsync(containerName, "-d", entry.Link, cancellationToken).ConfigureAwait(false))
        {
            return ContainerLinkEntryState.Directory();
        }

        if (await commandClient.TestInContainerAsync(containerName, "-f", entry.Link, cancellationToken).ConfigureAwait(false))
        {
            return ContainerLinkEntryState.File();
        }

        return ContainerLinkEntryState.Missing();
    }
}
