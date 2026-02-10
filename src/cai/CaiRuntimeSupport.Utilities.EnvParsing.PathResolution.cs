namespace ContainAI.Cli.Host;

internal static partial class CaiRuntimeEnvFileHelpers
{
    internal static RuntimeEnvFilePathResolution ResolveEnvFilePath(string workspaceRoot, string envFile)
    {
        if (Path.IsPathRooted(envFile))
        {
            return new RuntimeEnvFilePathResolution(null, $"env_file path rejected: absolute paths are not allowed (must be workspace-relative): {envFile}");
        }

        var candidate = Path.GetFullPath(Path.Combine(workspaceRoot, envFile));
        var workspacePrefix = workspaceRoot.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal)
            ? workspaceRoot
            : workspaceRoot + Path.DirectorySeparatorChar;
        if (!candidate.StartsWith(workspacePrefix, StringComparison.Ordinal) && !string.Equals(candidate, workspaceRoot, StringComparison.Ordinal))
        {
            return new RuntimeEnvFilePathResolution(null, $"env_file path rejected: outside workspace boundary: {envFile}");
        }

        if (!File.Exists(candidate))
        {
            return new RuntimeEnvFilePathResolution(null, null);
        }

        if (CaiRuntimePathHelpers.IsSymbolicLinkPath(candidate))
        {
            return new RuntimeEnvFilePathResolution(null, $"env_file is a symlink (rejected): {candidate}");
        }

        return new RuntimeEnvFilePathResolution(candidate, null);
    }
}
