using System;
using System.IO;

namespace AgentClientProtocol.Proxy.PathTranslation;

internal sealed class WorkspacePathTranslator
{
    private readonly string hostWorkspace;
    private readonly string containerWorkspace;
    private readonly string normalizedHostWorkspace;

    public WorkspacePathTranslator(string hostWorkspacePath, string containerWorkspacePath)
    {
        hostWorkspace = hostWorkspacePath;
        containerWorkspace = containerWorkspacePath;
        normalizedHostWorkspace = Path.GetFullPath(hostWorkspacePath).TrimEnd(Path.DirectorySeparatorChar);
    }

    public string TranslateToContainer(string hostPath)
    {
        ArgumentNullException.ThrowIfNull(hostPath);

        if (!Path.IsPathRooted(hostPath))
            return hostPath;

        if (!TryNormalizePath(hostPath, out var normalizedPath))
            return hostPath;

        if (normalizedPath == normalizedHostWorkspace)
            return containerWorkspace;

        var prefix = normalizedHostWorkspace + Path.DirectorySeparatorChar;
        if (normalizedPath.StartsWith(prefix, StringComparison.Ordinal))
        {
            var relative = normalizedPath.Substring(prefix.Length);
            return containerWorkspace + "/" + relative.Replace(Path.DirectorySeparatorChar, '/');
        }

        return hostPath;
    }

    public string TranslateToHost(string containerPath)
    {
        ArgumentNullException.ThrowIfNull(containerPath);

        if (!containerPath.StartsWith('/'))
            return containerPath;

        var normalizedContainer = containerPath.TrimEnd('/');

        if (normalizedContainer == containerWorkspace)
            return hostWorkspace;

        var prefix = containerWorkspace + "/";
        if (normalizedContainer.StartsWith(prefix, StringComparison.Ordinal))
        {
            var relative = normalizedContainer.Substring(prefix.Length);
            return Path.Combine(hostWorkspace, relative.Replace('/', Path.DirectorySeparatorChar));
        }

        return containerPath;
    }

    private static bool TryNormalizePath(string path, out string normalizedPath)
    {
        try
        {
            normalizedPath = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
            return true;
        }
        catch (ArgumentException)
        {
            normalizedPath = string.Empty;
            return false;
        }
        catch (SystemException ex) when (ex is NotSupportedException or PathTooLongException)
        {
            _ = ex;
            normalizedPath = string.Empty;
            return false;
        }
    }
}
