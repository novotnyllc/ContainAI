namespace ContainAI.Cli.Host;

internal sealed partial class CaiConfigManifestService
{
    private async Task<int> RunManifestParseCoreAsync(
        string manifestPath,
        bool includeDisabled,
        bool emitSourceFile,
        CancellationToken cancellationToken)
    {
        try
        {
            var parsed = manifestTomlParser.Parse(manifestPath, includeDisabled, emitSourceFile);
            foreach (var entry in parsed)
            {
                cancellationToken.ThrowIfCancellationRequested();
                await stdout.WriteLineAsync(entry.ToString()).ConfigureAwait(false);
            }

            return 0;
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }
}
