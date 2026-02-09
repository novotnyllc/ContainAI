using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal interface IDockerProxyArgumentParser
{
    DockerProxyWrapperFlags ParseWrapperFlags(IReadOnlyList<string> args);

    DevcontainerLabels ExtractDevcontainerLabels(IReadOnlyList<string> args);

    bool IsContainerCreateCommand(IReadOnlyList<string> args);

    string SanitizeWorkspaceName(string value);

    string? GetFirstSubcommand(IReadOnlyList<string> args);

    string? GetContainerNameArg(IReadOnlyList<string> args, string subcommand);

    List<string> PrependContext(string contextName, IReadOnlyList<string> args);
}

internal interface IDevcontainerFeatureSettingsParser
{
    string StripJsoncComments(string content);

    bool TryReadFeatureSettings(string configFile, TextWriter stderr, out FeatureSettings settings);

    bool IsValidVolumeName(string volume);
}

internal sealed partial class DockerProxyArgumentParser : IDockerProxyArgumentParser
{
    public DockerProxyWrapperFlags ParseWrapperFlags(IReadOnlyList<string> args)
    {
        var dockerArgs = new List<string>(args.Count);
        var verbose = false;
        var quiet = false;

        foreach (var arg in args)
        {
            if (string.Equals(arg, "--verbose", StringComparison.Ordinal))
            {
                verbose = true;
                continue;
            }

            if (string.Equals(arg, "--quiet", StringComparison.Ordinal))
            {
                quiet = true;
                continue;
            }

            dockerArgs.Add(arg);
        }

        return new DockerProxyWrapperFlags(dockerArgs, verbose, quiet);
    }

    public DevcontainerLabels ExtractDevcontainerLabels(IReadOnlyList<string> args)
    {
        string? configFile = null;
        string? localFolder = null;

        for (var index = 0; index < args.Count; index++)
        {
            var token = args[index];
            if (string.Equals(token, "--label", StringComparison.Ordinal) && index + 1 < args.Count)
            {
                ParseLabel(args[index + 1], ref configFile, ref localFolder);
                index++;
                continue;
            }

            if (token.StartsWith("--label=", StringComparison.Ordinal))
            {
                ParseLabel(token[8..], ref configFile, ref localFolder);
            }
        }

        return new DevcontainerLabels(configFile, localFolder);
    }

    public bool IsContainerCreateCommand(IReadOnlyList<string> args)
    {
        var firstToken = string.Empty;
        var secondToken = string.Empty;

        foreach (var arg in args)
        {
            if (arg.StartsWith('-'))
            {
                continue;
            }

            if (string.IsNullOrEmpty(firstToken))
            {
                firstToken = arg;
                continue;
            }

            secondToken = arg;
            break;
        }

        if (string.Equals(firstToken, "run", StringComparison.Ordinal) ||
            string.Equals(firstToken, "create", StringComparison.Ordinal))
        {
            return true;
        }

        return string.Equals(firstToken, "container", StringComparison.Ordinal) &&
               (string.Equals(secondToken, "run", StringComparison.Ordinal) ||
                string.Equals(secondToken, "create", StringComparison.Ordinal));
    }

    public string SanitizeWorkspaceName(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "workspace";
        }

        var replaced = NonWorkspaceCharacterRegex().Replace(value, "-");
        replaced = MultiHyphenRegex().Replace(replaced, "-").Trim('-');
        return string.IsNullOrWhiteSpace(replaced) ? "workspace" : replaced;
    }

    public string? GetFirstSubcommand(IReadOnlyList<string> args)
    {
        foreach (var arg in args)
        {
            if (!arg.StartsWith('-'))
            {
                return arg;
            }
        }

        return null;
    }

    public string? GetContainerNameArg(IReadOnlyList<string> args, string subcommand)
    {
        var seenSubcommand = false;
        foreach (var arg in args)
        {
            if (!seenSubcommand)
            {
                if (string.Equals(arg, subcommand, StringComparison.Ordinal))
                {
                    seenSubcommand = true;
                }

                continue;
            }

            if (!arg.StartsWith('-'))
            {
                return arg;
            }
        }

        return null;
    }

    public List<string> PrependContext(string contextName, IReadOnlyList<string> args)
    {
        var dockerArgs = new List<string>(args.Count + 2)
        {
            "--context",
            contextName,
        };

        dockerArgs.AddRange(args);
        return dockerArgs;
    }

    private static void ParseLabel(string labelToken, ref string? configFile, ref string? localFolder)
    {
        if (labelToken.StartsWith("devcontainer.config_file=", StringComparison.Ordinal))
        {
            configFile = labelToken[25..];
            return;
        }

        if (labelToken.StartsWith("devcontainer.local_folder=", StringComparison.Ordinal))
        {
            localFolder = labelToken[26..];
        }
    }

    [GeneratedRegex("[^A-Za-z0-9._-]", RegexOptions.Compiled)]
    private static partial Regex NonWorkspaceCharacterRegex();

    [GeneratedRegex("-{2,}", RegexOptions.Compiled)]
    private static partial Regex MultiHyphenRegex();
}

internal sealed partial class DevcontainerFeatureSettingsParser : IDevcontainerFeatureSettingsParser
{
    private readonly ContainAiDockerProxyOptions options;

    public DevcontainerFeatureSettingsParser(ContainAiDockerProxyOptions options) => this.options = options;

    public string StripJsoncComments(string content)
    {
        var builder = new StringBuilder(content.Length);
        var inString = false;
        var escape = false;

        for (var index = 0; index < content.Length; index++)
        {
            var current = content[index];

            if (escape)
            {
                builder.Append(current);
                escape = false;
                continue;
            }

            if (current == '\\' && inString)
            {
                builder.Append(current);
                escape = true;
                continue;
            }

            if (current == '"')
            {
                inString = !inString;
                builder.Append(current);
                continue;
            }

            if (!inString && current == '/' && index + 1 < content.Length)
            {
                var next = content[index + 1];
                if (next == '/')
                {
                    while (index < content.Length && content[index] != '\n')
                    {
                        index++;
                    }

                    if (index < content.Length)
                    {
                        builder.Append('\n');
                    }

                    continue;
                }

                if (next == '*')
                {
                    index += 2;
                    while (index + 1 < content.Length && !(content[index] == '*' && content[index + 1] == '/'))
                    {
                        if (content[index] == '\n')
                        {
                            builder.Append('\n');
                        }

                        index++;
                    }

                    index++;
                    continue;
                }
            }

            builder.Append(current);
        }

        return builder.ToString();
    }

    public bool TryReadFeatureSettings(string configFile, TextWriter stderr, out FeatureSettings settings)
    {
        settings = FeatureSettings.Default(options.DefaultDataVolume);

        if (!File.Exists(configFile))
        {
            return false;
        }

        try
        {
            var raw = File.ReadAllText(configFile);
            var stripped = StripJsoncComments(raw);
            using var document = JsonDocument.Parse(stripped);
            if (!document.RootElement.TryGetProperty("features", out var features) || features.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            foreach (var feature in features.EnumerateObject())
            {
                if (!feature.Name.Contains("containai", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var featureElement = feature.Value;
                var dataVolume = options.DefaultDataVolume;
                if (featureElement.ValueKind == JsonValueKind.Object &&
                    featureElement.TryGetProperty("dataVolume", out var dataVolumeElement) &&
                    dataVolumeElement.ValueKind == JsonValueKind.String)
                {
                    var candidate = dataVolumeElement.GetString();
                    if (!string.IsNullOrWhiteSpace(candidate) && IsValidVolumeName(candidate!))
                    {
                        dataVolume = candidate!;
                    }
                }

                var enableCredentials = false;
                if (featureElement.ValueKind == JsonValueKind.Object && featureElement.TryGetProperty("enableCredentials", out var credentialsElement))
                {
                    enableCredentials = credentialsElement.ValueKind switch
                    {
                        JsonValueKind.True => true,
                        JsonValueKind.False => false,
                        JsonValueKind.String when bool.TryParse(credentialsElement.GetString(), out var parsed) => parsed,
                        _ => false,
                    };
                }

                var remoteUser = "vscode";
                if (featureElement.ValueKind == JsonValueKind.Object &&
                    featureElement.TryGetProperty("remoteUser", out var remoteUserElement) &&
                    remoteUserElement.ValueKind == JsonValueKind.String)
                {
                    var candidate = remoteUserElement.GetString();
                    if (!string.IsNullOrWhiteSpace(candidate) &&
                        !string.Equals(candidate, "auto", StringComparison.Ordinal) &&
                        UnixUsernameRegex().IsMatch(candidate!))
                    {
                        remoteUser = candidate!;
                    }
                }

                if (document.RootElement.TryGetProperty("remoteUser", out var topLevelRemoteUserElement) &&
                    topLevelRemoteUserElement.ValueKind == JsonValueKind.String)
                {
                    var candidate = topLevelRemoteUserElement.GetString();
                    if (!string.IsNullOrWhiteSpace(candidate) &&
                        !string.Equals(candidate, "auto", StringComparison.Ordinal) &&
                        UnixUsernameRegex().IsMatch(candidate!))
                    {
                        remoteUser = candidate!;
                    }
                }

                settings = new FeatureSettings(true, dataVolume, enableCredentials, remoteUser);
                return true;
            }

            return false;
        }
        catch (IOException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (UnauthorizedAccessException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (JsonException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (ArgumentException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
        catch (NotSupportedException ex)
        {
            stderr.WriteLine($"[cai-docker] Warning: failed to parse devcontainer config: {ex.Message}");
            return false;
        }
    }

    public bool IsValidVolumeName(string volume)
    {
        if (!VolumeNameRegex().IsMatch(volume))
        {
            return false;
        }

        if (volume.Contains(':', StringComparison.Ordinal) ||
            volume.Contains('/', StringComparison.Ordinal) ||
            volume.Contains('~', StringComparison.Ordinal))
        {
            return false;
        }

        return !string.Equals(volume, ".", StringComparison.Ordinal) && !string.Equals(volume, "..", StringComparison.Ordinal);
    }

    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex VolumeNameRegex();

    [GeneratedRegex("^[a-z_][a-z0-9_-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex UnixUsernameRegex();
}

internal readonly record struct DockerProxyWrapperFlags(IReadOnlyList<string> DockerArgs, bool Verbose, bool Quiet);

internal readonly record struct DevcontainerLabels(string? ConfigFile, string? LocalFolder);

internal readonly record struct DockerProxyProcessResult(int ExitCode, string StandardOutput, string StandardError);

internal sealed record ContainAiDockerProxyOptions(string DefaultContext, string DefaultDataVolume, int SshPortRangeStart, int SshPortRangeEnd)
{
    public static ContainAiDockerProxyOptions Default { get; } = new("containai-docker", "containai-data", 2400, 2499);
}

internal readonly record struct FeatureSettings(bool HasContainAiFeature, string DataVolume, bool EnableCredentials, string RemoteUser)
{
    public static FeatureSettings Default(string defaultDataVolume) => new(false, defaultDataVolume, false, "vscode");
}
