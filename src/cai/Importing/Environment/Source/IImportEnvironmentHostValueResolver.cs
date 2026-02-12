namespace ContainAI.Cli.Host.Importing.Environment.Source;

internal interface IImportEnvironmentHostValueResolver
{
    Task<Dictionary<string, string>> ResolveAsync(
        IReadOnlyList<string> validatedKeys,
        CancellationToken cancellationToken);
}
