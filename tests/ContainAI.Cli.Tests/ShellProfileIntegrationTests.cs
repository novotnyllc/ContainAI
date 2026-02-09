using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class ShellProfileIntegrationTests
{
    [Fact]
    public async Task EnsureProfileScriptAsync_WritesPathAndCompletionHooks()
    {
        using var temp = new TemporaryDirectory();
        var homeDirectory = temp.Path;
        var binDirectory = Path.Combine(homeDirectory, ".local", "bin");
        Directory.CreateDirectory(binDirectory);

        var changed = await ShellProfileIntegration.EnsureProfileScriptAsync(homeDirectory, binDirectory, TestContext.Current.CancellationToken);
        var profileScriptPath = ShellProfileIntegration.GetProfileScriptPath(homeDirectory);
        var content = await File.ReadAllTextAsync(profileScriptPath, TestContext.Current.CancellationToken);

        Assert.True(changed);
        Assert.Contains("complete -o default -F _cai_complete cai", content, StringComparison.Ordinal);
        Assert.Contains("complete -o default -F _cai_complete containai-docker", content, StringComparison.Ordinal);
        Assert.Contains("$HOME/.local/bin", content, StringComparison.Ordinal);
    }

    [Fact]
    public async Task EnsureHookInShellProfileAsync_IsIdempotent()
    {
        using var temp = new TemporaryDirectory();
        var shellProfilePath = Path.Combine(temp.Path, ".bashrc");

        var firstWrite = await ShellProfileIntegration.EnsureHookInShellProfileAsync(shellProfilePath, TestContext.Current.CancellationToken);
        var secondWrite = await ShellProfileIntegration.EnsureHookInShellProfileAsync(shellProfilePath, TestContext.Current.CancellationToken);
        var content = await File.ReadAllTextAsync(shellProfilePath, TestContext.Current.CancellationToken);

        Assert.True(firstWrite);
        Assert.False(secondWrite);
        Assert.Equal(1, CountOccurrences(content, "# >>> ContainAI shell integration >>>"));
    }

    [Fact]
    public async Task RemoveHookFromShellProfileAsync_RemovesManagedBlock()
    {
        using var temp = new TemporaryDirectory();
        var shellProfilePath = Path.Combine(temp.Path, ".bashrc");
        await ShellProfileIntegration.EnsureHookInShellProfileAsync(shellProfilePath, TestContext.Current.CancellationToken);

        var removed = await ShellProfileIntegration.RemoveHookFromShellProfileAsync(shellProfilePath, TestContext.Current.CancellationToken);
        var content = await File.ReadAllTextAsync(shellProfilePath, TestContext.Current.CancellationToken);

        Assert.True(removed);
        Assert.DoesNotContain("# >>> ContainAI shell integration >>>", content, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RemoveProfileScriptAsync_RemovesInstalledScript()
    {
        using var temp = new TemporaryDirectory();
        var homeDirectory = temp.Path;
        var binDirectory = Path.Combine(homeDirectory, ".local", "bin");
        Directory.CreateDirectory(binDirectory);
        await ShellProfileIntegration.EnsureProfileScriptAsync(homeDirectory, binDirectory, TestContext.Current.CancellationToken);

        var removed = await ShellProfileIntegration.RemoveProfileScriptAsync(homeDirectory, TestContext.Current.CancellationToken);

        Assert.True(removed);
        Assert.False(File.Exists(ShellProfileIntegration.GetProfileScriptPath(homeDirectory)));
    }

    private static int CountOccurrences(string content, string value)
    {
        var index = 0;
        var count = 0;
        while (true)
        {
            index = content.IndexOf(value, index, StringComparison.Ordinal);
            if (index < 0)
            {
                return count;
            }

            count++;
            index += value.Length;
        }
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"cai-shell-profile-{Guid.NewGuid():N}");
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
