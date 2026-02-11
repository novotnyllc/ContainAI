using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsAndSetupOperations
{
    private readonly TextWriter stdout;
    private readonly CaiDiagnosticsStatusOperations statusOperations;
    private readonly CaiDoctorOperations doctorOperations;
    private readonly CaiSetupOperations setupOperations;
    private readonly CaiDoctorFixOperations doctorFixOperations;

    public CaiDiagnosticsAndSetupOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<bool, CancellationToken, Task<int>> runSshCleanupAsync)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));

        var templateRestoreOperations = new CaiTemplateRestoreOperations(standardOutput, standardError);
        statusOperations = new CaiDiagnosticsStatusOperations(standardOutput, standardError);
        doctorOperations = new CaiDoctorOperations(standardOutput, standardError);
        setupOperations = new CaiSetupOperations(
            standardOutput,
            standardError,
            templateRestoreOperations,
            cancellationToken => doctorOperations.RunDoctorAsync(
                outputJson: false,
                buildTemplates: false,
                resetLima: false,
                cancellationToken));
        doctorFixOperations = new CaiDoctorFixOperations(
            standardOutput,
            standardError,
            runSshCleanupAsync,
            templateRestoreOperations);
    }

    public Task<int> RunStatusAsync(
        bool outputJson,
        bool verbose,
        string? workspace,
        string? container,
        CancellationToken cancellationToken)
        => statusOperations.RunStatusAsync(outputJson, verbose, workspace, container, cancellationToken);

    public Task<int> RunDoctorAsync(
        bool outputJson,
        bool buildTemplates,
        bool resetLima,
        CancellationToken cancellationToken)
        => doctorOperations.RunDoctorAsync(outputJson, buildTemplates, resetLima, cancellationToken);

    public Task<int> RunSetupAsync(
        bool dryRun,
        bool verbose,
        bool skipTemplates,
        bool showHelp,
        CancellationToken cancellationToken)
        => setupOperations.RunSetupAsync(dryRun, verbose, skipTemplates, showHelp, cancellationToken);

    public Task<int> RunDoctorFixAsync(
        bool fixAll,
        bool dryRun,
        string? target,
        string? targetArg,
        CancellationToken cancellationToken)
        => doctorFixOperations.RunDoctorFixAsync(fixAll, dryRun, target, targetArg, cancellationToken);

    public static async Task<int> RunDockerAsync(IReadOnlyList<string> dockerArguments, CancellationToken cancellationToken)
    {
        var executable = CaiRuntimePathResolutionHelpers.IsExecutableOnPath("containai-docker")
            ? "containai-docker"
            : "docker";

        var dockerArgs = new List<string>();
        if (string.Equals(executable, "docker", StringComparison.Ordinal))
        {
            var context = await CaiRuntimeDockerHelpers.ResolveDockerContextAsync(cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(context))
            {
                dockerArgs.Add("--context");
                dockerArgs.Add(context);
            }
        }

        foreach (var argument in dockerArguments)
        {
            dockerArgs.Add(argument);
        }

        return await CaiRuntimeProcessRunner.RunProcessInteractiveAsync(executable, dockerArgs, cancellationToken).ConfigureAwait(false);
    }

    public async Task<int> RunVersionAsync(bool json, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var versionInfo = InstallMetadata.ResolveVersionInfo();
        var installType = InstallMetadata.GetInstallTypeLabel(versionInfo.InstallType);

        if (json)
        {
            await stdout.WriteLineAsync($"{{\"version\":\"{versionInfo.Version}\",\"install_type\":\"{installType}\",\"install_dir\":\"{CaiRuntimeJsonEscaper.EscapeJson(versionInfo.InstallDir)}\"}}").ConfigureAwait(false);
            return 0;
        }

        await stdout.WriteLineAsync(versionInfo.Version).ConfigureAwait(false);
        return 0;
    }
}
