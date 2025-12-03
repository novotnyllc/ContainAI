using Xunit;

namespace ContainAI.Protocol.Tests;

public class AuditEventTests
{
    [Fact]
    public void CanCreateAuditEvent()
    {
        var evt = new AuditEvent(DateTimeOffset.UtcNow, "Test", "TestEvent", null);
        Assert.Equal("Test", evt.Source);
    }
}
