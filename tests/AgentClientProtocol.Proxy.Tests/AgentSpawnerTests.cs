using AgentClientProtocol.Proxy.Sessions;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class AgentSpawnerTests
{
    [Fact]
    public void SpawnAgent_DirectSpawn_WithMissingBinary_ThrowsWithClearMessage()
    {
        using var session = new AcpSession("/tmp/workspace");
        var spawner = new AgentSpawner(directSpawn: true, TextWriter.Null);
        var missingAgent = $"containai-missing-{Guid.NewGuid():N}";

        var exception = Assert.Throws<InvalidOperationException>(() => spawner.SpawnAgent(session, missingAgent));

        Assert.Contains($"Agent '{missingAgent}' not found", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void SpawnAgent_DirectSpawn_StartsProcess()
    {
        using var session = new AcpSession("/tmp/workspace");
        var stderr = new StringWriter();
        var spawner = new AgentSpawner(directSpawn: true, stderr);

        using var process = spawner.SpawnAgent(session, "sh");

        Assert.NotNull(process);
        Assert.True(process.WaitForExit(milliseconds: 5_000));
    }
}
