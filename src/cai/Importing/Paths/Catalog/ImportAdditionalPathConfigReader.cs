using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathConfigReader
{
    Task<IReadOnlyList<string>> ReadRawAdditionalPathsAsync(
        string configPath,
        bool verbose,
        CancellationToken cancellationToken);
}

internal sealed class ImportAdditionalPathConfigReader : IImportAdditionalPathConfigReader
{
    private readonly TextWriter standardError;
    private readonly IImportAdditionalPathJsonReader additionalPathJsonReader;

    public ImportAdditionalPathConfigReader(TextWriter standardError)
        : this(standardError, new ImportAdditionalPathJsonReader(standardError))
    {
    }

    internal ImportAdditionalPathConfigReader(
        TextWriter standardError,
        IImportAdditionalPathJsonReader additionalPathJsonReader)
    {
        this.standardError = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.additionalPathJsonReader = additionalPathJsonReader ?? throw new ArgumentNullException(nameof(additionalPathJsonReader));
    }

    public async Task<IReadOnlyList<string>> ReadRawAdditionalPathsAsync(
        string configPath,
        bool verbose,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(configPath);

        if (!File.Exists(configPath))
        {
            return [];
        }

        var result = await CaiRuntimeParseAndTimeHelpers
            .RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken)
            .ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            if (verbose && !string.IsNullOrWhiteSpace(result.StandardError))
            {
                await standardError.WriteLineAsync(result.StandardError.Trim()).ConfigureAwait(false);
            }

            return [];
        }

        return await additionalPathJsonReader.ReadRawAdditionalPathsAsync(result.StandardOutput, verbose).ConfigureAwait(false);
    }
}
