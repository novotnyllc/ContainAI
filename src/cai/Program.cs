using ContainAI.Cli;
using ContainAI.Cli.Host;

var invocationName = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]);
var manifestTomlParser = new ManifestTomlParser();
if (string.Equals(invocationName, "containai-docker", StringComparison.OrdinalIgnoreCase))
{
    return await ContainAiDockerProxy.RunAsync(args, Console.Out, Console.Error, CancellationToken.None).ConfigureAwait(false);
}

var shimExitCode = await AgentShimDispatcher.TryRunAsync(invocationName, args, manifestTomlParser, CancellationToken.None).ConfigureAwait(false);
if (shimExitCode.HasValue)
{
    return shimExitCode.Value;
}

var runtime = new CaiCommandRuntime(new AcpProxyRunner(), manifestTomlParser);

return await CaiCli.RunAsync(args, runtime).ConfigureAwait(false);
