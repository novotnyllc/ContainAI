using ContainAI.Acp.Sessions;
using Xunit;

namespace ContainAI.Acp.Tests;

public class AcpSessionTests
{
    [Fact]
    public void Constructor_GeneratesUniqueSessionId()
    {
        var session1 = new AcpSession("/workspace1");
        var session2 = new AcpSession("/workspace2");

        Assert.NotEqual(session1.ProxySessionId, session2.ProxySessionId);
        Assert.False(string.IsNullOrEmpty(session1.ProxySessionId));
        Assert.False(string.IsNullOrEmpty(session2.ProxySessionId));
    }

    [Fact]
    public void Constructor_SetsWorkspace()
    {
        var session = new AcpSession("/home/user/project");

        Assert.Equal("/home/user/project", session.Workspace);
    }

    [Fact]
    public void AgentSessionId_DefaultsToEmpty()
    {
        var session = new AcpSession("/workspace");

        Assert.Equal("", session.AgentSessionId);
    }

    [Fact]
    public void AgentSessionId_CanBeSet()
    {
        var session = new AcpSession("/workspace");

        session.AgentSessionId = "agent-session-123";

        Assert.Equal("agent-session-123", session.AgentSessionId);
    }

    [Fact]
    public void TryCompleteResponse_UnknownId_ReturnsFalse()
    {
        var session = new AcpSession("/workspace");

        var result = session.TryCompleteResponse("unknown-id", new Protocol.JsonRpcMessage());

        Assert.False(result);
    }

    [Fact]
    public void Cancel_SetsCancellationToken()
    {
        var session = new AcpSession("/workspace");

        Assert.False(session.CancellationToken.IsCancellationRequested);

        session.Cancel();

        Assert.True(session.CancellationToken.IsCancellationRequested);
    }

    [Fact]
    public void Dispose_CanBeCalledMultipleTimes()
    {
        var session = new AcpSession("/workspace");

        // Should not throw
        session.Dispose();
        session.Dispose();
    }

    [Fact]
    public void Dispose_CompletesWithoutError()
    {
        var session = new AcpSession("/workspace");

        // We can't easily test the internal pending requests without exposing them,
        // but we can verify dispose completes without error
        // Note: Cannot access CancellationToken after Dispose as CTS is disposed
        var exception = Record.Exception(() => session.Dispose());

        Assert.Null(exception);
    }

    [Fact]
    public void ProxySessionId_IsValidGuid()
    {
        var session = new AcpSession("/workspace");

        var isValidGuid = Guid.TryParse(session.ProxySessionId, out _);

        Assert.True(isValidGuid);
    }
}
