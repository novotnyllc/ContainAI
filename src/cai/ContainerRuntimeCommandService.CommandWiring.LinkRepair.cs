using System.Text.Json;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private async Task<int> RunLinkRepairCoreAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
    {
        var parsed = optionParser.ParseLinkRepairCommandOptions(options);
        var mode = parsed.Mode;
        var quiet = parsed.Quiet;
        var builtinSpecPath = parsed.BuiltinSpecPath;
        var userSpecPath = parsed.UserSpecPath;
        var checkedAtFilePath = parsed.CheckedAtFilePath;

        if (!File.Exists(builtinSpecPath))
        {
            await stderr.WriteLineAsync($"ERROR: Built-in link spec not found: {builtinSpecPath}").ConfigureAwait(false);
            return 1;
        }

        var stats = new LinkRepairStats();
        try
        {
            await ProcessLinkSpecAsync(builtinSpecPath, mode, quiet, "built-in links", stats, cancellationToken).ConfigureAwait(false);
            if (File.Exists(userSpecPath))
            {
                try
                {
                    await ProcessLinkSpecAsync(userSpecPath, mode, quiet, "user-defined links", stats, cancellationToken).ConfigureAwait(false);
                }
                catch (InvalidOperationException ex)
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
                catch (IOException ex)
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
                catch (UnauthorizedAccessException ex)
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
                catch (JsonException ex)
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
                catch (ArgumentException ex)
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
                catch (NotSupportedException ex)
                {
                    await WriteUserLinkSpecWarningAsync(stats, ex).ConfigureAwait(false);
                }
            }

            if (mode == LinkRepairMode.Fix && stats.Errors == 0)
            {
                await WriteTimestampAsync(checkedAtFilePath).ConfigureAwait(false);
                await LogInfoAsync(quiet, "Updated links-checked-at timestamp").ConfigureAwait(false);
            }

            await WriteLinkRepairSummaryAsync(mode, stats, quiet).ConfigureAwait(false);
            if (stats.Errors > 0)
            {
                return 1;
            }

            if (mode == LinkRepairMode.Check && (stats.Broken + stats.Missing) > 0)
            {
                return 1;
            }

            return 0;
        }
        catch (InvalidOperationException ex)
        {
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
        }
        catch (IOException ex)
        {
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
        }
        catch (UnauthorizedAccessException ex)
        {
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
        }
        catch (ArgumentException ex)
        {
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
        }
        catch (NotSupportedException ex)
        {
            return await WriteLinkRepairErrorAsync(ex).ConfigureAwait(false);
        }
    }
}
