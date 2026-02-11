using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal interface ICaiUninstallShellIntegrationCleaner
{
    Task CleanAsync(bool dryRun, CancellationToken cancellationToken);
}

internal sealed class CaiUninstallShellIntegrationCleaner : ICaiUninstallShellIntegrationCleaner
{
    private readonly TextWriter stdout;

    public CaiUninstallShellIntegrationCleaner(TextWriter standardOutput)
        => stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));

    public async Task CleanAsync(bool dryRun, CancellationToken cancellationToken)
    {
        var homeDirectory = CaiRuntimeHomePathHelpers.ResolveHomeDirectory();
        var profileScriptPath = ShellProfileIntegration.GetProfileScriptPath(homeDirectory);
        if (dryRun)
        {
            if (File.Exists(profileScriptPath))
            {
                await stdout.WriteLineAsync($"Would remove shell profile script: {profileScriptPath}").ConfigureAwait(false);
            }
        }
        else if (await ShellProfileIntegration.RemoveProfileScriptAsync(homeDirectory, cancellationToken).ConfigureAwait(false))
        {
            await stdout.WriteLineAsync($"Removed shell profile script: {profileScriptPath}").ConfigureAwait(false);
        }

        foreach (var shellProfilePath in ShellProfileIntegration.GetCandidateShellProfilePaths(homeDirectory, Environment.GetEnvironmentVariable("SHELL")))
        {
            if (!File.Exists(shellProfilePath))
            {
                continue;
            }

            var existing = await File.ReadAllTextAsync(shellProfilePath, cancellationToken).ConfigureAwait(false);
            if (!ShellProfileIntegration.HasHookBlock(existing))
            {
                continue;
            }

            if (dryRun)
            {
                await stdout.WriteLineAsync($"Would remove shell integration from: {shellProfilePath}").ConfigureAwait(false);
                continue;
            }

            if (await ShellProfileIntegration.RemoveHookFromShellProfileAsync(shellProfilePath, cancellationToken).ConfigureAwait(false))
            {
                await stdout.WriteLineAsync($"Removed shell integration from: {shellProfilePath}").ConfigureAwait(false);
            }
        }
    }
}
