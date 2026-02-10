using System.Globalization;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerLinkRepairOperations
{
    public async Task<ContainerLinkOperationResult> WriteCheckedTimestampAsync(
        string containerName,
        string checkedAtFilePath,
        CancellationToken cancellationToken)
    {
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyyMMddHHmmss", CultureInfo.InvariantCulture);
        var write = await commandClient
            .ExecuteInContainerWithInputAsync(containerName, ["tee", checkedAtFilePath], timestamp + Environment.NewLine, cancellationToken)
            .ConfigureAwait(false);
        if (write.ExitCode != 0)
        {
            return ContainerLinkOperationResult.Fail(write.StandardError.Trim());
        }

        var chown = await commandClient.ExecuteInContainerAsync(containerName, ["chown", "1000:1000", checkedAtFilePath], cancellationToken).ConfigureAwait(false);
        if (chown.ExitCode != 0)
        {
            return ContainerLinkOperationResult.Fail(chown.StandardError.Trim());
        }

        return ContainerLinkOperationResult.Ok();
    }
}
