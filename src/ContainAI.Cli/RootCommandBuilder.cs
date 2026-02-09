using System.Collections.Frozen;
using System.CommandLine;
using System.CommandLine.Parsing;
using System.Text.Encodings.Web;
using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host;

namespace ContainAI.Cli;

internal static class RootCommandBuilder
{
    public static RootCommand Build(ICaiCommandRuntime runtime, ICaiConsole console)
    {
        ArgumentNullException.ThrowIfNull(runtime);
        ArgumentNullException.ThrowIfNull(console);

        var root = new RootCommand("ContainAI native CLI")
        {
            TreatUnmatchedTokensAsErrors = true,
        };

        root.SetAction((_, cancellationToken) => runtime.RunRunAsync(
            new RunCommandOptions(
                Workspace: null,
                Fresh: false,
                Detached: false,
                Quiet: false,
                Verbose: false,
                Credentials: null,
                AcknowledgeCredentialRisk: false,
                DataVolume: null,
                Config: null,
                Container: null,
                Force: false,
                Debug: false,
                DryRun: false,
                ImageTag: null,
                Template: null,
                Channel: null,
                Memory: null,
                Cpus: null,
                Env: Array.Empty<string>(),
                CommandArgs: Array.Empty<string>()),
            cancellationToken));

        foreach (var command in new Command[]
                 {
                     RuntimeCommandsBuilder.CreateRunCommand(runtime),
                     RuntimeCommandsBuilder.CreateShellCommand(runtime),
                     RuntimeCommandsBuilder.CreateExecCommand(runtime),
                     MaintenanceCommandsBuilder.CreateDoctorCommand(runtime),
                     MaintenanceCommandsBuilder.CreateInstallCommand(runtime),
                     MaintenanceCommandsBuilder.CreateExamplesCommand(runtime),
                     MaintenanceCommandsBuilder.CreateSetupCommand(runtime),
                     MaintenanceCommandsBuilder.CreateValidateCommand(runtime),
                     RuntimeCommandsBuilder.CreateDockerCommand(runtime),
                     MaintenanceCommandsBuilder.CreateImportCommand(runtime),
                     MaintenanceCommandsBuilder.CreateExportCommand(runtime),
                     MaintenanceCommandsBuilder.CreateSyncCommand(runtime),
                     MaintenanceCommandsBuilder.CreateStopCommand(runtime),
                     RuntimeCommandsBuilder.CreateStatusCommand(runtime),
                     MaintenanceCommandsBuilder.CreateGcCommand(runtime),
                     MaintenanceCommandsBuilder.CreateSshCommand(runtime),
                     MaintenanceCommandsBuilder.CreateLinksCommand(runtime),
                     MaintenanceCommandsBuilder.CreateConfigCommand(runtime),
                     MaintenanceCommandsBuilder.CreateManifestCommand(runtime),
                     MaintenanceCommandsBuilder.CreateTemplateCommand(runtime),
                     MaintenanceCommandsBuilder.CreateUpdateCommand(runtime),
                     MaintenanceCommandsBuilder.CreateRefreshCommand(runtime),
                     MaintenanceCommandsBuilder.CreateUninstallCommand(runtime),
                     CompletionCommandBuilder.CreateCompletionCommand(root, console),
                     VersionCommandBuilder.CreateVersionCommand(runtime, console),
                     MaintenanceCommandsBuilder.CreateSystemCommand(runtime),
                     AcpCommandBuilder.Build(runtime),
                 })
        {
            root.Subcommands.Add(command);
        }

        return root;
    }

    internal static string[] BuildArgumentList(string[]? parsedArgs, IReadOnlyList<string> unmatchedTokens)
        => (parsedArgs, unmatchedTokens.Count) switch
        {
            ({ Length: > 0 }, > 0) => [.. parsedArgs, .. unmatchedTokens],
            ({ Length: > 0 }, 0) => parsedArgs,
            (null or { Length: 0 }, > 0) => [.. unmatchedTokens],
            _ => Array.Empty<string>(),
        };

    internal static (string Line, int Cursor) NormalizeCompletionInput(string line, int position)
    {
        if (string.IsNullOrEmpty(line))
        {
            return (string.Empty, 0);
        }

        var clampedPosition = Math.Clamp(position, 0, line.Length);
        var start = 0;
        while (start < line.Length && char.IsWhiteSpace(line[start]))
        {
            start++;
        }

        var end = start;
        while (end < line.Length && !char.IsWhiteSpace(line[end]))
        {
            end++;
        }

        if (end == start)
        {
            return (line, clampedPosition);
        }

        var invocationToken = line[start..end];
        var invocationName = Path.GetFileNameWithoutExtension(invocationToken);
        if (string.Equals(invocationName, "cai", StringComparison.OrdinalIgnoreCase))
        {
            var trimStart = end;
            while (trimStart < line.Length && char.IsWhiteSpace(line[trimStart]))
            {
                trimStart++;
            }

            return (line[trimStart..], Math.Max(0, clampedPosition - trimStart));
        }

        if (string.Equals(invocationName, "containai-docker", StringComparison.OrdinalIgnoreCase)
            || string.Equals(invocationName, "docker-containai", StringComparison.OrdinalIgnoreCase))
        {
            var trimStart = end;
            while (trimStart < line.Length && char.IsWhiteSpace(line[trimStart]))
            {
                trimStart++;
            }

            var remainder = line[trimStart..];
            var rewritten = string.IsNullOrWhiteSpace(remainder)
                ? "docker "
                : $"docker {remainder}";
            var cursor = "docker ".Length + Math.Max(0, clampedPosition - trimStart);
            return (rewritten, Math.Clamp(cursor, 0, rewritten.Length));
        }

        return (line, clampedPosition);
    }

    internal static string[] NormalizeCompletionArguments(string line, FrozenSet<string> knownCommands)
    {
        var normalized = CommandLineParser.SplitCommandLine(line).ToArray();
        if (normalized.Length == 0)
        {
            return Array.Empty<string>();
        }

        normalized = normalized switch
        {
            ["help"] => ["--help"],
            ["help", .. var helpArgs] when helpArgs.Length > 0 => [.. helpArgs, "--help"],
            ["--refresh", .. var refreshArgs] => ["refresh", .. refreshArgs],
            ["-v" or "--version", .. var versionArgs] => ["version", .. versionArgs],
            _ => normalized,
        };

        if (ShouldImplicitRunForCompletion(normalized, knownCommands))
        {
            return ["run", .. normalized];
        }

        return normalized;
    }

    internal static string ExpandHome(string path)
    {
        if (!path.StartsWith('~'))
        {
            return path;
        }

        var home = Environment.GetEnvironmentVariable("HOME");
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }

        if (path.Length == 1)
        {
            return home!;
        }

        return path[1] is '/' or '\\'
            ? Path.Combine(home!, path[2..])
            : path;
    }

    internal static string GetVersionJson()
    {
        var versionInfo = InstallMetadata.ResolveVersionInfo();
        var installType = InstallMetadata.GetInstallTypeLabel(versionInfo.InstallType);

        return $"{{\"version\":\"{JavaScriptEncoder.Default.Encode(versionInfo.Version)}\",\"install_type\":\"{JavaScriptEncoder.Default.Encode(installType)}\",\"install_dir\":\"{JavaScriptEncoder.Default.Encode(versionInfo.InstallDir)}\"}}";
    }

    private static bool ShouldImplicitRunForCompletion(string[] args, FrozenSet<string> knownCommands)
    {
        if (args.Length == 0)
        {
            return false;
        }

        var firstToken = args[0];
        if (firstToken is "--help" or "-h")
        {
            return false;
        }

        if (firstToken.StartsWith('-'))
        {
            return true;
        }

        if (knownCommands.Any(command => command.StartsWith(firstToken, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        return !knownCommands.Contains(firstToken);
    }
}
