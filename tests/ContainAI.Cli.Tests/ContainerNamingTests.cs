using ContainAI.Cli.Host;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class ContainerNamingTests
{
    [Fact]
    public void UsesRepositoryAndBranchLeaf()
    {
        var name = ContainerNameGenerator.Compose("MyRepo", "feature/One");
        Assert.Equal("myrepo-one", name);
    }

    [Fact]
    public void UsesDetachedTokenForDetachedHead()
    {
        var name = ContainerNameGenerator.Compose("MyRepo", "HEAD");
        Assert.Equal("myrepo-detached", name);
    }

    [Fact]
    public void UsesNoGitForNonGitDirectory()
    {
        var name = ContainerNameGenerator.Compose("NoGit", "nogit");
        Assert.Equal("nogit-nogit", name);
    }

    [Fact]
    public void TruncatesResultToTwentyFourCharacters()
    {
        var longRepo = new string('r', 40);
        var longBranch = new string('b', 40);

        var name = ContainerNameGenerator.Compose(longRepo, longBranch);

        Assert.True(name.Length <= 24, $"expected <= 24 chars but got '{name}' ({name.Length})");
        Assert.Contains("-", name, StringComparison.Ordinal);
        Assert.False(name.StartsWith('-'));
        Assert.False(name.EndsWith('-'));
    }

    [Fact]
    public void UsesSanitizationFallbackWhenSegmentsBecomeEmpty()
    {
        var name = ContainerNameGenerator.Compose("___", "___");
        Assert.Equal("repo-branch", name);
    }

    [Fact]
    public void UsesLeafForMultiSegmentBranchNames()
    {
        var name = ContainerNameGenerator.Compose("my-app", "feat/ui/button");
        Assert.Equal("my-app-button", name);
    }

    [Fact]
    public void PreservesSimpleBranchNames()
    {
        var name = ContainerNameGenerator.Compose("project", "develop");
        Assert.Equal("project-develop", name);
    }
}
