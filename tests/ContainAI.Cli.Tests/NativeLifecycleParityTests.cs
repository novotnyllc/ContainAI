using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class NativeLifecycleParityTests
{
    [Fact]
    public async Task DoctorFixWithoutTarget_ShowsAvailableTargets()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

        var exitCode = await runtime.RunAsync(["doctor", "fix"], TestContext.Current.CancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Contains("Available doctor fix targets", stdout.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task DoctorResetLimaOnNonMac_ReturnsError()
    {
        if (OperatingSystem.IsMacOS())
        {
            return;
        }

        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

        var exitCode = await runtime.RunAsync(["doctor", "--reset-lima"], TestContext.Current.CancellationToken);

        Assert.Equal(1, exitCode);
        Assert.Contains("--reset-lima is only available on macOS", stderr.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task SetupDryRun_ListsTemplateInstallByDefault()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

        var exitCode = await runtime.RunAsync(["setup", "--dry-run"], TestContext.Current.CancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Contains("Would install templates to", stdout.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task SetupDryRun_SkipTemplatesOmitsTemplateStep()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

        var exitCode = await runtime.RunAsync(["setup", "--dry-run", "--skip-templates"], TestContext.Current.CancellationToken);

        Assert.Equal(0, exitCode);
        Assert.DoesNotContain("Would install templates to", stdout.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task StatusUnknownOption_ReturnsValidationErrorBeforeDocker()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

        var exitCode = await runtime.RunAsync(["status", "--definitely-unknown"], TestContext.Current.CancellationToken);

        Assert.Equal(1, exitCode);
        Assert.Contains("Unknown status option", stderr.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task DockerHelp_WritesUsageWithoutInvokingDocker()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

        var exitCode = await runtime.RunAsync(["docker", "--help"], TestContext.Current.CancellationToken);

        Assert.Equal(0, exitCode);
        Assert.Contains("Usage: cai docker", stdout.ToString(), StringComparison.Ordinal);
    }
}
