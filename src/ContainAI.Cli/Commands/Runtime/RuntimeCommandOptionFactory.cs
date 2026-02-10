using System.CommandLine;

namespace ContainAI.Cli.Commands.Runtime;

internal static class RuntimeCommandOptionFactory
{
    internal static void AddOptions(Command command, params Option[] options)
    {
        foreach (var option in options)
        {
            command.Options.Add(option);
        }
    }

    internal static Option<string?> CreateWorkspaceOption(string description)
        => new("--workspace", "-w")
        {
            Description = description,
        };

    internal static Option<bool> CreateFreshOption()
        => new("--fresh")
        {
            Description = "Request a fresh runtime environment.",
        };

    internal static Option<bool> CreateRestartOption()
        => new("--restart")
        {
            Description = "Alias for --fresh.",
        };

    internal static Option<string?> CreateDataVolumeOption()
        => new("--data-volume")
        {
            Description = "Data volume override.",
        };

    internal static Option<string?> CreateConfigOption()
        => new("--config")
        {
            Description = "Path to config file.",
        };

    internal static Option<string?> CreateContainerOption()
        => new("--container")
        {
            Description = "Attach to a specific container.",
        };

    internal static Option<bool> CreateForceOption()
        => new("--force")
        {
            Description = "Force operation where supported.",
        };

    internal static Option<bool> CreateQuietOption()
        => new("--quiet", "-q")
        {
            Description = "Suppress non-essential output.",
        };

    internal static Option<bool> CreateVerboseOption()
        => new("--verbose")
        {
            Description = "Enable verbose output.",
        };

    internal static Option<bool> CreateDebugOption()
        => new("--debug", "-D")
        {
            Description = "Enable debug output.",
        };

    internal static Option<bool> CreateDryRunOption()
        => new("--dry-run")
        {
            Description = "Show planned actions without executing.",
        };

    internal static Option<string?> CreateTemplateOption()
        => new("--template")
        {
            Description = "Template name.",
        };

    internal static Option<string?> CreateChannelOption()
        => new("--channel")
        {
            Description = "Channel override.",
        };

    internal static Option<string?> CreateMemoryOption()
        => new("--memory")
        {
            Description = "Container memory limit.",
        };

    internal static Option<string?> CreateCpusOption()
        => new("--cpus")
        {
            Description = "Container CPU limit.",
        };
}
