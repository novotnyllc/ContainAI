namespace ContainAI.Cli.Host;

internal interface ICaiDoctorStatusWriter
{
    Task WriteAsync(bool outputJson, bool buildTemplates, CaiDoctorRuntimeProbeResult runtimeProbe, bool templateStatus);
}
