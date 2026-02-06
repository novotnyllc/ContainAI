using ContainAI.Cli;
using ContainAI.Cli.Host;

var scriptResolver = new DefaultContainAiScriptResolver();
var legacyBridge = new LegacyContainAiBridge(scriptResolver);
var runtimeService = new CommandRuntimeService();
var runtime = new CaiCommandRuntime(legacyBridge, runtimeService, new AcpProxyRunner());

return await CaiCli.RunAsync(args, runtime);
