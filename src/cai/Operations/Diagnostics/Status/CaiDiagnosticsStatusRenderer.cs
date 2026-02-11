namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsStatusRenderer
{
    private readonly TextWriter standardOutput;
    private readonly Func<string, string> escapeJson;

    public CaiDiagnosticsStatusRenderer(TextWriter standardOutput, Func<string, string> escapeJson)
    {
        this.standardOutput = standardOutput;
        this.escapeJson = escapeJson;
    }

    public Task RenderAsync(CaiDiagnosticsStatusReport report, bool outputJson, bool verbose)
        => outputJson
            ? RenderJsonAsync(report)
            : RenderTextAsync(report, verbose);

    private async Task RenderJsonAsync(CaiDiagnosticsStatusReport report)
    {
        var jsonFields = new List<string>
        {
            $"\"container\":\"{escapeJson(report.Container)}\"",
            $"\"status\":\"{escapeJson(report.Status)}\"",
            $"\"image\":\"{escapeJson(report.Image)}\"",
            $"\"context\":\"{escapeJson(report.Context)}\"",
        };

        if (!string.IsNullOrWhiteSpace(report.Uptime))
        {
            jsonFields.Add($"\"uptime\":\"{escapeJson(report.Uptime)}\"");
        }

        if (!string.IsNullOrWhiteSpace(report.MemoryUsage))
        {
            jsonFields.Add($"\"memory_usage\":\"{escapeJson(report.MemoryUsage)}\"");
        }

        if (!string.IsNullOrWhiteSpace(report.MemoryLimit))
        {
            jsonFields.Add($"\"memory_limit\":\"{escapeJson(report.MemoryLimit)}\"");
        }

        if (!string.IsNullOrWhiteSpace(report.CpuPercent))
        {
            jsonFields.Add($"\"cpu_percent\":\"{escapeJson(report.CpuPercent)}\"");
        }

        await standardOutput.WriteLineAsync("{" + string.Join(",", jsonFields) + "}").ConfigureAwait(false);
    }

    private async Task RenderTextAsync(CaiDiagnosticsStatusReport report, bool verbose)
    {
        await standardOutput.WriteLineAsync($"Container: {report.Container}").ConfigureAwait(false);
        await standardOutput.WriteLineAsync($"  Status: {report.Status}").ConfigureAwait(false);
        await standardOutput.WriteLineAsync($"  Image: {report.Image}").ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(report.Uptime))
        {
            await standardOutput.WriteLineAsync($"  Uptime: {report.Uptime}").ConfigureAwait(false);
        }

        if (verbose)
        {
            await standardOutput.WriteLineAsync($"  Context: {report.Context}").ConfigureAwait(false);
        }

        if (!string.IsNullOrWhiteSpace(report.MemoryUsage) && !string.IsNullOrWhiteSpace(report.MemoryLimit))
        {
            await standardOutput.WriteLineAsync($"  Memory: {report.MemoryUsage} / {report.MemoryLimit}").ConfigureAwait(false);
        }

        if (!string.IsNullOrWhiteSpace(report.CpuPercent))
        {
            await standardOutput.WriteLineAsync($"  CPU: {report.CpuPercent}").ConfigureAwait(false);
        }
    }
}
