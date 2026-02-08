using System.CommandLine;
using System.CommandLine.Invocation;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

public static class CaiCli
{
    public static async Task<int> RunAsync(
        string[] args,
        ICaiCommandRuntime runtime,
        CancellationToken cancellationToken = default)
        => await RunAsync(args, runtime, CaiConsole.System, cancellationToken).ConfigureAwait(false);

    public static async Task<int> RunAsync(
        string[] args,
        ICaiCommandRuntime runtime,
        ICaiConsole console,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(args);
        ArgumentNullException.ThrowIfNull(runtime);
        ArgumentNullException.ThrowIfNull(console);

        var normalizedArgs = NormalizeRootAliases(args);
        var root = CreateRootCommand(runtime, console);
        var invocation = CreateInvocationConfiguration(console);
        if (normalizedArgs.Length > 0 && ShouldImplicitRun(normalizedArgs, root))
        {
            var redirected = new string[normalizedArgs.Length + 1];
            redirected[0] = "run";
            Array.Copy(normalizedArgs, 0, redirected, 1, normalizedArgs.Length);

            cancellationToken.ThrowIfCancellationRequested();
            return await root.Parse(redirected).InvokeAsync(invocation, cancellationToken).ConfigureAwait(false);
        }

        cancellationToken.ThrowIfCancellationRequested();
        return await root.Parse(normalizedArgs).InvokeAsync(invocation, cancellationToken).ConfigureAwait(false);
    }

    public static RootCommand CreateRootCommand(ICaiCommandRuntime runtime)
        => CreateRootCommand(runtime, CaiConsole.System);

    public static RootCommand CreateRootCommand(ICaiCommandRuntime runtime, ICaiConsole console)
    {
        ArgumentNullException.ThrowIfNull(runtime);
        ArgumentNullException.ThrowIfNull(console);
        return RootCommandBuilder.Build(runtime, console);
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

    private static bool ShouldImplicitRun(string[] args, RootCommand root)
    {
        var firstToken = args[0];

        if (firstToken is "help" or "--help" or "-h")
        {
            return false;
        }

        if (firstToken.StartsWith('-'))
        {
            return true;
        }

        return !root.Subcommands.Any(command => string.Equals(command.Name, firstToken, StringComparison.Ordinal));
    }

    private static InvocationConfiguration CreateInvocationConfiguration(ICaiConsole console)
        => new()
        {
            Output = console.OutputWriter,
            Error = console.ErrorWriter,
        };
}
