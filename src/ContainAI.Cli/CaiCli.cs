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

        if (args.Length == 0)
        {
            return await runtime.RunLegacyAsync(Array.Empty<string>(), cancellationToken);
        }

        if (args[0] == "--acp")
        {
            var agent = args.Length > 1 ? args[1] : "claude";
            return await runtime.RunAcpProxyAsync(agent, cancellationToken);
        }

        var normalizedArgs = NormalizeRootAliases(args);
        if (ShouldFallbackToLegacyRun(normalizedArgs))
        {
            return await runtime.RunLegacyAsync(normalizedArgs, cancellationToken);
        }

        var root = CreateRootCommand(runtime);
        return await root.Parse(normalizedArgs).InvokeAsync();
    }

    public static RootCommand CreateRootCommand(ICaiCommandRuntime runtime)
    {
        ArgumentNullException.ThrowIfNull(runtime);

        var root = new RootCommand("ContainAI native CLI")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        root.SetAction((_, cancellationToken) => runtime.RunLegacyAsync(Array.Empty<string>(), cancellationToken));

        foreach (var name in CommandCatalog.RoutedCommands.Where(static command => command != "acp"))
        {
            root.Subcommands.Add(CreateLegacyPassThroughCommand(name, runtime));
        }

        root.Subcommands.Add(CreateAcpCommand(runtime));

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

    private static Command CreateAcpCommand(ICaiCommandRuntime runtime)
    {
        var acpCommand = new Command("acp", "ACP tooling")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        var proxyCommand = new Command("proxy", "Start ACP proxy for an agent")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        var agentArgument = new Argument<string>("agent")
        {
            Arity = ArgumentArity.ZeroOrOne,
            Description = "Agent binary name (defaults to claude)",
            DefaultValueFactory = _ => "claude",
        };

        proxyCommand.Arguments.Add(agentArgument);
        proxyCommand.SetAction((parseResult, cancellationToken) =>
        {
            var agent = parseResult.GetValue(agentArgument) ?? "claude";
            return runtime.RunAcpProxyAsync(agent, cancellationToken);
        });

        acpCommand.Subcommands.Add(proxyCommand);

        return acpCommand;
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
