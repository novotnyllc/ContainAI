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

    [Fact]
    public async Task UninstallDryRun_ReportsShellIntegrationCleanup()
    {
        using var temp = new TemporaryDirectory();
        var homeDirectory = temp.Path;
        var shellProfilePath = Path.Combine(homeDirectory, ".bashrc");
        Directory.CreateDirectory(Path.GetDirectoryName(shellProfilePath)!);
        await File.WriteAllTextAsync(
            shellProfilePath,
            """
            # >>> ContainAI shell integration >>>
            if [ -d "$HOME/.config/containai/profile.d" ]; then
              for _cai_profile in "$HOME/.config/containai/profile.d/"*.sh; do
                [ -r "$_cai_profile" ] && . "$_cai_profile"
              done
              unset _cai_profile
            fi
            # <<< ContainAI shell integration <<<
            """,
            TestContext.Current.CancellationToken);
        var profileScriptPath = Path.Combine(homeDirectory, ".config", "containai", "profile.d", "containai.sh");
        Directory.CreateDirectory(Path.GetDirectoryName(profileScriptPath)!);
        await File.WriteAllTextAsync(profileScriptPath, "# profile script", TestContext.Current.CancellationToken);

        var originalHome = Environment.GetEnvironmentVariable("HOME");
        Environment.SetEnvironmentVariable("HOME", homeDirectory);
        try
        {
            using var stdout = new StringWriter();
            using var stderr = new StringWriter();
            var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

            var exitCode = await runtime.RunAsync(["uninstall", "--dry-run"], TestContext.Current.CancellationToken);

            Assert.Equal(0, exitCode);
            var output = stdout.ToString();
            Assert.Contains("Would remove shell profile script", output, StringComparison.Ordinal);
            Assert.Contains("Would remove shell integration from", output, StringComparison.Ordinal);
        }
        finally
        {
            Environment.SetEnvironmentVariable("HOME", originalHome);
        }
    }

    [Fact]
    public async Task ConfigGetWrapper_InjectsGetSubcommand()
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var runtime = new NativeLifecycleCommandRuntime(stdout, stderr);

        var exitCode = await runtime.RunConfigGetCommandAsync([], TestContext.Current.CancellationToken);

        Assert.Equal(1, exitCode);
        Assert.Contains("invalid config command usage", stderr.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("config requires a subcommand", stderr.ToString(), StringComparison.Ordinal);
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"cai-native-runtime-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }
    }
}
