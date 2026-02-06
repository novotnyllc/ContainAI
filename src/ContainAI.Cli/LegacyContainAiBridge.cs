using System.Diagnostics;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

public sealed class LegacyContainAiBridge : ILegacyContainAiBridge
{
    private readonly IContainAiScriptResolver _scriptResolver;

    public LegacyContainAiBridge(IContainAiScriptResolver scriptResolver)
    {
        _scriptResolver = scriptResolver;
    }

    public async Task<int> InvokeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(args);

        var scriptPath = _scriptResolver.ResolveScriptPath();

        using var process = new Process
        {
            StartInfo = CreateStartInfo(scriptPath, args),
        };

        if (!process.Start())
        {
            throw new InvalidOperationException("Failed to launch bash process for legacy containai command execution.");
        }

        using var cancellationRegistration = cancellationToken.Register(() =>
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch
            {
                // Ignore cleanup failures during cancellation.
            }
        });

        await process.WaitForExitAsync(cancellationToken);
        return process.ExitCode;
    }

    private static ProcessStartInfo CreateStartInfo(string scriptPath, IReadOnlyList<string> args)
    {
        var startInfo = new ProcessStartInfo("bash")
        {
            UseShellExecute = false,
        };

        startInfo.ArgumentList.Add("-lc");
        startInfo.ArgumentList.Add("source \"$1\"; shift; containai \"$@\"");
        startInfo.ArgumentList.Add("cai-legacy-bridge");
        startInfo.ArgumentList.Add(scriptPath);

        foreach (var arg in args)
        {
            startInfo.ArgumentList.Add(arg);
        }

        return startInfo;
    }
}
