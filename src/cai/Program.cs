using ContainAI.Cli;
using ContainAI.Cli.Host;

var scriptResolver = new DefaultContainAiScriptResolver();
var legacyBridge = new LegacyContainAiBridge(scriptResolver);
var runtime = new CaiCommandRuntime(legacyBridge, new AcpProxyRunner());

return await CaiCli.RunAsync(args, runtime);
