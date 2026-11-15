# Local build of both drivers (x64 + ARM64) and the WinUI3 control panel, mirroring .github/workflows/build.yml.
# Requires VS 2022 Build Tools with MSVC v143 (x64 + ARM64), Spectre-mitigated libs,
# Component.Microsoft.Windows.DriverKit.BuildTools, the .NET 8 SDK and nuget.exe.
# Output is unsigned. Exit code is non-zero if any build fails.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -version '[17.0,18.0)' -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
if (-not $vs) { throw 'VS 2022 with MSVC not found' }
$msbuild = Join-Path $vs 'MSBuild\Current\Bin\amd64\MSBuild.exe'
"MSBuild: $msbuild"

$nuget = (Get-Command nuget -ErrorAction SilentlyContinue).Source
if (-not $nuget) {
    $nuget = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\nuget.exe'
}
if (-not (Test-Path $nuget)) { throw 'nuget.exe not found' }

$nugetArgs = @('-PackagesDirectory', "$repo\packages", '-Source', 'https://api.nuget.org/v3/index.json', '-MSBuildPath', (Split-Path $msbuild))
& $nuget restore .\AmtPtpDeviceUsbUm\MagicTrackpad2PtpDevice.vcxproj @nugetArgs
if ($LASTEXITCODE) { throw "nuget restore (USB) failed: $LASTEXITCODE" }
& $nuget restore .\AmtPtpHidFilter\AmtPtpHidFilter.vcxproj @nugetArgs
if ($LASTEXITCODE) { throw "nuget restore (BT) failed: $LASTEXITCODE" }

$results = @()
foreach ($plat in 'x64', 'ARM64') {
    foreach ($proj in '.\AmtPtpDeviceUsbUm\MagicTrackpad2PtpDevice.vcxproj', '.\AmtPtpHidFilter\AmtPtpHidFilter.vcxproj') {
        & $msbuild $proj -p:Configuration=Release -p:Platform=$plat -p:ApiValidator_Enable=false -m -nologo -v:minimal
        $results += "{0} {1}: exit {2}" -f (Split-Path $proj -Leaf), $plat, $LASTEXITCODE
    }
}

foreach ($rid in 'win-x64', 'win-arm64') {
    dotnet publish .\AmtPtpControlPanel.WinUI3\AmtPtpControlPanel.WinUI3.csproj -c Release -p:PublishProfile=$rid --source https://api.nuget.org/v3/index.json -nologo -v:minimal
    $results += "ControlPanel.WinUI3 ${rid}: exit $LASTEXITCODE"
}

'===== SUMMARY ====='
$results
Get-ChildItem -Recurse -Include AmtPtpDeviceUsbUm.dll, AmtPtpHidFilter.sys, AmtPtpControlPanel.WinUI3.exe -Path .\AmtPtpDeviceUsbUm\build, .\AmtPtpHidFilter\build, .\AmtPtpControlPanel.WinUI3\bin\publish -ErrorAction SilentlyContinue |
    Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 300
if ($results -match 'exit [1-9]') { exit 1 }
