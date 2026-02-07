using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

public static class CaiCli
{
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
        var root = CreateRootCommand(runtime);
        if (normalizedArgs.Length > 0 && ShouldImplicitRun(normalizedArgs))
        {
            var redirected = new string[normalizedArgs.Length + 1];
            redirected[0] = "run";
            Array.Copy(normalizedArgs, 0, redirected, 1, normalizedArgs.Length);

            cancellationToken.ThrowIfCancellationRequested();
            return await root.Parse(redirected).InvokeAsync(new InvocationConfiguration(), cancellationToken);
        }

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
        if (args is ["--refresh", .. var refreshArgs])
        {
            return ["refresh", .. refreshArgs];
        }

        if (args is ["-v" or "--version", .. var versionArgs])
        {
            return ["version", .. versionArgs];
        }

        return args;
    }

    private static bool ShouldImplicitRun(string[] args)
    {
        var firstToken = args[0];

        if (CommandCatalog.RootParserTokens.Contains(firstToken))
        {
            return false;
        }

        if (firstToken.StartsWith('-'))
        {
            return true;
        }

        return !CommandCatalog.RoutedCommands.Contains(firstToken);
    }
}
