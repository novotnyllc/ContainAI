namespace ContainAI.Cli.Host;

internal sealed partial class CaiSetupOperations
{
    private async Task WriteSetupDryRunAsync(SetupPaths setupPaths, bool skipTemplates)
    {
        await stdout.WriteLineAsync($"Would create {setupPaths.ContainAiDir}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Would create {setupPaths.SshDir}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Would generate SSH key {setupPaths.SshKeyPath}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Would verify runtime socket {setupPaths.SocketPath}").ConfigureAwait(false);
        await stdout.WriteLineAsync("Would create Docker context containai-docker").ConfigureAwait(false);
        if (!skipTemplates)
        {
            await stdout.WriteLineAsync($"Would install templates to {ResolveTemplatesDirectory()}").ConfigureAwait(false);
        }
    }
}
