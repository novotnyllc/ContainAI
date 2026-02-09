using System.Reflection;
using ContainAI.Cli;
using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host;

namespace ContainAI.Cli.Tests;

internal static class RuntimeCompatibilityExtensions
{
    public static Task<int> RunAsync(
        this CaiCommandRuntime runtime,
        IReadOnlyList<string> args,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(runtime);
        ArgumentNullException.ThrowIfNull(args);

        var console = CreateRuntimeConsole(runtime);
        return CaiCli.RunAsync(args.ToArray(), runtime, console, cancellationToken);
    }

    private static RuntimeConsole CreateRuntimeConsole(CaiCommandRuntime runtime)
    {
        var runtimeType = typeof(CaiCommandRuntime);
        var outputField = runtimeType.GetField("stdout", BindingFlags.Instance | BindingFlags.NonPublic);
        var errorField = runtimeType.GetField("stderr", BindingFlags.Instance | BindingFlags.NonPublic);

        var outputWriter = outputField?.GetValue(runtime) as TextWriter ?? TextWriter.Null;
        var errorWriter = errorField?.GetValue(runtime) as TextWriter ?? TextWriter.Null;
        return new RuntimeConsole(outputWriter, errorWriter);
    }

    private sealed class RuntimeConsole(TextWriter outputWriter, TextWriter errorWriter) : ICaiConsole
    {
        public TextWriter OutputWriter { get; } = outputWriter;

        public TextWriter ErrorWriter { get; } = errorWriter;
    }
}
