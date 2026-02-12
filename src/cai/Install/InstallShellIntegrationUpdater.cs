namespace ContainAI.Cli.Host;

internal sealed class InstallShellIntegrationUpdater : IInstallShellIntegrationUpdater
{
    private readonly IInstallPathResolver pathResolver;
    private readonly IShellProfileIntegration shellProfileIntegration;
    private readonly IInstallCommandOutput output;

    public InstallShellIntegrationUpdater(
        IInstallPathResolver pathResolver,
        IShellProfileIntegration shellProfileIntegration,
        IInstallCommandOutput output)
    {
        this.pathResolver = pathResolver ?? throw new ArgumentNullException(nameof(pathResolver));
        this.shellProfileIntegration = shellProfileIntegration ?? throw new ArgumentNullException(nameof(shellProfileIntegration));
        this.output = output ?? throw new ArgumentNullException(nameof(output));
    }

    public async Task EnsureShellIntegrationAsync(
        string binDir,
        string homeDirectory,
        bool autoUpdateShellConfig,
        CancellationToken cancellationToken)
    {
        if (!autoUpdateShellConfig)
        {
            await output.WriteWarningAsync(
                $"Shell integration not updated. Rerun with --yes to wire PATH/completions for `{binDir}`.",
                cancellationToken).ConfigureAwait(false);
            return;
        }

        var profileScriptUpdated = await shellProfileIntegration
            .EnsureProfileScriptAsync(homeDirectory, binDir, cancellationToken)
            .ConfigureAwait(false);
        var shellProfilePath = shellProfileIntegration.ResolvePreferredShellProfilePath(
            homeDirectory,
            pathResolver.GetEnvironmentVariable("SHELL"));
        var shellHookUpdated = await shellProfileIntegration
            .EnsureHookInShellProfileAsync(shellProfilePath, cancellationToken)
            .ConfigureAwait(false);
        if (!profileScriptUpdated && !shellHookUpdated)
        {
            return;
        }

        await output.WriteInfoAsync($"Updated shell integration in {shellProfilePath}", cancellationToken).ConfigureAwait(false);
    }
}
