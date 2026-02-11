namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal static class ContainerRuntimeEnvironmentVariableKeyValidator
{
    public static bool IsValid(string key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            return false;
        }

        if (!(char.IsLetter(key[0]) || key[0] == '_'))
        {
            return false;
        }

        for (var index = 1; index < key.Length; index++)
        {
            var c = key[index];
            if (!(char.IsLetterOrDigit(c) || c == '_'))
            {
                return false;
            }
        }

        return true;
    }
}
