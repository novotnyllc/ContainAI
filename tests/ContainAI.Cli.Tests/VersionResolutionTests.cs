using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class VersionResolutionTests
{
    [Fact]
    public async Task ReadsVersionFromScriptDirectory()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-version-same-dir");
        await File.WriteAllTextAsync(
            Path.Combine(temp.Path, "VERSION"),
            "1.2.3-test\n",
            TestContext.Current.CancellationToken);

        var version = await ResolveVersionAsync(temp.Path);
        Assert.Equal("1.2.3-test", version);
    }

    [Fact]
    public async Task ReadsVersionFromParentDirectory()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-version-parent");
        var scriptDir = Path.Combine(temp.Path, "src");
        Directory.CreateDirectory(scriptDir);
        await File.WriteAllTextAsync(
            Path.Combine(temp.Path, "VERSION"),
            "9.9.9-test\n",
            TestContext.Current.CancellationToken);

        var version = await ResolveVersionAsync(scriptDir);
        Assert.Equal("9.9.9-test", version);
    }

    private static async Task<string> ResolveVersionAsync(string scriptDirectory)
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var versionLibraryPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/version.sh");

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            source {ShellTestSupport.ShellQuote(versionLibraryPath)}
            _CAI_SCRIPT_DIR={ShellTestSupport.ShellQuote(scriptDirectory)}
            _cai_get_version
            """,
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        return result.StdOut.Trim();
    }
}
