namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportPostCopyOperations
{
    private readonly IImportSecretPermissionOperations secretPermissionOperations;
    private readonly IImportGitConfigFilterOperations gitConfigFilterOperations;

    public CaiImportPostCopyOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportSecretPermissionOperations(standardOutput, standardError),
            new ImportGitConfigFilterOperations(standardOutput, standardError))
    {
    }

    internal CaiImportPostCopyOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportSecretPermissionOperations importSecretPermissionOperations,
        IImportGitConfigFilterOperations importGitConfigFilterOperations)
        : base(standardOutput, standardError)
        => (secretPermissionOperations, gitConfigFilterOperations) = (
            importSecretPermissionOperations ?? throw new ArgumentNullException(nameof(importSecretPermissionOperations)),
            importGitConfigFilterOperations ?? throw new ArgumentNullException(nameof(importGitConfigFilterOperations)));
}
