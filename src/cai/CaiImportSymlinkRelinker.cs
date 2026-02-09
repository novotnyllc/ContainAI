using System.Diagnostics;
using System.Text;

namespace ContainAI.Cli.Host;

internal interface IImportSymlinkRelinker
{
    Task<int> RelinkImportedDirectorySymlinksAsync(
        string volume,
        string sourceDirectoryPath,
        string targetRelativePath,
        CancellationToken cancellationToken);
}

internal sealed class CaiImportSymlinkRelinker : CaiRuntimeSupport
    , IImportSymlinkRelinker
{
    public CaiImportSymlinkRelinker(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<int> RelinkImportedDirectorySymlinksAsync(
        string volume,
        string sourceDirectoryPath,
        string targetRelativePath,
        CancellationToken cancellationToken)
    {
        var symlinks = CollectSymlinksForRelink(sourceDirectoryPath);
        if (symlinks.Count == 0)
        {
            return 0;
        }

        var operations = new List<(string LinkPath, string RelativeTarget)>();
        foreach (var symlink in symlinks)
        {
            if (!Path.IsPathRooted(symlink.Target))
            {
                continue;
            }

            var absoluteTarget = Path.GetFullPath(symlink.Target);
            if (!IsPathWithinDirectory(absoluteTarget, sourceDirectoryPath))
            {
                await stderr.WriteLineAsync($"[WARN] preserving external absolute symlink: {symlink.RelativePath} -> {symlink.Target}").ConfigureAwait(false);
                continue;
            }

            if (!File.Exists(absoluteTarget) && !Directory.Exists(absoluteTarget))
            {
                continue;
            }

            var sourceRelativeTarget = Path.GetRelativePath(sourceDirectoryPath, absoluteTarget).Replace('\\', '/');
            var volumeLinkPath = $"/target/{targetRelativePath.TrimEnd('/')}/{symlink.RelativePath.TrimStart('/')}";
            var volumeTargetPath = $"/target/{targetRelativePath.TrimEnd('/')}/{sourceRelativeTarget.TrimStart('/')}";
            var volumeParentPath = NormalizePosixPath(Path.GetDirectoryName(volumeLinkPath)?.Replace('\\', '/') ?? "/target");
            var relativeTarget = ComputeRelativePosixPath(volumeParentPath, NormalizePosixPath(volumeTargetPath));
            operations.Add((NormalizePosixPath(volumeLinkPath), relativeTarget));
        }

        if (operations.Count == 0)
        {
            return 0;
        }

        var commandBuilder = new StringBuilder();
        foreach (var operation in operations)
        {
            commandBuilder.Append("link='");
            commandBuilder.Append(EscapeForSingleQuotedShell(operation.LinkPath));
            commandBuilder.Append("'; ");
            commandBuilder.Append("mkdir -p \"$(dirname \"$link\")\"; ");
            commandBuilder.Append("rm -rf -- \"$link\"; ");
            commandBuilder.Append("ln -sfn -- '");
            commandBuilder.Append(EscapeForSingleQuotedShell(operation.RelativeTarget));
            commandBuilder.Append("' \"$link\"; ");
        }

        var result = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", commandBuilder.ToString()],
            cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
            await stderr.WriteLineAsync(errorOutput.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private static List<ImportSymlink> CollectSymlinksForRelink(string sourceDirectoryPath)
    {
        var symlinks = new List<ImportSymlink>();
        var stack = new Stack<string>();
        stack.Push(sourceDirectoryPath);
        while (stack.Count > 0)
        {
            var currentDirectory = stack.Pop();
            IEnumerable<string> entries;
            try
            {
                entries = Directory.EnumerateFileSystemEntries(currentDirectory);
            }
            catch (IOException)
            {
                continue;
            }
            catch (UnauthorizedAccessException)
            {
                continue;
            }
            catch (NotSupportedException)
            {
                continue;
            }
            catch (ArgumentException)
            {
                continue;
            }

            foreach (var entry in entries)
            {
                if (IsSymbolicLinkPath(entry))
                {
                    var linkTarget = ReadSymlinkTarget(entry);
                    if (!string.IsNullOrWhiteSpace(linkTarget))
                    {
                        var relativePath = Path.GetRelativePath(sourceDirectoryPath, entry).Replace('\\', '/');
                        symlinks.Add(new ImportSymlink(relativePath, linkTarget));
                    }

                    continue;
                }

                if (Directory.Exists(entry))
                {
                    stack.Push(entry);
                }
            }
        }

        return symlinks;
    }

    private static string? ReadSymlinkTarget(string path)
    {
        try
        {
            var fileInfo = new FileInfo(path);
            if (!string.IsNullOrWhiteSpace(fileInfo.LinkTarget))
            {
                return fileInfo.LinkTarget;
            }
        }
        catch (IOException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }
        catch (NotSupportedException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }
        catch (ArgumentException ex)
        {
            Debug.WriteLine($"Failed to read file symlink target for '{path}': {ex.Message}");
        }

        try
        {
            var directoryInfo = new DirectoryInfo(path);
            if (!string.IsNullOrWhiteSpace(directoryInfo.LinkTarget))
            {
                return directoryInfo.LinkTarget;
            }
        }
        catch (IOException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }
        catch (NotSupportedException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }
        catch (ArgumentException ex)
        {
            Debug.WriteLine($"Failed to read directory symlink target for '{path}': {ex.Message}");
        }

        return null;
    }

    private static bool IsPathWithinDirectory(string path, string directory)
    {
        var normalizedDirectory = Path.GetFullPath(directory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var normalizedPath = Path.GetFullPath(path)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (string.Equals(normalizedPath, normalizedDirectory, StringComparison.Ordinal))
        {
            return true;
        }

        return normalizedPath.StartsWith(
            normalizedDirectory + Path.DirectorySeparatorChar,
            StringComparison.Ordinal);
    }

    private static string NormalizePosixPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return "/";
        }

        var normalized = path.Replace('\\', '/');
        normalized = normalized.Replace("//", "/", StringComparison.Ordinal);
        return string.IsNullOrWhiteSpace(normalized) ? "/" : normalized;
    }

    private static string ComputeRelativePosixPath(string fromDirectory, string toPath)
    {
        var fromParts = NormalizePosixPath(fromDirectory).Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        var toParts = NormalizePosixPath(toPath).Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        var maxShared = Math.Min(fromParts.Length, toParts.Length);
        var shared = 0;
        while (shared < maxShared && string.Equals(fromParts[shared], toParts[shared], StringComparison.Ordinal))
        {
            shared++;
        }

        var segments = new List<string>();
        for (var index = shared; index < fromParts.Length; index++)
        {
            segments.Add("..");
        }

        for (var index = shared; index < toParts.Length; index++)
        {
            segments.Add(toParts[index]);
        }

        return segments.Count == 0 ? "." : string.Join('/', segments);
    }
}
