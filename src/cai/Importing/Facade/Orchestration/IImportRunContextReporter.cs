namespace ContainAI.Cli.Host;

internal interface IImportRunContextReporter
{
    Task WriteContextAsync(ImportRunContext context, bool dryRun);

    Task WriteRunContextErrorAsync(string error);

    Task WriteManifestLoadErrorAsync(string error);
}
