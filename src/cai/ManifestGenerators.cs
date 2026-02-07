using System.Text;
using System.Text.Json;
using Tomlyn;
using Tomlyn.Model;

namespace ContainAI.Cli.Host;

internal static class ManifestGenerators
{
    public static ManifestGeneratedArtifact GenerateImportMap(string manifestPath)
    {
        var headerSource = Directory.Exists(manifestPath) ? "src/manifests/" : Path.GetFileName(manifestPath);
        var entries = ManifestTomlParser.Parse(manifestPath, includeDisabled: false, includeSourceFile: false)
            .Where(static entry => string.Equals(entry.Type, "entry", StringComparison.Ordinal))
            .Where(static entry => !string.IsNullOrEmpty(entry.Source))
            .Where(static entry => !string.IsNullOrEmpty(entry.Target))
            .Where(static entry => !entry.Flags.Contains('G', StringComparison.Ordinal))
            .Where(static entry => !entry.Flags.Contains('g', StringComparison.Ordinal))
            .Select(static entry =>
            {
                var importFlags = entry.Flags.Replace("R", string.Empty, StringComparison.Ordinal);
                return $"/source/{entry.Source}:/target/{entry.Target}:{importFlags}";
            })
            .ToArray();

        var builder = new StringBuilder();
        builder.AppendLine($"# Generated from {headerSource} - DO NOT EDIT");
        builder.AppendLine("# Regenerate with: cai manifest generate import-map src/manifests");
        builder.AppendLine("#");
        builder.AppendLine("# This array maps host paths to volume paths for import.");
        builder.AppendLine("# Format: /source/<host_path>:/target/<volume_path>:<flags>");
        builder.AppendLine("#");
        builder.AppendLine("# Flags:");
        builder.AppendLine("#   f = file, d = directory");
        builder.AppendLine("#   j = json-init (create {} if empty)");
        builder.AppendLine("#   s = secret (skipped with --no-secrets)");
        builder.AppendLine("#   o = optional (skip if source does not exist)");
        builder.AppendLine("#   g = git-filter (strip credential.helper and signing config)");
        builder.AppendLine("#   x = exclude .system/ subdirectory");
        builder.AppendLine("#   p = exclude *.priv.* files");
        builder.AppendLine();
        builder.AppendLine("_IMPORT_SYNC_MAP=(");
        foreach (var entry in entries)
        {
            builder.AppendLine($"    \"{entry}\"");
        }

        builder.AppendLine(")");
        return new ManifestGeneratedArtifact(builder.ToString(), entries.Length);
    }

    public static ManifestGeneratedArtifact GenerateDockerfileSymlinks(string manifestPath)
    {
        var headerSource = Directory.Exists(manifestPath) ? "src/manifests/" : Path.GetFileName(manifestPath);
        var dataMount = "/mnt/agent-data";
        var homeDir = "/home/agent";
        var parsed = ManifestTomlParser.Parse(manifestPath, includeDisabled: true, includeSourceFile: false);

        var mkdirTargets = new List<string>();
        var symlinkCommands = new List<(string VolumePath, string ContainerPath, bool NeedsRemoveFirst)>();
        foreach (var entry in parsed)
        {
            if (string.IsNullOrEmpty(entry.ContainerLink))
            {
                continue;
            }

            if (entry.Flags.Contains('G', StringComparison.Ordinal))
            {
                continue;
            }

            var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal);
            var removeFirst = entry.Flags.Contains('R', StringComparison.Ordinal);
            var containerPath = $"{homeDir}/{entry.ContainerLink}";
            var volumePath = $"{dataMount}/{entry.Target}";
            var parentDir = Path.GetDirectoryName(containerPath)?.Replace('\\', '/') ?? homeDir;
            if (!string.Equals(parentDir, homeDir, StringComparison.Ordinal))
            {
                mkdirTargets.Add(parentDir);
            }

            if (isDirectory)
            {
                mkdirTargets.Add(volumePath);
            }

            symlinkCommands.Add((volumePath, containerPath, removeFirst));
        }

        var uniqueMkdirTargets = DeduplicatePreservingOrder(mkdirTargets);
        var builder = new StringBuilder();
        builder.AppendLine("#!/usr/bin/env bash");
        builder.AppendLine($"# Generated from {headerSource} - DO NOT EDIT");
        builder.AppendLine("# Regenerate with: cai manifest generate dockerfile-symlinks src/manifests");
        builder.AppendLine("# This script is COPY'd into the container and RUN during build");
        builder.AppendLine("set -euo pipefail");
        builder.AppendLine();
        builder.AppendLine("# Logging helper - prints command and executes it");
        builder.AppendLine("run_cmd() {");
        builder.AppendLine("    printf '+ %s\\n' \"$*\"");
        builder.AppendLine("    if ! \"$@\"; then");
        builder.AppendLine("        local arg");
        builder.AppendLine("        printf 'ERROR: Command failed: %s\\n' \"$*\" >&2");
        builder.AppendLine("        printf '  id: %s\\n' \"$(id)\" >&2");
        builder.AppendLine("        printf '  ls -ld /mnt/agent-data:\\n' >&2");
        builder.AppendLine("        ls -ld -- /mnt/agent-data 2>&1 | sed 's/^/    /' >&2 || printf '    (not found)\\n' >&2");
        builder.AppendLine("        for arg in \"$@\"; do");
        builder.AppendLine("            case \"$arg\" in");
        builder.AppendLine("                /home/*|/mnt/*)");
        builder.AppendLine("                    printf '  ls -ld %s:\\n' \"$arg\" >&2");
        builder.AppendLine("                    ls -ld -- \"$arg\" 2>&1 | sed 's/^/    /' >&2 || printf '    (not found)\\n' >&2");
        builder.AppendLine("                    ;;");
        builder.AppendLine("            esac");
        builder.AppendLine("        done");
        builder.AppendLine("        exit 1");
        builder.AppendLine("    fi");
        builder.AppendLine("}");
        builder.AppendLine();
        builder.AppendLine("# Verify /mnt/agent-data is writable");
        builder.AppendLine("if ! touch /mnt/agent-data/.write-test 2>/dev/null; then");
        builder.AppendLine("    printf 'ERROR: /mnt/agent-data is not writable by %s\\n' \"$(id)\" >&2");
        builder.AppendLine("    ls -la /mnt/agent-data 2>&1 || printf '/mnt/agent-data does not exist\\n' >&2");
        builder.AppendLine("    exit 1");
        builder.AppendLine("fi");
        builder.AppendLine("rm -f /mnt/agent-data/.write-test");
        builder.AppendLine();

        if (uniqueMkdirTargets.Count > 0)
        {
            builder.AppendLine("run_cmd mkdir -p \\");
            for (var i = 0; i < uniqueMkdirTargets.Count; i++)
            {
                var continuation = i == uniqueMkdirTargets.Count - 1 ? string.Empty : " \\";
                builder.AppendLine($"    {uniqueMkdirTargets[i]}{continuation}");
            }

            builder.AppendLine();
        }

        foreach (var command in symlinkCommands)
        {
            if (command.NeedsRemoveFirst)
            {
                builder.AppendLine($"run_cmd rm -rf -- \"{EscapeShellDoubleQuoted(command.ContainerPath)}\"");
            }

            builder.AppendLine($"run_cmd ln -sfn -- \"{EscapeShellDoubleQuoted(command.VolumePath)}\" \"{EscapeShellDoubleQuoted(command.ContainerPath)}\"");
        }

        return new ManifestGeneratedArtifact(builder.ToString(), symlinkCommands.Count);
    }

    public static ManifestGeneratedArtifact GenerateInitDirs(string manifestPath)
    {
        var headerSource = Directory.Exists(manifestPath) ? "src/manifests/" : Path.GetFileName(manifestPath);
        var dataDir = "${DATA_DIR}";
        var parsed = ManifestTomlParser.Parse(manifestPath, includeDisabled: true, includeSourceFile: false);

        var dirCommands = new List<string>();
        var fileCommands = new List<string>();
        var secretFileCommands = new List<string>();
        var secretDirCommands = new List<string>();

        foreach (var entry in parsed.Where(static entry => string.Equals(entry.Type, "entry", StringComparison.Ordinal)))
        {
            if (string.IsNullOrEmpty(entry.Target))
            {
                continue;
            }

            if (entry.Flags.Contains('G', StringComparison.Ordinal))
            {
                continue;
            }

            if (entry.Flags.Contains('f', StringComparison.Ordinal) && string.IsNullOrEmpty(entry.ContainerLink))
            {
                continue;
            }

            var volumePath = $"{dataDir}/{entry.Target}";
            var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal);
            var isFile = entry.Flags.Contains('f', StringComparison.Ordinal);
            var isJson = entry.Flags.Contains('j', StringComparison.Ordinal);
            var isSecret = entry.Flags.Contains('s', StringComparison.Ordinal);

            if (isDirectory)
            {
                if (isSecret)
                {
                    secretDirCommands.Add($"ensure_dir \"{volumePath}\"");
                    secretDirCommands.Add($"safe_chmod 700 \"{volumePath}\"");
                }
                else
                {
                    dirCommands.Add($"ensure_dir \"{volumePath}\"");
                }
            }
            else if (isFile)
            {
                var ensureCommand = isJson ? $"ensure_file \"{volumePath}\" true" : $"ensure_file \"{volumePath}\"";
                if (isSecret)
                {
                    secretFileCommands.Add(ensureCommand);
                    secretFileCommands.Add($"safe_chmod 600 \"{volumePath}\"");
                }
                else
                {
                    fileCommands.Add(ensureCommand);
                }
            }
        }

        foreach (var entry in parsed.Where(static entry => string.Equals(entry.Type, "symlink", StringComparison.Ordinal)))
        {
            if (string.IsNullOrEmpty(entry.Target) || !entry.Flags.Contains('f', StringComparison.Ordinal))
            {
                continue;
            }

            var volumePath = $"{dataDir}/{entry.Target}";
            var ensureCommand = entry.Flags.Contains('j', StringComparison.Ordinal)
                ? $"ensure_file \"{volumePath}\" true"
                : $"ensure_file \"{volumePath}\"";
            fileCommands.Add(ensureCommand);
        }

        var builder = new StringBuilder();
        builder.AppendLine("#!/usr/bin/env bash");
        builder.AppendLine($"# Generated from {headerSource} - DO NOT EDIT");
        builder.AppendLine("# Regenerate with: cai manifest generate init-dirs src/manifests");
        builder.AppendLine("#");
        builder.AppendLine("# This script is consumed by cai system init to create volume structure.");
        builder.AppendLine("# It uses helper functions defined in the parent script:");
        builder.AppendLine("#   ensure_dir <path>          - create directory with validation");
        builder.AppendLine("#   ensure_file <path> [json]  - create file (json=true for {} init)");
        builder.AppendLine("#   safe_chmod <mode> <path>   - chmod with symlink/path validation");
        builder.AppendLine();
        builder.AppendLine("# Regular directories");
        foreach (var command in dirCommands)
        {
            builder.AppendLine(command);
        }

        builder.AppendLine();
        builder.AppendLine("# Regular files");
        foreach (var command in fileCommands)
        {
            builder.AppendLine(command);
        }

        builder.AppendLine();
        builder.AppendLine("# Secret files (600 permissions)");
        foreach (var command in secretFileCommands)
        {
            builder.AppendLine(command);
        }

        builder.AppendLine();
        builder.AppendLine("# Secret directories (700 permissions)");
        foreach (var command in secretDirCommands)
        {
            builder.AppendLine(command);
        }

        return new ManifestGeneratedArtifact(builder.ToString(), dirCommands.Count + fileCommands.Count + secretFileCommands.Count + secretDirCommands.Count);
    }

    public static ManifestGeneratedArtifact GenerateContainerLinkSpec(string manifestPath)
    {
        var parsed = ManifestTomlParser.Parse(manifestPath, includeDisabled: true, includeSourceFile: false);
        var links = parsed
            .Where(static entry => !string.IsNullOrEmpty(entry.ContainerLink))
            .Where(static entry => !entry.Flags.Contains('G', StringComparison.Ordinal))
            .Select(static entry => new ManifestLinkSpec(
                Link: $"/home/agent/{entry.ContainerLink}",
                Target: $"/mnt/agent-data/{entry.Target}",
                RemoveFirst: entry.Flags.Contains('R', StringComparison.Ordinal)))
            .ToArray();

        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true });
        writer.WriteStartObject();
        writer.WriteNumber("version", 1);
        writer.WriteString("data_mount", "/mnt/agent-data");
        writer.WriteString("home_dir", "/home/agent");
        writer.WriteStartArray("links");
        foreach (var link in links)
        {
            writer.WriteStartObject();
            writer.WriteString("link", link.Link);
            writer.WriteString("target", link.Target);
            writer.WriteBoolean("remove_first", link.RemoveFirst);
            writer.WriteEndObject();
        }

        writer.WriteEndArray();
        writer.WriteEndObject();
        writer.Flush();

        var content = Encoding.UTF8.GetString(stream.ToArray()) + Environment.NewLine;
        return new ManifestGeneratedArtifact(content, links.Length);
    }

    public static ManifestGeneratedArtifact GenerateAgentWrappers(string manifestsDirectory)
    {
        var files = ResolveManifestFiles(manifestsDirectory);
        var agents = new List<AgentDefinition>();
        foreach (var file in files)
        {
            var content = File.ReadAllText(file);
            var model = Toml.ToModel(content);
            if (model is not TomlTable root || !root.TryGetValue("agent", out var value) || value is not TomlTable table)
            {
                continue;
            }

            var name = ReadString(table, "name");
            var binary = ReadString(table, "binary");
            var defaultArgs = ReadStringArray(table, "default_args");
            var aliases = ReadStringArray(table, "aliases");
            var optional = ReadBool(table, "optional");

            if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(binary) || defaultArgs.Count == 0)
            {
                continue;
            }

            agents.Add(new AgentDefinition(name, binary, defaultArgs, aliases, optional));
        }

        var builder = new StringBuilder();
        builder.AppendLine("# Generated agent launch wrappers from src/manifests/");
        builder.AppendLine("# Regenerate with: cai manifest generate agent-wrappers src/manifests <output>");
        builder.AppendLine("#");
        builder.AppendLine("# These functions prepend default autonomous flags to agent commands.");
        builder.AppendLine("# Use `command` builtin to invoke real binary (avoids recursion).");
        builder.AppendLine("# Sourced via BASH_ENV for non-interactive SSH compatibility.");
        builder.AppendLine();

        foreach (var agent in agents)
        {
            var args = string.Join(' ', agent.DefaultArgs.Select(ShellSingleQuote));
            builder.AppendLine($"# {agent.Name}");
            if (agent.Optional)
            {
                builder.AppendLine($"if command -v {agent.Binary} >/dev/null 2>&1; then");
            }

            AppendWrapperFunction(builder, agent.Name, agent.Binary, args, indent: agent.Optional ? "    " : string.Empty);
            if (!string.Equals(agent.Name, agent.Binary, StringComparison.Ordinal))
            {
                AppendWrapperFunction(builder, agent.Binary, agent.Binary, args, indent: agent.Optional ? "    " : string.Empty);
            }

            foreach (var alias in agent.Aliases)
            {
                AppendWrapperFunction(builder, alias, agent.Binary, args, indent: agent.Optional ? "    " : string.Empty);
            }

            if (agent.Optional)
            {
                builder.AppendLine("fi");
            }

            builder.AppendLine();
        }

        return new ManifestGeneratedArtifact(builder.ToString(), agents.Count);
    }

    private static void AppendWrapperFunction(StringBuilder builder, string functionName, string binary, string args, string indent)
    {
        builder.AppendLine($"{indent}{functionName}() {{");
        if (string.IsNullOrEmpty(args))
        {
            builder.AppendLine($"{indent}    command {binary} \"$@\"");
        }
        else
        {
            builder.AppendLine($"{indent}    command {binary} {args} \"$@\"");
        }

        builder.AppendLine($"{indent}}}");
    }

    private static IReadOnlyList<string> ResolveManifestFiles(string manifestPath)
    {
        if (!Directory.Exists(manifestPath))
        {
            throw new InvalidOperationException($"manifests directory not found: {manifestPath}");
        }

        var files = Directory
            .EnumerateFiles(manifestPath, "*.toml", SearchOption.TopDirectoryOnly)
            .OrderBy(static file => file, StringComparer.Ordinal)
            .ToArray();

        if (files.Length == 0)
        {
            throw new InvalidOperationException($"no .toml files found in directory: {manifestPath}");
        }

        return files;
    }

    private static string EscapeShellDoubleQuoted(string value)
        => value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal);

    private static string ShellSingleQuote(string value)
        => $"'{value.Replace("'", "'\\''", StringComparison.Ordinal)}'";

    private static List<string> DeduplicatePreservingOrder(List<string> values)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var result = new List<string>();
        foreach (var value in values)
        {
            if (seen.Add(value))
            {
                result.Add(value);
            }
        }

        return result;
    }

    private static string ReadString(TomlTable table, string key)
    {
        if (!table.TryGetValue(key, out var value) || value is null)
        {
            return string.Empty;
        }

        return value as string ?? string.Empty;
    }

    private static List<string> ReadStringArray(TomlTable table, string key)
    {
        if (!table.TryGetValue(key, out var value) || value is not TomlArray array)
        {
            return [];
        }

        var values = new List<string>(array.Count);
        foreach (var item in array)
        {
            if (item is string text && !string.IsNullOrWhiteSpace(text))
            {
                values.Add(text);
            }
        }

        return values;
    }

    private static bool ReadBool(TomlTable table, string key) => table.TryGetValue(key, out var value) && value is bool b && b;

    private readonly record struct ManifestLinkSpec(string Link, string Target, bool RemoveFirst);

    private readonly record struct AgentDefinition(
        string Name,
        string Binary,
        IReadOnlyList<string> DefaultArgs,
        IReadOnlyList<string> Aliases,
        bool Optional);
}

internal readonly record struct ManifestGeneratedArtifact(string Content, int Count);
