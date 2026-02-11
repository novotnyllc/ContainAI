namespace ContainAI.Cli.Host;

internal sealed class CaiDoctorOperations
{
    private readonly ICaiDoctorLimaResetter limaResetter;
    private readonly ICaiDoctorRuntimeProbe runtimeProbe;
    private readonly ICaiDoctorTemplateValidator templateValidator;
    private readonly ICaiDoctorStatusWriter statusWriter;

    public CaiDoctorOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            new CaiDoctorLimaResetter(standardOutput, standardError),
            new CaiDoctorRuntimeProbe(),
            new CaiDoctorTemplateValidator(),
            new CaiDoctorStatusWriter(standardOutput))
    {
    }

    internal CaiDoctorOperations(
        ICaiDoctorLimaResetter caiDoctorLimaResetter,
        ICaiDoctorRuntimeProbe caiDoctorRuntimeProbe,
        ICaiDoctorTemplateValidator caiDoctorTemplateValidator,
        ICaiDoctorStatusWriter caiDoctorStatusWriter)
    {
        limaResetter = caiDoctorLimaResetter ?? throw new ArgumentNullException(nameof(caiDoctorLimaResetter));
        runtimeProbe = caiDoctorRuntimeProbe ?? throw new ArgumentNullException(nameof(caiDoctorRuntimeProbe));
        templateValidator = caiDoctorTemplateValidator ?? throw new ArgumentNullException(nameof(caiDoctorTemplateValidator));
        statusWriter = caiDoctorStatusWriter ?? throw new ArgumentNullException(nameof(caiDoctorStatusWriter));
    }

    public async Task<int> RunDoctorAsync(
        bool outputJson,
        bool buildTemplates,
        bool resetLima,
        CancellationToken cancellationToken)
    {
        var resetExitCode = await limaResetter.TryResetLimaAsync(resetLima, cancellationToken).ConfigureAwait(false);
        if (resetExitCode.HasValue)
        {
            return resetExitCode.Value;
        }

        var runtimeStatus = await runtimeProbe.ProbeAsync(cancellationToken).ConfigureAwait(false);
        var templateStatus = await templateValidator.ResolveTemplateStatusAsync(buildTemplates, cancellationToken).ConfigureAwait(false);

        await statusWriter.WriteAsync(outputJson, buildTemplates, runtimeStatus, templateStatus).ConfigureAwait(false);

        return runtimeStatus.DockerCli && runtimeStatus.ContextExists && runtimeStatus.DockerInfo && runtimeStatus.SysboxRuntime && templateStatus
            ? 0
            : 1;
    }
}
