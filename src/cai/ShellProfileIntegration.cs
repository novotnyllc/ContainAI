namespace ContainAI.Cli.Host;

internal static class ShellProfileIntegration
{
    private const string ShellIntegrationStartMarker = "# >>> ContainAI shell integration >>>";
    private const string ShellIntegrationEndMarker = "# <<< ContainAI shell integration <<<";
    private const string ProfileDirectoryRelativePath = ".config/containai/profile.d";
    private const string ProfileScriptFileName = "containai.sh";

    public static string GetProfileDirectoryPath(string homeDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        return Path.Combine(homeDirectory, ".config", "containai", "profile.d");
    }

    public static string GetProfileScriptPath(string homeDirectory)
        => Path.Combine(GetProfileDirectoryPath(homeDirectory), ProfileScriptFileName);

    public static string ResolvePreferredShellProfilePath(string homeDirectory, string? shellPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);

        var shellName = Path.GetFileName(shellPath ?? string.Empty);
        return shellName switch
        {
            "zsh" => Path.Combine(homeDirectory, ".zshrc"),
            _ => File.Exists(Path.Combine(homeDirectory, ".bash_profile"))
                ? Path.Combine(homeDirectory, ".bash_profile")
                : Path.Combine(homeDirectory, ".bashrc"),
        };
    }

    public static IReadOnlyList<string> GetCandidateShellProfilePaths(string homeDirectory, string? shellPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);

        var candidates = new List<string>
        {
            ResolvePreferredShellProfilePath(homeDirectory, shellPath),
            Path.Combine(homeDirectory, ".bash_profile"),
            Path.Combine(homeDirectory, ".bashrc"),
            Path.Combine(homeDirectory, ".zshrc"),
        };

        return candidates
            .Distinct(StringComparer.Ordinal)
            .ToArray();
    }

    public static async Task<bool> EnsureProfileScriptAsync(string homeDirectory, string binDirectory, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        ArgumentException.ThrowIfNullOrWhiteSpace(binDirectory);

        var profileScriptPath = GetProfileScriptPath(homeDirectory);
        Directory.CreateDirectory(Path.GetDirectoryName(profileScriptPath)!);

        var script = BuildProfileScript(homeDirectory, binDirectory);
        if (File.Exists(profileScriptPath))
        {
            var existing = await File.ReadAllTextAsync(profileScriptPath, cancellationToken).ConfigureAwait(false);
            if (string.Equals(existing, script, StringComparison.Ordinal))
            {
                return false;
            }
        }

        await File.WriteAllTextAsync(profileScriptPath, script, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public static async Task<bool> EnsureHookInShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shellProfilePath);

        var shellProfileDirectory = Path.GetDirectoryName(shellProfilePath);
        if (!string.IsNullOrWhiteSpace(shellProfileDirectory))
        {
            Directory.CreateDirectory(shellProfileDirectory);
        }
        var existing = File.Exists(shellProfilePath)
            ? await File.ReadAllTextAsync(shellProfilePath, cancellationToken).ConfigureAwait(false)
            : string.Empty;
        if (HasHookBlock(existing))
        {
            return false;
        }

        var hookBlock = BuildHookBlock();
        var updated = string.IsNullOrWhiteSpace(existing)
            ? hookBlock + Environment.NewLine
            : existing.TrimEnd() + Environment.NewLine + Environment.NewLine + hookBlock + Environment.NewLine;
        await File.WriteAllTextAsync(shellProfilePath, updated, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public static bool HasHookBlock(string content)
        => content.Contains(ShellIntegrationStartMarker, StringComparison.Ordinal)
           && content.Contains(ShellIntegrationEndMarker, StringComparison.Ordinal);

    public static async Task<bool> RemoveHookFromShellProfileAsync(string shellProfilePath, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(shellProfilePath);

        if (!File.Exists(shellProfilePath))
        {
            return false;
        }

        var existing = await File.ReadAllTextAsync(shellProfilePath, cancellationToken).ConfigureAwait(false);
        if (!TryRemoveHookBlock(existing, out var updated))
        {
            return false;
        }

        await File.WriteAllTextAsync(shellProfilePath, updated, cancellationToken).ConfigureAwait(false);
        return true;
    }

    public static Task<bool> RemoveProfileScriptAsync(string homeDirectory, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        cancellationToken.ThrowIfCancellationRequested();

        var profileScriptPath = GetProfileScriptPath(homeDirectory);
        if (!File.Exists(profileScriptPath))
        {
            return Task.FromResult(false);
        }

        File.Delete(profileScriptPath);

        var profileDirectory = GetProfileDirectoryPath(homeDirectory);
        if (Directory.Exists(profileDirectory) && !Directory.EnumerateFileSystemEntries(profileDirectory).Any())
        {
            Directory.Delete(profileDirectory);
        }

        return Task.FromResult(true);
    }

    private static bool TryRemoveHookBlock(string content, out string updated)
    {
        updated = content;
        var removed = false;
        while (TryFindHookRange(updated, out var startIndex, out var endIndex))
        {
            updated = updated.Remove(startIndex, endIndex - startIndex);
            removed = true;
        }

        if (!removed)
        {
            return false;
        }

        updated = updated.TrimEnd('\r', '\n');
        if (updated.Length > 0)
        {
            updated += Environment.NewLine;
        }

        return true;
    }

    private static bool TryFindHookRange(string content, out int startIndex, out int endIndex)
    {
        startIndex = content.IndexOf(ShellIntegrationStartMarker, StringComparison.Ordinal);
        if (startIndex < 0)
        {
            endIndex = -1;
            return false;
        }

        var lineStart = content.LastIndexOf('\n', Math.Max(startIndex - 1, 0));
        startIndex = lineStart < 0 ? 0 : lineStart + 1;

        var endMarkerIndex = content.IndexOf(ShellIntegrationEndMarker, startIndex, StringComparison.Ordinal);
        if (endMarkerIndex < 0)
        {
            endIndex = -1;
            return false;
        }

        var lineEnd = content.IndexOf('\n', endMarkerIndex);
        endIndex = lineEnd < 0 ? content.Length : lineEnd + 1;
        return true;
    }

    private static string BuildHookBlock()
    {
        var profileDirectory = "$HOME/" + ProfileDirectoryRelativePath;
        return string.Join(
            Environment.NewLine,
            ShellIntegrationStartMarker,
            $"if [ -d \"{profileDirectory}\" ]; then",
            $"  for _cai_profile in \"{profileDirectory}/\"*.sh; do",
            "    [ -r \"$_cai_profile\" ] && . \"$_cai_profile\"",
            "  done",
            "  unset _cai_profile",
            "fi",
            ShellIntegrationEndMarker);
    }

    private static string BuildProfileScript(string homeDirectory, string binDirectory)
    {
        var pathSegment = NormalizePathForShell(homeDirectory, binDirectory);
        return string.Join(
            Environment.NewLine,
            "# Generated by cai install. Manual edits may be overwritten.",
            $"if [ -d \"{pathSegment}\" ]; then",
            $"  case \":$PATH:\" in *\":{pathSegment}:\"*) ;; *) export PATH=\"{pathSegment}:$PATH\" ;; esac",
            "fi",
            "if command -v complete >/dev/null 2>&1; then",
            "  if [ -n \"${ZSH_VERSION-}\" ] && command -v bashcompinit >/dev/null 2>&1; then",
            "    bashcompinit >/dev/null 2>&1 || true",
            "  fi",
            "  _cai_complete()",
            "  {",
            "    local line point",
            "    line=\"${COMP_LINE:-}\"",
            "    point=\"${COMP_POINT:-${#line}}\"",
            "    local IFS=$'\\n'",
            "    COMPREPLY=($(cai completion suggest --line \"$line\" --position \"$point\" 2>/dev/null))",
            "  }",
            "  complete -o default -F _cai_complete cai",
            "  complete -o default -F _cai_complete containai-docker",
            "fi",
            string.Empty);
    }

    private static string NormalizePathForShell(string homeDirectory, string path)
    {
        var normalizedHome = Path.GetFullPath(homeDirectory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .Replace('\\', '/');
        var normalizedPath = Path.GetFullPath(path)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .Replace('\\', '/');

        if (string.Equals(normalizedPath, normalizedHome, StringComparison.Ordinal))
        {
            return "$HOME";
        }

        if (normalizedPath.StartsWith(normalizedHome + "/", StringComparison.Ordinal))
        {
            return "$HOME/" + normalizedPath[(normalizedHome.Length + 1)..];
        }

        return normalizedPath;
    }
}
