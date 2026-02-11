using System.Text;

namespace ContainAI.Cli.Host;

internal static class DockerProxyJsoncCommentStripper
{
    public static string Strip(string content)
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
}
