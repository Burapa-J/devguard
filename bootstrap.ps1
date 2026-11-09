# One-command setup on Windows (PowerShell 5.1+):
#
#   irm https://raw.githubusercontent.com/Burapa-J/devguard/main/bootstrap.ps1 | iex
#
# Installs missing prerequisites via winget, clones the kit to ~/.local/share/agent-kit/src,
# runs ./install.sh through Git Bash, and adds ~/.local/bin to the user PATH.

$ErrorActionPreference = "Stop"

$Repo = "Burapa-J/devguard"
$FallbackRepo = "Burapa-J/A69-012-agent-kit"
$Dest = if ($env:AGENT_KIT_DIR) { $env:AGENT_KIT_DIR } else { Join-Path $HOME ".local\share\agent-kit\src" }

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Find-GitBash {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Git\bin\bash.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe")
    )
    $gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($gitCmd -and $gitCmd.Source) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $gitCmd.Source)
        $candidates = @((Join-Path $gitRoot "bin\bash.exe"), (Join-Path $gitRoot "usr\bin\bash.exe")) + $candidates
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

$prereqs = @(
    @{ Cmd = "git";        WingetId = "Git.Git" },
    @{ Cmd = "jq";         WingetId = "jqlang.jq" },
    @{ Cmd = "python";     WingetId = "Python.Python.3.12" },
    @{ Cmd = "npm";        WingetId = "OpenJS.NodeJS.LTS" },
    @{ Cmd = "ast-grep";   WingetId = "ast-grep.ast-grep" },
    @{ Cmd = "shellcheck"; WingetId = "koalaman.shellcheck" }
)

foreach ($p in $prereqs) {
    if (-not (Get-Command $p.Cmd -ErrorAction SilentlyContinue)) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Step "Installing $($p.Cmd) ($($p.WingetId)) via winget..."
            winget install --id $p.WingetId -e --accept-source-agreements --accept-package-agreements --silent | Out-Null
        } else {
            Write-Warning "Missing $($p.Cmd) and winget is not available. Please install $($p.WingetId) manually."
        }
    }
}

# Refresh current session PATH from Machine + User Registry after winget installs
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPathReg = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$userPathReg;$machinePath"

$gitBash = Find-GitBash
if (-not $gitBash) {
    throw "Git Bash (bash.exe from Git for Windows) not found. Install Git for Windows (winget install Git.Git) and run again."
}

if (Test-Path -LiteralPath (Join-Path $Dest ".git")) {
    Write-Step "Updating $Dest"
    git -C $Dest pull --ff-only
} else {
    Write-Step "Cloning $Repo to $Dest"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    git clone "https://github.com/$Repo.git" $Dest 2>$null
    if (-not (Test-Path -LiteralPath (Join-Path $Dest ".git"))) {
        git clone "https://github.com/$FallbackRepo.git" $Dest
    }
}

Write-Step "Running install.sh via Git Bash ($gitBash)"
$posixDest = (& $gitBash -c 'cygpath -u "$1"' -- $Dest).Trim()
& $gitBash -c 'cd "$1" && shift && ./install.sh "$@"' -- $posixDest @args
if ($LASTEXITCODE -ne 0) {
    throw "install.sh exited with code $LASTEXITCODE"
}

$binDir = Join-Path $HOME ".local\bin"
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
if ($null -ne $key) {
    $curPath = $key.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $expanded = ($curPath -split ";") | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd("\") }
    if ($expanded -notcontains $binDir.TrimEnd("\")) {
        $newPath = if ($curPath) { "$binDir;$curPath" } else { $binDir }
        $key.SetValue("Path", $newPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        $env:Path = "$binDir;$env:Path"
        Write-Step "Added $binDir to User PATH"
    }
    $key.Close()
}

Write-Step "Done. Open a new terminal, restart your agents, then run: devguard status"
