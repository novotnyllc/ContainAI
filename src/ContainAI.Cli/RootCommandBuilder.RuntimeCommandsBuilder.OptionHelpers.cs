using System.CommandLine;

namespace ContainAI.Cli;

internal static partial class RuntimeCommandsBuilder
{
    private static void AddOptions(Command command, params Option[] options)
    {
        foreach (var option in options)
        {
            command.Options.Add(option);
        }
    }

    private static Option<string?> CreateWorkspaceOption(string description)
        => new("--workspace", "-w")
        {
            Description = description,
        };

    private static Option<bool> CreateFreshOption()
        => new("--fresh")
        {
            Description = "Request a fresh runtime environment.",
        };

    private static Option<bool> CreateRestartOption()
        => new("--restart")
        {
            Description = "Alias for --fresh.",
        };

    private static Option<string?> CreateDataVolumeOption()
        => new("--data-volume")
        {
            Description = "Data volume override.",
        };

    private static Option<string?> CreateConfigOption()
        => new("--config")
        {
            Description = "Path to config file.",
        };

    private static Option<string?> CreateContainerOption()
        => new("--container")
        {
            Description = "Attach to a specific container.",
        };

    private static Option<bool> CreateForceOption()
        => new("--force")
        {
            Description = "Force operation where supported.",
        };

    private static Option<bool> CreateQuietOption()
        => new("--quiet", "-q")
        {
            Description = "Suppress non-essential output.",
        };

    private static Option<bool> CreateVerboseOption()
        => new("--verbose")
        {
            Description = "Enable verbose output.",
        };

    private static Option<bool> CreateDebugOption()
        => new("--debug", "-D")
        {
            Description = "Enable debug output.",
        };

    private static Option<bool> CreateDryRunOption()
        => new("--dry-run")
        {
            Description = "Show planned actions without executing.",
        };

    private static Option<string?> CreateTemplateOption()
        => new("--template")
        {
            Description = "Template name.",
        };

    private static Option<string?> CreateChannelOption()
        => new("--channel")
        {
            Description = "Channel override.",
        };

    private static Option<string?> CreateMemoryOption()
        => new("--memory")
        {
            Description = "Container memory limit.",
        };

    private static Option<string?> CreateCpusOption()
        => new("--cpus")
        {
            Description = "Container CPU limit.",
        };
}
