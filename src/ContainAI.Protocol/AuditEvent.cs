namespace ContainAI.Protocol;

using System.Text.Json.Nodes;

public record AuditEvent(
    DateTimeOffset Timestamp,
    string Source,
    string EventType,
    JsonNode? Payload
);
