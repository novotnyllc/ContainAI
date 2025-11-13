# PowerShell Language Support Implementation Plan for Serena in CodingAgents

## Executive Summary

This plan outlines adding PowerShell language server support to Serena by integrating **PowerShell Editor Services (PSES)** into the CodingAgents container environment. Since Serena is installed via `uvx` from git, we'll fork Serena and add PowerShell support following their language addition guide.

## 1. Architecture Overview

### 1.1 Current Setup
- **Serena**: Installed via `uvx --from "git+https://github.com/oraios/serena"` in containers
- **Container Base**: Ubuntu 22.04 with Python 3.11, Node.js 20, PowerShell already installed
- **Language Servers**: Started via Serena as subprocess communicating over LSP

### 1.2 PowerShell Editor Services (PSES)
- **Repository**: https://github.com/PowerShell/PowerShellEditorServices
- **Language**: C# (.NET)
- **Protocol**: LSP over stdio or named pipes
- **Entry Point**: `Start-EditorServices.ps1` wrapper or `Start-EditorServices` cmdlet
- **Installation**: Distributed as PowerShell module or standalone bundle

## 2. Implementation Steps

### Phase 1: Container Preparation (PSES Installation)

#### File: `docker/base/Dockerfile`

Add after PowerShell installation (around line 90):

```dockerfile
# Install PowerShell Editor Services
RUN pwsh -NoProfile -Command " \
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
    Install-Module -Name PowerShellEditorServices -Repository PSGallery -Scope AllUsers -Force; \
    "

# Verify PSES installation
RUN pwsh -NoProfile -Command " \
    Import-Module PowerShellEditorServices; \
    Get-Command Start-EditorServices; \
    " || echo "⚠️  PowerShell Editor Services installation verification failed"

# Set PSES environment variables for easier access
ENV PSES_MODULE_PATH="/usr/local/share/powershell/Modules/PowerShellEditorServices"
```

**Alternative: Install from GitHub Release (for specific version control):**

```dockerfile
# Install PowerShell Editor Services from GitHub
RUN PSES_VERSION="v3.20.1" && \
    wget -q "https://github.com/PowerShell/PowerShellEditorServices/releases/download/${PSES_VERSION}/PowerShellEditorServices.zip" -O /tmp/pses.zip && \
    mkdir -p /usr/local/share/powershell/Modules/PowerShellEditorServices && \
    unzip -q /tmp/pses.zip -d /usr/local/share/powershell/Modules/PowerShellEditorServices && \
    rm /tmp/pses.zip && \
    pwsh -NoProfile -Command "Import-Module PowerShellEditorServices; Get-Command Start-EditorServices"
```

### Phase 2: Fork Serena and Add PowerShell Support

#### File Structure to Add:
```
serena/
├── src/
│   └── solidlsp/
│       └── language_servers/
│           └── powershell_server.py          # NEW FILE
├── test/
│   ├── resources/
│   │   └── repos/
│   │       └── powershell/
│   │           └── test_repo/                 # NEW TEST REPO
│   │               ├── scripts/
│   │               │   ├── Invoke-Demo.ps1
│   │               │   └── Get-Helper.ps1
│   │               ├── modules/
│   │               │   └── MyModule/
│   │               │       ├── MyModule.psd1
│   │               │       └── MyModule.psm1
│   │               └── tests/
│   │                   └── MyModule.Tests.ps1
│   └── solidlsp/
│       └── powershell/
│           ├── __init__.py
│           └── test_powershell_basic.py       # NEW TEST FILE
└── pytest.ini                                  # UPDATE
```

#### File: `src/solidlsp/language_servers/powershell_server.py`

```python
"""
PowerShell language server implementation using PowerShell Editor Services.
"""
import logging
import os
import shutil
import subprocess
from typing import Optional

from solidlsp.ls import SolidLanguageServer
from solidlsp.ls_config import LanguageServerConfig
from solidlsp.ls_logger import LanguageServerLogger
from solidlsp.lsp_protocol_handler.server import ProcessLaunchInfo


logger = logging.getLogger(__name__)


class PowerShellServer(SolidLanguageServer):
    """
    Language server implementation for PowerShell using PowerShell Editor Services.
    
    PowerShell Editor Services (PSES) is the official LSP implementation from Microsoft.
    It requires PowerShell 7+ and communicates via stdio.
    """
    
    def __init__(
        self,
        config: LanguageServerConfig,
        logger: LanguageServerLogger,
        repository_root_path: str
    ):
        """Initialize PowerShell language server."""
        # Get language server command
        cmd = self._get_language_server_command(logger)
        
        super().__init__(
            config,
            logger,
            repository_root_path,
            ProcessLaunchInfo(cmd=cmd, cwd=repository_root_path),
            "powershell",  # Language ID for LSP
        )
    
    def _get_language_server_command(self, logger: LanguageServerLogger) -> list[str]:
        """
        Construct the command to start PowerShell Editor Services.
        
        PSES can be started via:
        1. The Start-EditorServices.ps1 script (bundled with module)
        2. The Start-EditorServices cmdlet directly
        
        We use stdio mode for LSP communication.
        """
        # Check if pwsh is available
        pwsh_path = shutil.which("pwsh")
        if not pwsh_path:
            # Fall back to powershell.exe on Windows
            pwsh_path = shutil.which("powershell")
            if not pwsh_path:
                raise RuntimeError(
                    "PowerShell not found. Please install PowerShell 7+ (pwsh) "
                    "or Windows PowerShell 5.1+."
                )
        
        # Check if PowerShellEditorServices module is available
        check_cmd = [
            pwsh_path,
            "-NoProfile",
            "-Command",
            "Get-Module -ListAvailable PowerShellEditorServices | Select-Object -ExpandProperty ModuleBase"
        ]
        
        try:
            result = subprocess.run(
                check_cmd,
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode != 0 or not result.stdout.strip():
                raise RuntimeError(
                    "PowerShellEditorServices module not found. Please install:\n"
                    "  pwsh -Command 'Install-Module -Name PowerShellEditorServices -Scope CurrentUser'"
                )
            
            module_base = result.stdout.strip().split('\n')[0]
            logger.info(f"Found PowerShellEditorServices at: {module_base}")
            
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
            raise RuntimeError(f"Failed to check PowerShellEditorServices installation: {e}")
        
        # Construct command to start PSES in stdio mode
        # Using the Start-EditorServices cmdlet with -Stdio parameter
        cmd = [
            pwsh_path,
            "-NoLogo",
            "-NoProfile",
            "-Command",
            (
                "Import-Module PowerShellEditorServices; "
                "Start-EditorServices "
                "-HostName 'Serena' "
                "-HostProfileId 'Serena' "
                "-HostVersion '1.0.0' "
                "-LogLevel Normal "
                "-SessionDetailsPath (Join-Path ([System.IO.Path]::GetTempPath()) 'pses_serena.json') "
                "-FeatureFlags @() "
                "-AdditionalModules @() "
                "-LogPath (Join-Path ([System.IO.Path]::GetTempPath()) 'pses_serena.log') "
                "-Stdio "
                "-BundledModulesPath $PSScriptRoot "
                "-LanguageServiceOnly"
            )
        ]
        
        return cmd
    
    @override
    def is_ignored_dirname(self, dirname: str) -> bool:
        """
        Define PowerShell-specific directories to ignore.
        
        Common PowerShell directories to ignore:
        - .git, .vscode (standard VCS/IDE)
        - bin, obj (build outputs for PowerShell classes/C# interop)
        - TestResults (Pester test results)
        - .vs (Visual Studio)
        """
        return super().is_ignored_dirname(dirname) or dirname in [
            "bin",
            "obj",
            "TestResults",
            ".vs",
            "packages",
            "out",
        ]
    
    @override
    def _get_file_extensions(self) -> list[str]:
        """Return file extensions for PowerShell files."""
        return [".ps1", ".psm1", ".psd1"]
```

#### File: `src/solidlsp/ls_config.py` (update)

Add to the `Language` enum:

```python
class Language(str, Enum):
    # ... existing languages ...
    POWERSHELL = "powershell"
    
    def get_source_fn_matcher(self) -> FilenameMatcher:
        match self:
            # ... existing cases ...
            case self.POWERSHELL:
                return FilenameMatcher("*.ps1", "*.psm1", "*.psd1")
```

#### File: `src/solidlsp/ls.py` (update)

Add to the `create` method:

```python
@classmethod
def create(
    cls,
    config: LanguageServerConfig,
    logger: LanguageServerLogger,
    repository_root_path: str
) -> "SolidLanguageServer":
    match config.code_language:
        # ... existing cases ...
        case Language.POWERSHELL:
            from solidlsp.language_servers.powershell_server import PowerShellServer
            return PowerShellServer(config, logger, repository_root_path)
```

### Phase 3: Test Repository Structure

#### Directory: `test/resources/repos/powershell/test_repo/`

**File: `scripts/Invoke-Demo.ps1`**
```powershell
<#
.SYNOPSIS
    Demonstrates PowerShell script functionality.
.DESCRIPTION
    This script tests various PowerShell features including functions,
    classes, and module imports.
#>

# Import helper module
Import-Module -Name "$PSScriptRoot/../modules/MyModule/MyModule.psm1"

# Define a class (PowerShell 5.0+)
class Calculator {
    [int] Add([int]$a, [int]$b) {
        return $a + $b
    }
    
    [int] Subtract([int]$a, [int]$b) {
        return Get-SubtractionResult -First $a -Second $b
    }
    
    [int] Multiply([int]$a, [int]$b) {
        return $a * $b
    }
}

# Function using the class
function Invoke-Calculation {
    param(
        [Parameter(Mandatory)]
        [int]$First,
        
        [Parameter(Mandatory)]
        [int]$Second,
        
        [ValidateSet('Add', 'Subtract', 'Multiply')]
        [string]$Operation = 'Add'
    )
    
    $calc = [Calculator]::new()
    
    switch ($Operation) {
        'Add' { $calc.Add($First, $Second) }
        'Subtract' { $calc.Subtract($First, $Second) }
        'Multiply' { $calc.Multiply($First, $Second) }
    }
}

# Main execution
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-Calculation -First 10 -Second 5 -Operation Add
    Write-Host "Result: $result"
}
```

**File: `modules/MyModule/MyModule.psm1`**
```powershell
<#
.SYNOPSIS
    Helper module for mathematical operations.
#>

function Get-SubtractionResult {
    <#
    .SYNOPSIS
        Subtracts two numbers.
    .PARAMETER First
        The first number.
    .PARAMETER Second
        The second number to subtract.
    .OUTPUTS
        System.Int32
    #>
    param(
        [Parameter(Mandatory)]
        [int]$First,
        
        [Parameter(Mandatory)]
        [int]$Second
    )
    
    return $First - $Second
}

function Get-MultiplicationResult {
    param(
        [int]$First,
        [int]$Second
    )
    
    return $First * $Second
}

Export-ModuleMember -Function Get-SubtractionResult, Get-MultiplicationResult
```

**File: `modules/MyModule/MyModule.psd1`**
```powershell
@{
    RootModule = 'MyModule.psm1'
    ModuleVersion = '1.0.0'
    GUID = '12345678-1234-1234-1234-123456789012'
    Author = 'Test Author'
    Description = 'Test module for PowerShell language server'
    FunctionsToExport = @('Get-SubtractionResult', 'Get-MultiplicationResult')
}
```

**File: `scripts/Get-Helper.ps1`**
```powershell
<#
.SYNOPSIS
    Helper script demonstrating cross-file references.
#>

# This function is referenced from Invoke-Demo.ps1
function Get-ProcessInfo {
    param(
        [string]$ProcessName
    )
    
    Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
}

function Test-Functionality {
    $processes = Get-ProcessInfo -ProcessName 'pwsh'
    return $processes.Count -gt 0
}
```

### Phase 4: Test Suite

#### File: `test/solidlsp/powershell/test_powershell_basic.py`

```python
"""
Basic tests for PowerShell language server functionality.
"""
import pytest
from pathlib import Path

from solidlsp.ls_config import Language, LanguageServerConfig
from test.test_utils import get_test_repo_path


# Test marker for PowerShell tests
pytestmark = pytest.mark.powershell


@pytest.fixture
def powershell_repo_path():
    """Get path to PowerShell test repository."""
    return get_test_repo_path(Language.POWERSHELL)


@pytest.fixture
def powershell_server(powershell_repo_path):
    """Create a PowerShell language server instance."""
    from solidlsp.ls import SolidLanguageServer
    from solidlsp.ls_logger import LanguageServerLogger
    
    config = LanguageServerConfig(code_language=Language.POWERSHELL)
    logger = LanguageServerLogger()
    
    server = SolidLanguageServer.create(config, logger, str(powershell_repo_path))
    yield server
    server.shutdown()


def test_find_class_symbol(powershell_server, powershell_repo_path):
    """Test finding a PowerShell class definition."""
    script_path = powershell_repo_path / "scripts" / "Invoke-Demo.ps1"
    
    # Find the Calculator class
    symbols = powershell_server.find_symbols(
        file_path=str(script_path),
        name_pattern="Calculator"
    )
    
    assert len(symbols) > 0, "Should find Calculator class"
    assert any(s.name == "Calculator" for s in symbols)


def test_find_function_symbol(powershell_server, powershell_repo_path):
    """Test finding a PowerShell function definition."""
    script_path = powershell_repo_path / "scripts" / "Invoke-Demo.ps1"
    
    # Find the Invoke-Calculation function
    symbols = powershell_server.find_symbols(
        file_path=str(script_path),
        name_pattern="Invoke-Calculation"
    )
    
    assert len(symbols) > 0, "Should find Invoke-Calculation function"
    assert any(s.name == "Invoke-Calculation" for s in symbols)


def test_find_method_references(powershell_server, powershell_repo_path):
    """Test finding references to a class method."""
    script_path = powershell_repo_path / "scripts" / "Invoke-Demo.ps1"
    
    # Find references to Calculator.Add method
    references = powershell_server.find_references(
        file_path=str(script_path),
        line=23,  # Line with Add method definition
        character=10
    )
    
    # Should find at least the definition and one usage
    assert len(references) >= 2, "Should find method definition and usage"


def test_find_cross_file_references(powershell_server, powershell_repo_path):
    """Test finding cross-file function references."""
    module_path = powershell_repo_path / "modules" / "MyModule" / "MyModule.psm1"
    
    # Find references to Get-SubtractionResult
    references = powershell_server.find_references(
        file_path=str(module_path),
        line=10,  # Function definition line
        character=15
    )
    
    # Should find:
    # 1. Definition in MyModule.psm1
    # 2. Export in MyModule.psm1
    # 3. Usage in Invoke-Demo.ps1 (Calculator.Subtract method)
    assert len(references) >= 2, "Should find cross-file references"
    
    # Verify at least one reference is in a different file
    file_paths = {ref.file_path for ref in references}
    assert len(file_paths) >= 2, "References should span multiple files"


def test_document_symbols(powershell_server, powershell_repo_path):
    """Test retrieving all symbols in a document."""
    script_path = powershell_repo_path / "scripts" / "Invoke-Demo.ps1"
    
    symbols = powershell_server.get_document_symbols(str(script_path))
    
    # Should find: Calculator class, Invoke-Calculation function
    assert len(symbols) >= 2, "Should find multiple symbols"
    
    symbol_names = {s.name for s in symbols}
    assert "Calculator" in symbol_names
    assert "Invoke-Calculation" in symbol_names


def test_powershell_file_extensions(powershell_server):
    """Test that PowerShell server recognizes correct file extensions."""
    extensions = powershell_server._get_file_extensions()
    
    assert ".ps1" in extensions, "Should recognize .ps1 files"
    assert ".psm1" in extensions, "Should recognize .psm1 module files"
    assert ".psd1" in extensions, "Should recognize .psd1 manifest files"


def test_ignored_directories(powershell_server):
    """Test that PowerShell-specific directories are ignored."""
    assert powershell_server.is_ignored_dirname("bin")
    assert powershell_server.is_ignored_dirname("obj")
    assert powershell_server.is_ignored_dirname("TestResults")
    assert not powershell_server.is_ignored_dirname("scripts")
    assert not powershell_server.is_ignored_dirname("modules")


@pytest.mark.slow
def test_completion(powershell_server, powershell_repo_path):
    """Test code completion functionality."""
    script_path = powershell_repo_path / "scripts" / "Invoke-Demo.ps1"
    
    # Test completion after typing "Get-"
    completions = powershell_server.get_completions(
        file_path=str(script_path),
        line=50,  # Arbitrary line in script
        character=4
    )
    
    # Should get PowerShell cmdlet completions
    assert len(completions) > 0, "Should provide completions"
```

#### File: `pytest.ini` (update)

Add PowerShell marker:

```ini
[pytest]
markers =
    # ... existing markers ...
    powershell: PowerShell language server tests
```

### Phase 5: Integration with CodingAgents

#### Update `config.toml` to use forked Serena:

```toml
[mcp_servers.serena]
command = "uvx"
# Use forked version with PowerShell support
args = ["--from", "git+https://github.com/YOUR-USERNAME/serena@powershell-support", "serena", "start-mcp-server", "--project", "/workspace", "--context", "ide-assistant", "--mode", "planning", "--mode", "editing", "--mode", "interactive"]
```

## 3. Timeline and Milestones

### Week 1: Setup
- [ ] Fork Serena repository
- [ ] Add PSES to `docker/base/Dockerfile`
- [ ] Build and test container with PSES

### Week 2: Implementation
- [ ] Implement `powershell_server.py`
- [ ] Update Serena enums and factory
- [ ] Create test repository structure

### Week 3: Testing
- [ ] Write comprehensive unit tests
- [ ] Test in CodingAgents container
- [ ] Fix bugs and edge cases

### Week 4: Integration
- [ ] Update CodingAgents config
- [ ] Write documentation
- [ ] Consider submitting PR to Serena upstream

## 4. Success Criteria

✅ PowerShell Editor Services starts successfully in containers  
✅ Serena can find PowerShell symbols (classes, functions, cmdlets)  
✅ Cross-file references work (module imports, function calls)  
✅ Tests pass with >90% coverage  
✅ Documentation is complete and accurate  
✅ Works seamlessly in CodingAgents workflow

## 5. Resources

- **Serena Guide**: https://github.com/oraios/serena/blob/main/.serena/memories/adding_new_language_support_guide.md
- **PSES Repository**: https://github.com/PowerShell/PowerShellEditorServices
- **LSP Specification**: https://microsoft.github.io/language-server-protocol/
- **PowerShell Documentation**: https://learn.microsoft.com/en-us/powershell/

## 6. Notes

- PSES adds approximately 20MB to container size
- PowerShell 7+ is already installed in base container
- PSES supports stdio mode (preferred for LSP)
- Consider submitting upstream PR once stable
