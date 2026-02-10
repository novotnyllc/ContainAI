namespace ContainAI.Cli.Host;

internal sealed partial class CaiUninstallOperations
{
    private async Task RemoveShellIntegrationAsync(bool dryRun, CancellationToken cancellationToken)
    {
        var homeDirectory = ResolveHomeDirectory();
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
