using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using ContainAI.Protocol;
using Xunit;

namespace ContainAI.LogCollector.Tests;

public class CollectorTests
{
    [Fact]
    public async Task Collector_WritesReceivedEventsToLogFile()
    {
        // Arrange
        var fileSystem = new MockFileSystem();
        var socketProvider = new MockSocketProvider();
        var service = new LogCollectorService("/run/audit.sock", "/var/log/audit", fileSystem, socketProvider);
        var cts = new CancellationTokenSource();

        // Act
        var serviceTask = service.RunAsync(cts.Token);

        // Simulate a client connection with data
        var payload = new System.Text.Json.Nodes.JsonObject
        {
            ["syscall"] = "openat",
            ["executable"] = "/bin/cat",
            ["arguments"] = new System.Text.Json.Nodes.JsonArray("/etc/passwd")
        };

        var testEvent = new AuditEvent(
            DateTimeOffset.UtcNow,
            "test-source",
            "syscall",
            payload
        );

        var json = JsonSerializer.Serialize(testEvent, AuditContext.Default.AuditEvent);
        socketProvider.Listener.SimulateConnection(json);

        // Allow some time for processing
        await Task.Delay(100, TestContext.Current.CancellationToken);
        cts.Cancel();

        try { await serviceTask; } catch (OperationCanceledException) { }

        // Assert
        Assert.Equal("/run/audit.sock", socketProvider.BoundPath);
        Assert.Contains("/var/log/audit", fileSystem.CreatedDirectories);
        
        // Verify log file content
        var logFile = fileSystem.Files.Keys.Single(k => k.StartsWith("/var/log/audit/session-"));
        var stream = fileSystem.Files[logFile];
        stream.Position = 0;
        using var reader = new StreamReader(stream);
        var line = await reader.ReadLineAsync(TestContext.Current.CancellationToken);
        
        Assert.NotNull(line);
        var savedEvent = JsonSerializer.Deserialize(line, AuditContext.Default.AuditEvent);
        
        Assert.NotNull(savedEvent);
        Assert.Equal(testEvent.Source, savedEvent.Source);
        Assert.Equal(testEvent.EventType, savedEvent.EventType);
        Assert.Equal(testEvent.Timestamp, savedEvent.Timestamp);
    }
}
