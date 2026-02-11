using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetParsingValidationService
{
    public string? TryReadWorkspaceStringProperty(string workspaceStateJson, string propertyName)
    {
        using var json = JsonDocument.Parse(workspaceStateJson);
        if (json.RootElement.ValueKind != JsonValueKind.Object ||
            !json.RootElement.TryGetProperty(propertyName, out var propertyValue))
        {
            return null;
        }

        var value = propertyValue.GetString();
        return string.IsNullOrWhiteSpace(value) ? null : value;
    }
}
