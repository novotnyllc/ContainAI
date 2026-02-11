namespace ContainAI.Cli.Host.RuntimeSupport.Process;

internal static class CaiRuntimeDirectoryCopier
{
    internal static async Task CopyDirectoryAsync(string sourceDirectory, string destinationDirectory, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(destinationDirectory);

        foreach (var sourceFile in Directory.EnumerateFiles(sourceDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destinationFile = Path.Combine(destinationDirectory, Path.GetFileName(sourceFile));
            using var sourceStream = File.OpenRead(sourceFile);
            using var destinationStream = File.Create(destinationFile);
            await sourceStream.CopyToAsync(destinationStream, cancellationToken).ConfigureAwait(false);
        }

        foreach (var sourceSubdirectory in Directory.EnumerateDirectories(sourceDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destinationSubdirectory = Path.Combine(destinationDirectory, Path.GetFileName(sourceSubdirectory));
            await CopyDirectoryAsync(sourceSubdirectory, destinationSubdirectory, cancellationToken).ConfigureAwait(false);
        }
    }
}
