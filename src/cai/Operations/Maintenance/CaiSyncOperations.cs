using ContainAI.Cli.Host.RuntimeSupport.Paths;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal sealed class CaiSyncOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public CaiSyncOperations(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<int> RunSyncAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var sourceRoot = CaiRuntimeHomePathHelpers.ResolveHomeDirectory();
        var destinationRoot = "/mnt/agent-data";
        if (!Directory.Exists(destinationRoot))
        {
            await stderr.WriteLineAsync("sync must run inside a container with /mnt/agent-data").ConfigureAwait(false);
            return 1;
        }

        foreach (var directory in new[] { ".config", ".ssh", ".claude", ".codex" })
        {
            var source = Path.Combine(sourceRoot, directory);
            var destination = Path.Combine(destinationRoot, directory);
            if (!Directory.Exists(source))
            {
                continue;
            }

            Directory.CreateDirectory(destination);
            await CaiRuntimeDirectoryCopier.CopyDirectoryAsync(source, destination, cancellationToken).ConfigureAwait(false);
        }

        await stdout.WriteLineAsync("Sync complete.").ConfigureAwait(false);
        return 0;
    }
}
