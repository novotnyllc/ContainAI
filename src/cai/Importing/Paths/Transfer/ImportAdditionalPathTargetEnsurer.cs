using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathTargetEnsurer
{
    Task<int> EnsureAsync(
        string volume,
        ImportAdditionalPath additionalPath,
        CancellationToken cancellationToken);
}

internal sealed class ImportAdditionalPathTargetEnsurer : IImportAdditionalPathTargetEnsurer
{
    private readonly TextWriter standardError;

    public ImportAdditionalPathTargetEnsurer(TextWriter standardError)
        => this.standardError = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<int> EnsureAsync(
        string volume,
        ImportAdditionalPath additionalPath,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(volume);

        var ensureCommand = additionalPath.IsDirectory
            ? $"mkdir -p '/target/{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(additionalPath.TargetPath)}'"
            : $"mkdir -p \"$(dirname '/target/{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(additionalPath.TargetPath)}')\"";

        var ensureResult = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", ensureCommand],
            cancellationToken).ConfigureAwait(false);

        if (ensureResult.ExitCode == 0)
        {
            return 0;
        }

        if (!string.IsNullOrWhiteSpace(ensureResult.StandardError))
        {
            await standardError.WriteLineAsync(ensureResult.StandardError.Trim()).ConfigureAwait(false);
        }

        return 1;
    }
}
