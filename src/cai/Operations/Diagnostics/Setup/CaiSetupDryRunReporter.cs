using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Operations.Diagnostics.Setup;

internal sealed class CaiSetupDryRunReporter
{
    private readonly TextWriter stdout;

    public CaiSetupDryRunReporter(TextWriter standardOutput)
        => stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));

    public async Task WriteAsync(CaiSetupPaths setupPaths, bool skipTemplates)
    {
        await stdout.WriteLineAsync($"Would create {setupPaths.ContainAiDir}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Would create {setupPaths.SshDir}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Would generate SSH key {setupPaths.SshKeyPath}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Would verify runtime socket {setupPaths.SocketPath}").ConfigureAwait(false);
        await stdout.WriteLineAsync("Would create Docker context containai-docker").ConfigureAwait(false);
        if (!skipTemplates)
        {
            await stdout.WriteLineAsync($"Would install templates to {CaiRuntimeConfigRoot.ResolveTemplatesDirectory()}").ConfigureAwait(false);
        }
    }
}
