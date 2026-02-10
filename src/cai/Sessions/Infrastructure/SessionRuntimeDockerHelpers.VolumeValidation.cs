namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeDockerHelpers
{
    internal static bool IsValidVolumeName(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 255)
        {
            return false;
        }

        if (!char.IsLetterOrDigit(name[0]))
        {
            return false;
        }

        foreach (var ch in name)
        {
            if (!(char.IsLetterOrDigit(ch) || ch is '_' or '.' or '-'))
            {
                return false;
            }
        }

        return true;
    }
}
