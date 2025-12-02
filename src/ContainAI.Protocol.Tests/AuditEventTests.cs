using Xunit;

namespace ContainAI.Protocol.Tests;

public class AuditEventTests
{
    [Fact]
    public void CanCreateAuditEvent()
    {
        var event = new AuditEvent(DateTimeOffset.UtcNow, "Test", "TestEvent", null);
        Assert.Equal("Test", event.Source);
    }
}
