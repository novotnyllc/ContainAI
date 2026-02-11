namespace ContainAI.Cli.Host;

internal sealed partial class SessionSshCommandBuilder
{
    private static string JoinForShell(IReadOnlyList<string> args)
    {
        if (args.Count == 0)
        {
            return "true";
        }

        var escaped = new string[args.Count];
        for (var index = 0; index < args.Count; index++)
        {
            escaped[index] = QuoteBash(args[index]);
        }

        return string.Join(" ", escaped);
    }

    private static string QuoteBash(string value)
        => string.IsNullOrEmpty(value)
            ? "''"
            : $"'{SessionRuntimeInfrastructure.EscapeForSingleQuotedShell(value)}'";
}
