namespace ContainAI.Cli.Host.ContainerRuntime.Models;

internal enum LinkRepairMode
{
    Check,
    Fix,
    DryRun,
}

internal sealed class LinkRepairStats
{
    public int Broken { get; set; }

    public int Missing { get; set; }

    public int Ok { get; set; }

    public int Fixed { get; set; }

    public int Errors { get; set; }
}

internal readonly record struct ProcessCaptureResult(int ExitCode, string StandardOutput, string StandardError);
