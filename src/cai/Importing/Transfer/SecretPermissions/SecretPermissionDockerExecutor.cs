using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host.Importing.Transfer.SecretPermissions;

internal interface ISecretPermissionDockerExecutor
{
    Task<int> ExecuteAsync(string volume, string shellCommand, CancellationToken cancellationToken);
}

internal sealed class SecretPermissionDockerExecutor : ISecretPermissionDockerExecutor
{
    private readonly TextWriter stderr;

    public SecretPermissionDockerExecutor(TextWriter standardError)
        => stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<int> ExecuteAsync(string volume, string shellCommand, CancellationToken cancellationToken)
    {
        var result = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", shellCommand],
            cancellationToken).ConfigureAwait(false);

        if (result.ExitCode == 0)
        {
            return 0;
        }

        if (!string.IsNullOrWhiteSpace(result.StandardError))
        {
            await stderr.WriteLineAsync(result.StandardError.Trim()).ConfigureAwait(false);
        }

        return 1;
    }
}
