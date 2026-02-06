using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

public static class CaiCli
{
    private static readonly RootCommandBuilder RootCommandBuilder = new();

    public static async Task<int> RunAsync(
        string[] args,
        ICaiCommandRuntime runtime,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(args);
        ArgumentNullException.ThrowIfNull(runtime);

        if (args.Length > 0 && args[0] == "--acp")
        {
            var translated = new List<string>(capacity: args.Length + 1)
            {
                "acp",
                "proxy",
            };
            translated.AddRange(args.Skip(1));
            args = translated.ToArray();
        }

        var normalizedArgs = NormalizeRootAliases(args);
        if (normalizedArgs.Length > 0 && ShouldFallbackToLegacyRun(normalizedArgs))
        {
            return await runtime.RunLegacyAsync(normalizedArgs, cancellationToken);
        }

        var root = CreateRootCommand(runtime);
        cancellationToken.ThrowIfCancellationRequested();
        return await root.Parse(normalizedArgs).InvokeAsync(new InvocationConfiguration(), cancellationToken);
    }

    public static RootCommand CreateRootCommand(ICaiCommandRuntime runtime)
    {
        ArgumentNullException.ThrowIfNull(runtime);
        return RootCommandBuilder.Build(runtime);
    }

    private static string[] NormalizeRootAliases(string[] args)
    {
        if (args.Length > 0 && args[0] == "--refresh")
        {
            var normalized = new string[args.Length];
            normalized[0] = "refresh";
            Array.Copy(args, 1, normalized, 1, args.Length - 1);
            return normalized;
        }

        if (args.Length > 0 && (args[0] == "-v" || args[0] == "--version"))
        {
            var normalized = new string[args.Length];
            normalized[0] = "version";
            Array.Copy(args, 1, normalized, 1, args.Length - 1);
            return normalized;
        }

        return args;
    }

    private static bool ShouldFallbackToLegacyRun(string[] args)
    {
        var firstToken = args[0];

        if (CommandCatalog.RootParserTokens.Contains(firstToken))
        {
            return false;
        }

        if (firstToken.StartsWith("-", StringComparison.Ordinal))
        {
            return true;
        }

        return !CommandCatalog.RoutedCommands.Contains(firstToken);
    }
}
