using System.CommandLine;
using System.Text.Encodings.Web;
using System.Reflection;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal sealed class RootCommandBuilder
{
    private readonly AcpCommandBuilder _acpCommandBuilder;

    public RootCommandBuilder(AcpCommandBuilder? acpCommandBuilder = null)
    {
        _acpCommandBuilder = acpCommandBuilder ?? new AcpCommandBuilder();
    }

    public RootCommand Build(ICaiCommandRuntime runtime)
    {
        ArgumentNullException.ThrowIfNull(runtime);

        var root = new RootCommand("ContainAI native CLI")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        root.SetAction((_, cancellationToken) => runtime.RunLegacyAsync(Array.Empty<string>(), cancellationToken));

        foreach (var name in CommandCatalog.RoutedCommandOrder.Where(static command => command != "acp"))
        {
            var command = name == "version"
                ? CreateVersionCommand(runtime)
                : CreateLegacyPassThroughCommand(name, runtime);

            root.Subcommands.Add(command);
        }

        root.Subcommands.Add(_acpCommandBuilder.Build(runtime));

        return root;
    }

    private static Command CreateLegacyPassThroughCommand(string commandName, ICaiCommandRuntime runtime)
    {
        var command = new Command(commandName)
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        command.SetAction((parseResult, cancellationToken) =>
        {
            var forwarded = new List<string>(capacity: parseResult.UnmatchedTokens.Count + 1)
            {
                commandName,
            };

            forwarded.AddRange(parseResult.UnmatchedTokens);
            return runtime.RunLegacyAsync(forwarded, cancellationToken);
        });

        return command;
    }

    private static Command CreateVersionCommand(ICaiCommandRuntime runtime)
    {
        var versionCommand = new Command("version")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        var jsonOption = new Option<bool>("--json")
        {
            Description = "Emit version information as JSON.",
        };
        versionCommand.Options.Add(jsonOption);

        versionCommand.SetAction((parseResult, cancellationToken) =>
        {
            var useNativeJson = parseResult.GetValue(jsonOption) && parseResult.UnmatchedTokens.Count == 0;
            if (useNativeJson)
            {
                cancellationToken.ThrowIfCancellationRequested();
                Console.Out.WriteLine(GetVersionJson());
                return Task.FromResult(0);
            }

            var forwarded = new List<string>(capacity: parseResult.UnmatchedTokens.Count + 2)
            {
                "version",
            };

            if (parseResult.GetValue(jsonOption))
            {
                forwarded.Add("--json");
            }

            forwarded.AddRange(parseResult.UnmatchedTokens);
            return runtime.RunLegacyAsync(forwarded, cancellationToken);
        });

        return versionCommand;
    }

    internal static string GetVersionJson()
    {
        var installDir = ResolveInstallDirectory();
        var version = ResolveVersion(installDir);
        var installType = ResolveInstallType(installDir);

        return $"{{\"version\":\"{JavaScriptEncoder.Default.Encode(version)}\",\"install_type\":\"{JavaScriptEncoder.Default.Encode(installType)}\",\"install_dir\":\"{JavaScriptEncoder.Default.Encode(installDir)}\"}}";
    }

    private static string ResolveVersion(string installDir)
    {
        var versionFile = Path.Combine(installDir, "VERSION");
        if (File.Exists(versionFile))
        {
            var value = File.ReadAllText(versionFile).Trim();
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        var assemblyVersion = Assembly.GetEntryAssembly()?.GetName().Version?.ToString()
            ?? Assembly.GetExecutingAssembly().GetName().Version?.ToString();

        return string.IsNullOrWhiteSpace(assemblyVersion) ? "0.0.0" : assemblyVersion;
    }

    private static string ResolveInstallType(string installDir)
    {
        if (Directory.Exists(Path.Combine(installDir, ".git")))
        {
            return "git";
        }

        var normalized = installDir.Replace('\\', '/');
        if (normalized.Contains("/.local/share/containai", StringComparison.Ordinal))
        {
            return "local";
        }

        return "installed";
    }

    private static string ResolveInstallDirectory()
    {
        foreach (var candidate in EnumerateInstallDirectoryCandidates())
        {
            if (File.Exists(Path.Combine(candidate, "VERSION")))
            {
                return candidate;
            }
        }

        return Directory.GetCurrentDirectory();
    }

    private static IEnumerable<string> EnumerateInstallDirectoryCandidates()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var root in new[] { AppContext.BaseDirectory, Directory.GetCurrentDirectory() })
        {
            var current = Path.GetFullPath(root);
            while (!string.IsNullOrWhiteSpace(current))
            {
                if (seen.Add(current))
                {
                    yield return current;
                }

                var parent = Directory.GetParent(current);
                if (parent is null)
                {
                    break;
                }

                current = parent.FullName;
            }
        }
    }
}
