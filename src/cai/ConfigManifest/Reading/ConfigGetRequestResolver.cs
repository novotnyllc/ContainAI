using ContainAI.Cli.Host.ConfigManifest;

namespace ContainAI.Cli.Host.ConfigManifest.Reading;

internal sealed class ConfigGetRequestResolver(ICaiConfigRuntime runtime)
{
    public ConfigGetRequestResolution Resolve(ConfigCommandRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Key))
        {
            return ConfigGetRequestResolution.Invalid("config get requires <key>");
        }

        var normalizedKey = runtime.NormalizeConfigKey(request.Key);
        var workspaceScope = runtime.ResolveWorkspaceScope(request, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            return ConfigGetRequestResolution.Invalid(workspaceScope.Error);
        }

        return new ConfigGetRequestResolution(normalizedKey, workspaceScope.Workspace, request.Global);
    }
}
