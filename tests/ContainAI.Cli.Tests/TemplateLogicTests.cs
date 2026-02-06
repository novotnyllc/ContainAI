using System.Security.Cryptography;
using System.Text;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed class TemplateLogicTests
{
    [Fact]
    public async Task TemplateDirectory_UsesHomeConfigPath()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-template-home");
        var homePath = temp.Path;
        var cancellationToken = TestContext.Current.CancellationToken;
        var templateLibraryPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/template.sh");

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            source {ShellTestSupport.ShellQuote(templateLibraryPath)}
            _cai_get_template_dir
            """,
            environment: new Dictionary<string, string?> { ["HOME"] = homePath },
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        Assert.Equal(Path.Combine(homePath, ".config/containai/templates"), result.StdOut.Trim());
    }

    [Fact]
    public async Task TemplatePath_ResolvesDefaultAndCustomNames()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-template-paths");
        var homePath = temp.Path;
        var cancellationToken = TestContext.Current.CancellationToken;
        var templateLibraryPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/template.sh");

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            source {ShellTestSupport.ShellQuote(templateLibraryPath)}
            printf '%s\n' "$(_cai_get_template_path)"
            _cai_get_template_path "my-custom-template"
            """,
            environment: new Dictionary<string, string?> { ["HOME"] = homePath },
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        var lines = result.StdOut.Trim().Split('\n', StringSplitOptions.RemoveEmptyEntries);
        Assert.Equal(2, lines.Length);
        Assert.Equal(Path.Combine(homePath, ".config/containai/templates/default/Dockerfile"), lines[0]);
        Assert.Equal(Path.Combine(homePath, ".config/containai/templates/my-custom-template/Dockerfile"), lines[1]);
    }

    [Theory]
    [InlineData("default", true)]
    [InlineData("my-template", true)]
    [InlineData("template_v1", true)]
    [InlineData("template.1", true)]
    [InlineData("a1b2c3", true)]
    [InlineData("", false)]
    [InlineData("../etc", false)]
    [InlineData("a/b", false)]
    [InlineData("Template", false)]
    [InlineData("UPPER", false)]
    [InlineData("mixedCase", false)]
    [InlineData("in valid", false)]
    [InlineData("name@123", false)]
    [InlineData("_invalid", false)]
    [InlineData("-invalid", false)]
    [InlineData(".invalid", false)]
    public async Task TemplateNameValidation_MatchesShellRules(string templateName, bool expectedValid)
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var templateLibraryPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/template.sh");

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            source {ShellTestSupport.ShellQuote(templateLibraryPath)}
            _cai_validate_template_name {ShellTestSupport.ShellQuote(templateName)}
            """,
            cancellationToken: cancellationToken);

        Assert.Equal(expectedValid, result.ExitCode == 0);
    }

    [Fact]
    public async Task TemplatePath_RejectsInvalidTemplateName()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var templateLibraryPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/template.sh");

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            source {ShellTestSupport.ShellQuote(templateLibraryPath)}
            _cai_get_template_path "../etc"
            """,
            cancellationToken: cancellationToken);

        Assert.NotEqual(0, result.ExitCode);
    }

    [Fact]
    public async Task TemplateFingerprint_ComputesSha256ForTemplateDockerfile()
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-template-fingerprint");
        var templateDir = Path.Combine(temp.Path, "templates/default");
        Directory.CreateDirectory(templateDir);

        var dockerfilePath = Path.Combine(templateDir, "Dockerfile");
        const string dockerfile = "FROM ghcr.io/novotnyllc/containai:latest\nUSER agent\n";
        await File.WriteAllTextAsync(dockerfilePath, dockerfile, TestContext.Current.CancellationToken);

        var cancellationToken = TestContext.Current.CancellationToken;
        var templateLibraryPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/template.sh");

        var result = await ShellTestSupport.RunBashAsync(
            $"""
            source {ShellTestSupport.ShellQuote(templateLibraryPath)}
            _CAI_TEMPLATE_DIR={ShellTestSupport.ShellQuote(Path.Combine(temp.Path, "templates"))}
            _cai_template_fingerprint "default"
            """,
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);
        Assert.Equal(ComputeSha256(dockerfile), result.StdOut.Trim());
    }

    [Fact]
    public async Task TemplateRebuildPrompt_SkipsWhenFingerprintUnchanged()
    {
        var (exitCode, promptCalls) = await RunTemplateRebuildPromptAsync(
            templateLabel: "default",
            containerHashExpression: "$current_hash",
            promptResult: 0,
            promptOnChange: "true");

        Assert.Equal(0, exitCode);
        Assert.Equal(0, promptCalls);
    }

    [Fact]
    public async Task TemplateRebuildPrompt_ReturnsTenWhenUserConfirmsRebuild()
    {
        var (exitCode, promptCalls) = await RunTemplateRebuildPromptAsync(
            templateLabel: "default",
            containerHashExpression: "different-hash",
            promptResult: 0,
            promptOnChange: "true");

        Assert.Equal(10, exitCode);
        Assert.Equal(1, promptCalls);
    }

    [Fact]
    public async Task TemplateRebuildPrompt_ContinuesWhenUserDeclines()
    {
        var (exitCode, promptCalls) = await RunTemplateRebuildPromptAsync(
            templateLabel: "default",
            containerHashExpression: "different-hash",
            promptResult: 1,
            promptOnChange: "true");

        Assert.Equal(0, exitCode);
        Assert.Equal(1, promptCalls);
    }

    [Fact]
    public async Task TemplateRebuildPrompt_ReturnsTwoWhenPromptDisabled()
    {
        var (exitCode, promptCalls) = await RunTemplateRebuildPromptAsync(
            templateLabel: "default",
            containerHashExpression: "different-hash",
            promptResult: 0,
            promptOnChange: "false");

        Assert.Equal(2, exitCode);
        Assert.Equal(0, promptCalls);
    }

    [Fact]
    public async Task TemplateRebuildPrompt_SkipsWhenContainerLabelUsesDifferentTemplate()
    {
        var (exitCode, promptCalls) = await RunTemplateRebuildPromptAsync(
            templateLabel: "custom-template",
            containerHashExpression: "different-hash",
            promptResult: 0,
            promptOnChange: "true");

        Assert.Equal(0, exitCode);
        Assert.Equal(0, promptCalls);
    }

    private static async Task<(int ExitCode, int PromptCalls)> RunTemplateRebuildPromptAsync(
        string templateLabel,
        string containerHashExpression,
        int promptResult,
        string promptOnChange)
    {
        using var temp = ShellTestSupport.CreateTemporaryDirectory("cai-template-rebuild");
        var templateRoot = Path.Combine(temp.Path, "templates/default");
        Directory.CreateDirectory(templateRoot);
        await File.WriteAllTextAsync(
            Path.Combine(templateRoot, "Dockerfile"),
            "FROM ghcr.io/novotnyllc/containai:latest\nUSER agent\n",
            TestContext.Current.CancellationToken);

        var cancellationToken = TestContext.Current.CancellationToken;
        var templateLibraryPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/template.sh");
        var containerLibraryPath = Path.Combine(ShellTestSupport.RepositoryRoot, "src/lib/container.sh");

        var result = await ShellTestSupport.RunBashAsync(
            $$"""
            source {{ShellTestSupport.ShellQuote(templateLibraryPath)}}
            source {{ShellTestSupport.ShellQuote(containerLibraryPath)}}

            _CAI_TEMPLATE_DIR={{ShellTestSupport.ShellQuote(Path.Combine(temp.Path, "templates"))}}
            current_hash=$(_cai_template_fingerprint "default")
            MOCK_CONTAINER_TEMPLATE_LABEL={{ShellTestSupport.ShellQuote(templateLabel)}}
            MOCK_CONTAINER_TEMPLATE_HASH={{ShellTestSupport.ShellQuote(containerHashExpression)}}
            if [[ "$MOCK_CONTAINER_TEMPLATE_HASH" == '$current_hash' ]]; then
              MOCK_CONTAINER_TEMPLATE_HASH="$current_hash"
            fi

            PROMPT_CALLS=0
            PROMPT_RESULT={{promptResult}}

            docker() {
              local -a args=("$@")
              if [[ "${args[0]:-}" == "--context" ]]; then
                args=("${args[@]:2}")
              fi

              if [[ "${args[0]:-}" == "inspect" && "${args[1]:-}" == "--format" ]]; then
                local fmt="${args[2]:-}"
                case "$fmt" in
                  *"ai.containai.template-hash"*)
                    printf '%s' "$MOCK_CONTAINER_TEMPLATE_HASH"
                    return 0
                    ;;
                  *"ai.containai.template"*)
                    printf '%s' "$MOCK_CONTAINER_TEMPLATE_LABEL"
                    return 0
                    ;;
                esac
              fi

              return 1
            }

            _cai_prompt_confirm() {
              PROMPT_CALLS=$((PROMPT_CALLS + 1))
              return "$PROMPT_RESULT"
            }

            _cai_warn() {
              :
            }

            set +e
            _cai_maybe_prompt_template_rebuild "containai-docker" "test-container" "default" {{ShellTestSupport.ShellQuote(promptOnChange)}}
            rc=$?
            set -e

            printf '%s|%s' "$rc" "$PROMPT_CALLS"
            """,
            cancellationToken: cancellationToken);

        Assert.Equal(0, result.ExitCode);

        var split = result.StdOut.Trim().Split('|', StringSplitOptions.RemoveEmptyEntries);
        return (int.Parse(split[0]), int.Parse(split[1]));
    }

    private static string ComputeSha256(string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        var hash = SHA256.HashData(bytes);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
