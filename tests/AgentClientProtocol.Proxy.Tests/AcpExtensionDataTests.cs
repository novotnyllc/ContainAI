using System.Reflection;
using System.Text.Json;
using AgentClientProtocol.Proxy;
using AgentClientProtocol.Proxy.Protocol;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class AcpExtensionDataTests
{
    [Fact]
    public void MergeInto_WhenDestinationIsNull_Throws()
    {
        Assert.Throws<ArgumentNullException>(() => AcpExtensionData.MergeInto(destination: null!, source: null));
    }

    [Fact]
    public void MergeInto_WhenSourceIsNullOrEmpty_DoesNothing()
    {
        var destination = new Dictionary<string, JsonElement>(StringComparer.Ordinal)
        {
            ["existing"] = JsonSerializer.SerializeToElement("value"),
        };

        AcpExtensionData.MergeInto(destination, source: null);
        AcpExtensionData.MergeInto(destination, new Dictionary<string, JsonElement>());

        Assert.Single(destination);
        Assert.Equal("value", destination["existing"].GetString());
    }

    [Fact]
    public void MergeInto_ClonesValues()
    {
        using var sourceDoc = JsonDocument.Parse("""{"custom":{"name":"proxy"}}""");
        var source = new Dictionary<string, JsonElement>(StringComparer.Ordinal)
        {
            ["custom"] = sourceDoc.RootElement.GetProperty("custom").Clone(),
        };
        var destination = new Dictionary<string, JsonElement>(StringComparer.Ordinal);

        AcpExtensionData.MergeInto(destination, source);

        Assert.True(destination.ContainsKey("custom"));
        Assert.Equal("proxy", destination["custom"].GetProperty("name").GetString());
    }

    [Fact]
    public void TryGetValue_WithExistingTypedValue_ReturnsTrue()
    {
        var extensionData = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        AcpExtensionData.SetValue(
            extensionData,
            "scope",
            new SessionScopedParams { SessionId = "session-1" },
            AcpJsonContext.Default.SessionScopedParams);

        var found = AcpExtensionData.TryGetValue(
            extensionData,
            "scope",
            AcpJsonContext.Default.SessionScopedParams,
            out var scopedParams);

        Assert.True(found);
        Assert.NotNull(scopedParams);
        Assert.Equal("session-1", scopedParams.SessionId);
    }

    [Fact]
    public void TryGetValue_WithMissingOrNullValue_ReturnsFalse()
    {
        var extensionData = new Dictionary<string, JsonElement>(StringComparer.Ordinal)
        {
            ["nullValue"] = JsonSerializer.SerializeToElement<object?>(null),
        };

        var foundMissing = AcpExtensionData.TryGetValue(
            extensionData,
            "missing",
            AcpJsonContext.Default.SessionScopedParams,
            out var missingValue);

        var foundNull = AcpExtensionData.TryGetValue(
            extensionData,
            "nullValue",
            AcpJsonContext.Default.SessionScopedParams,
            out var nullValue);

        Assert.False(foundMissing);
        Assert.Null(missingValue);
        Assert.False(foundNull);
        Assert.Null(nullValue);
    }

    [Fact]
    public void TryGetValue_WithTypeMismatch_ReturnsFalse()
    {
        var extensionData = new Dictionary<string, JsonElement>(StringComparer.Ordinal)
        {
            ["scope"] = JsonSerializer.SerializeToElement(42),
        };

        var found = AcpExtensionData.TryGetValue(
            extensionData,
            "scope",
            AcpJsonContext.Default.SessionScopedParams,
            out var scopedParams);

        Assert.False(found);
        Assert.Null(scopedParams);
    }

    [Fact]
    public void TryGetValue_WithInvalidArguments_Throws()
    {
        var extensionData = new Dictionary<string, JsonElement>(StringComparer.Ordinal);

        Assert.Throws<ArgumentNullException>(() => AcpExtensionData.TryGetValue<SessionScopedParams>(
            extensionData: null!,
            "scope",
            AcpJsonContext.Default.SessionScopedParams,
            out var _));

        Assert.Throws<ArgumentException>(() => AcpExtensionData.TryGetValue(
            extensionData,
            "",
            AcpJsonContext.Default.SessionScopedParams,
            out var _));

        Assert.Throws<ArgumentNullException>(() => AcpExtensionData.TryGetValue<SessionScopedParams>(
            extensionData,
            "scope",
            typeInfo: null!,
            out var _));
    }

    [Fact]
    public void SetValue_WithInvalidArguments_Throws()
    {
        var extensionData = new Dictionary<string, JsonElement>(StringComparer.Ordinal);

        Assert.Throws<ArgumentNullException>(() => AcpExtensionData.SetValue(
            extensionData: null!,
            "scope",
            new SessionScopedParams(),
            AcpJsonContext.Default.SessionScopedParams));

        Assert.Throws<ArgumentException>(() => AcpExtensionData.SetValue(
            extensionData,
            "",
            new SessionScopedParams(),
            AcpJsonContext.Default.SessionScopedParams));

        Assert.Throws<ArgumentNullException>(() => AcpExtensionData.SetValue(
            extensionData,
            "scope",
            new SessionScopedParams(),
            typeInfo: null!));

        Assert.Throws<ArgumentNullException>(() => AcpExtensionData.SetValue(
            extensionData,
            "scope",
            (SessionScopedParams)null!,
            AcpJsonContext.Default.SessionScopedParams));
    }

    [Fact]
    public void CopySessionNewExtensions_WithNonObjectPayload_DoesNotMutateDestination()
    {
        var destination = new Dictionary<string, JsonElement>(StringComparer.Ordinal)
        {
            ["existing"] = JsonSerializer.SerializeToElement("value"),
        };
        var payload = JsonRpcData.FromJsonElement(JsonSerializer.SerializeToElement(42));

        var copyMethod = typeof(AcpProxy).GetMethod("CopySessionNewExtensions", BindingFlags.NonPublic | BindingFlags.Static);
        Assert.NotNull(copyMethod);

        copyMethod!.Invoke(null, [payload, destination]);

        Assert.Single(destination);
        Assert.Equal("value", destination["existing"].GetString());
    }
}
