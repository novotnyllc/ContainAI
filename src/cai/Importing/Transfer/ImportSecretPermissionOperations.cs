using ContainAI.Cli.Host.Importing.Transfer.SecretPermissions;

namespace ContainAI.Cli.Host;

internal interface IImportSecretPermissionOperations
{
    Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> ApplyEntrySecretPermissionsAsync(
        string volume,
        string normalizedTarget,
        bool isDirectory,
        CancellationToken cancellationToken);
}

internal sealed class ImportSecretPermissionOperations : IImportSecretPermissionOperations
{
    private readonly TextWriter stdout;
    private readonly IImportSecretPathCollector secretPathCollector;
    private readonly ISecretPermissionCommandBuilder permissionCommandBuilder;
    private readonly ISecretPermissionDockerExecutor permissionDockerExecutor;

    public ImportSecretPermissionOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportSecretPathCollector(),
            new SecretPermissionCommandBuilder(),
            new SecretPermissionDockerExecutor(standardError))
    {
    }

    internal ImportSecretPermissionOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportSecretPathCollector importSecretPathCollector,
        ISecretPermissionCommandBuilder secretPermissionCommandBuilder,
        ISecretPermissionDockerExecutor secretPermissionDockerExecutor)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        (stdout, secretPathCollector, permissionCommandBuilder, permissionDockerExecutor) = (
            standardOutput,
            importSecretPathCollector ?? throw new ArgumentNullException(nameof(importSecretPathCollector)),
            secretPermissionCommandBuilder ?? throw new ArgumentNullException(nameof(secretPermissionCommandBuilder)),
            secretPermissionDockerExecutor ?? throw new ArgumentNullException(nameof(secretPermissionDockerExecutor)));
    }

    public async Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var secretPaths = secretPathCollector.Collect(manifestEntries, noSecrets);

        if (secretPaths.IsEmpty)
        {
            return 0;
        }

        var permissionsCommand = permissionCommandBuilder.BuildBulkPermissionsCommand(
            secretPaths.SecretDirectories,
            secretPaths.SecretFiles);
        var enforceCode = await permissionDockerExecutor.ExecuteAsync(
            volume,
            permissionsCommand,
            cancellationToken).ConfigureAwait(false);
        if (enforceCode != 0)
        {
            return 1;
        }

        if (verbose)
        {
            await stdout.WriteLineAsync("[INFO] Enforced secret path permissions").ConfigureAwait(false);
        }

        return 0;
    }

    public async Task<int> ApplyEntrySecretPermissionsAsync(
        string volume,
        string normalizedTarget,
        bool isDirectory,
        CancellationToken cancellationToken)
    {
        var chmodCommand = permissionCommandBuilder.BuildEntryPermissionsCommand(normalizedTarget, isDirectory);
        return await permissionDockerExecutor.ExecuteAsync(
            volume,
            chmodCommand,
            cancellationToken).ConfigureAwait(false);
    }
}
