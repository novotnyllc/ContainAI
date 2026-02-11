using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ContainerRuntime.Configuration;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeOptionParser
{
    public LinkRepairCommandParsing ParseLinkRepairCommandOptions(SystemLinkRepairCommandOptions options)
        => new(
            Mode: ContainerRuntimeDefaults.ResolveLinkRepairMode(options),
            Quiet: options.Quiet,
            BuiltinSpecPath: string.IsNullOrWhiteSpace(options.BuiltinSpec) ? ContainerRuntimeDefaults.DefaultBuiltinLinkSpec : options.BuiltinSpec,
            UserSpecPath: string.IsNullOrWhiteSpace(options.UserSpec) ? ContainerRuntimeDefaults.DefaultUserLinkSpec : options.UserSpec,
            CheckedAtFilePath: string.IsNullOrWhiteSpace(options.CheckedAtFile) ? ContainerRuntimeDefaults.DefaultCheckedAtFile : options.CheckedAtFile);
}
