using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandSetUnsetExecutor(
    TomlCommandExecutionServices services,
    Regex workspaceKeyRegex,
    Regex globalKeyRegex);
