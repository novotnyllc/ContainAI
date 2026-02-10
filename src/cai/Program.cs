using ContainAI.Cli;
using ContainAI.Cli.Host;
using ContainAI.Cli.Host.AgentShims;

var invocationName = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]);
var manifestTomlParser = new ManifestTomlParser();
if (string.Equals(invocationName, "containai-docker", StringComparison.OrdinalIgnoreCase))
{
    return await ContainAiDockerProxy.RunAsync(args, Console.Out, Console.Error, CancellationToken.None).ConfigureAwait(false);
}

var shimDispatcher = new AgentShimDispatcher(
    new AgentShimDefinitionResolver(manifestTomlParser),
    new AgentShimBinaryResolver(),
    new AgentShimCommandLauncher(),
    Console.Error);

var shimExitCode = await shimDispatcher.TryRunAsync(invocationName, args, CancellationToken.None).ConfigureAwait(false);
if (shimExitCode.HasValue)
{
    return shimExitCode.Value;
}

var runtime = new CaiCommandRuntime(new AcpProxyRunner(), manifestTomlParser);

return await CaiCli.RunAsync(args, runtime).ConfigureAwait(false);
