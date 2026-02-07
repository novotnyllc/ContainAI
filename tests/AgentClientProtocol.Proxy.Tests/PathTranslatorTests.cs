using System.Text.Json.Nodes;
using AgentClientProtocol.Proxy.PathTranslation;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public class PathTranslatorTests
{
    private const string HostWorkspace = "/home/user/projects/myapp";
    private const string ContainerWorkspace = "/home/agent/workspace";

    [Fact]
    public void TranslateToContainer_ExactMatch_ReturnsContainerPath()
    {
        var translator = new PathTranslator(HostWorkspace);

        var result = translator.TranslateToContainer(HostWorkspace);

        Assert.Equal(ContainerWorkspace, result);
    }

    [Fact]
    public void TranslateToContainer_Descendant_ReturnsTranslatedPath()
    {
        var translator = new PathTranslator(HostWorkspace);

        var result = translator.TranslateToContainer("/home/user/projects/myapp/src/lib/utils.js");

        Assert.Equal("/home/agent/workspace/src/lib/utils.js", result);
    }

    [Fact]
    public void TranslateToContainer_OutsideWorkspace_ReturnsOriginal()
    {
        var translator = new PathTranslator(HostWorkspace);

        var result = translator.TranslateToContainer("/home/user/other/file.txt");

        Assert.Equal("/home/user/other/file.txt", result);
    }

    [Fact]
    public void TranslateToContainer_RelativePath_ReturnsOriginal()
    {
        var translator = new PathTranslator(HostWorkspace);

        var result = translator.TranslateToContainer("src/file.txt");

        Assert.Equal("src/file.txt", result);
    }

    [Fact]
    public void TranslateToHost_ExactMatch_ReturnsHostPath()
    {
        var translator = new PathTranslator(HostWorkspace);

        var result = translator.TranslateToHost(ContainerWorkspace);

        Assert.Equal(HostWorkspace, result);
    }

    [Fact]
    public void TranslateToHost_Descendant_ReturnsTranslatedPath()
    {
        var translator = new PathTranslator(HostWorkspace);

        var result = translator.TranslateToHost("/home/agent/workspace/src/lib/utils.js");

        var expected = Path.Combine(HostWorkspace, "src", "lib", "utils.js");
        Assert.Equal(expected, result);
    }

    [Fact]
    public void TranslateToHost_OutsideWorkspace_ReturnsOriginal()
    {
        var translator = new PathTranslator(HostWorkspace);

        var result = translator.TranslateToHost("/tmp/file.txt");

        Assert.Equal("/tmp/file.txt", result);
    }

    [Fact]
    public void TranslateMcpServers_ObjectFormat_TranslatesPaths()
    {
        var translator = new PathTranslator(HostWorkspace);
        var mcpServers = new JsonObject
        {
            ["filesystem"] = new JsonObject
            {
                ["command"] = "npx",
                ["args"] = new JsonArray(
                    "-y",
                    "@modelcontextprotocol/server-filesystem",
                    (JsonNode)"/home/user/projects/myapp/src"
                )
            }
        };

        var result = translator.TranslateMcpServers(mcpServers);

        var resultObj = Assert.IsType<JsonObject>(result);
        var filesystem = Assert.IsType<JsonObject>(resultObj["filesystem"]);
        var args = Assert.IsType<JsonArray>(filesystem["args"]);
        Assert.Equal(3, args.Count);
        Assert.Equal("-y", args[0]?.GetValue<string>());
        Assert.Equal("@modelcontextprotocol/server-filesystem", args[1]?.GetValue<string>());
        Assert.Equal("/home/agent/workspace/src", args[2]?.GetValue<string>());
    }

    [Fact]
    public void TranslateMcpServers_ArrayFormat_TranslatesPaths()
    {
        var translator = new PathTranslator(HostWorkspace);
        var mcpServers = new JsonArray
        {
            new JsonObject
            {
                ["name"] = "filesystem",
                ["command"] = "npx",
                ["args"] = new JsonArray(
                    "-y",
                    "@modelcontextprotocol/server-filesystem",
                    (JsonNode)"/home/user/projects/myapp/data"
                )
            }
        };

        var result = translator.TranslateMcpServers(mcpServers);

        var resultArray = Assert.IsType<JsonArray>(result);
        Assert.Single(resultArray);
        var server = Assert.IsType<JsonObject>(resultArray[0]);
        var args = Assert.IsType<JsonArray>(server["args"]);
        Assert.Equal("/home/agent/workspace/data", args[2]?.GetValue<string>());
    }

    [Fact]
    public void TranslateMcpServers_MixedPathsAndFlags_OnlyTranslatesAbsolutePaths()
    {
        var translator = new PathTranslator(HostWorkspace);
        var mcpServers = new JsonObject
        {
            ["tool"] = new JsonObject
            {
                ["command"] = "some-tool",
                ["args"] = new JsonArray(
                    "--config",
                    (JsonNode)"/home/user/projects/myapp/config.json",
                    "--output",
                    "relative/path",
                    (JsonNode)"/outside/workspace/file.txt"
                )
            }
        };

        var result = translator.TranslateMcpServers(mcpServers);

        var resultObj = Assert.IsType<JsonObject>(result);
        var tool = Assert.IsType<JsonObject>(resultObj["tool"]);
        var args = Assert.IsType<JsonArray>(tool["args"]);

        Assert.Equal("--config", args[0]?.GetValue<string>());
        Assert.Equal("/home/agent/workspace/config.json", args[1]?.GetValue<string>()); // Translated
        Assert.Equal("--output", args[2]?.GetValue<string>());
        Assert.Equal("relative/path", args[3]?.GetValue<string>()); // Not translated (relative)
        Assert.Equal("/outside/workspace/file.txt", args[4]?.GetValue<string>()); // Not translated (outside)
    }

    [Theory]
    [InlineData("/home/user/projects/myapp/", ContainerWorkspace)] // Trailing slash
    [InlineData("/home/user/projects/myapp", ContainerWorkspace)]  // No trailing slash
    public void TranslateToContainer_HandlesTrailingSlashes(string input, string expected)
    {
        var translator = new PathTranslator(HostWorkspace);

        var result = translator.TranslateToContainer(input);

        Assert.Equal(expected, result);
    }

    [Fact]
    public void TranslateToContainer_InvalidPath_ReturnsOriginal()
    {
        var translator = new PathTranslator(HostWorkspace);
        var invalidPath = "/home/user/projects/myapp/\0bad";

        var result = translator.TranslateToContainer(invalidPath);

        Assert.Equal(invalidPath, result);
    }

    [Fact]
    public void TranslateToHost_RelativePath_ReturnsOriginal()
    {
        var translator = new PathTranslator(HostWorkspace);

        var result = translator.TranslateToHost("relative/path");

        Assert.Equal("relative/path", result);
    }

    [Fact]
    public void TranslateMcpServers_UnknownNodeFormat_PassesThroughClone()
    {
        var translator = new PathTranslator(HostWorkspace);
        var input = JsonValue.Create("raw-value")!;

        var result = translator.TranslateMcpServers(input);

        Assert.Equal("raw-value", result.GetValue<string>());
        Assert.NotSame(input, result);
    }

    [Fact]
    public void TranslateMcpServers_ArrayFormat_PreservesNonObjectEntries()
    {
        var translator = new PathTranslator(HostWorkspace);
        var mcpServers = new JsonArray
        {
            JsonValue.Create("literal-entry"),
            new JsonObject
            {
                ["name"] = "filesystem",
                ["args"] = new JsonArray((JsonNode)"/home/user/projects/myapp/docs"),
            },
        };

        var result = Assert.IsType<JsonArray>(translator.TranslateMcpServers(mcpServers));
        Assert.Equal("literal-entry", result[0]?.GetValue<string>());
        Assert.Equal("/home/agent/workspace/docs", result[1]?["args"]?[0]?.GetValue<string>());
    }

    [Fact]
    public void TranslateMcpServers_ObjectFormat_PreservesNonObjectServerConfig()
    {
        var translator = new PathTranslator(HostWorkspace);
        var mcpServers = new JsonObject
        {
            ["server-name"] = JsonValue.Create("inline-config"),
        };

        var result = Assert.IsType<JsonObject>(translator.TranslateMcpServers(mcpServers));
        Assert.Equal("inline-config", result["server-name"]?.GetValue<string>());
    }

    [Fact]
    public void TranslateMcpServers_ArgsArray_PreservesNonStringValues()
    {
        var translator = new PathTranslator(HostWorkspace);
        var mcpServers = new JsonObject
        {
            ["filesystem"] = new JsonObject
            {
                ["args"] = new JsonArray(
                    JsonValue.Create(42),
                    JsonValue.Create(true),
                    JsonValue.Create("/home/user/projects/myapp/src")),
            },
        };

        var result = Assert.IsType<JsonObject>(translator.TranslateMcpServers(mcpServers));
        var args = Assert.IsType<JsonArray>(result["filesystem"]?["args"]);
        Assert.Equal(42, args[0]?.GetValue<int>());
        Assert.True(args[1]?.GetValue<bool>());
        Assert.Equal("/home/agent/workspace/src", args[2]?.GetValue<string>());
    }
}
