﻿<#
.SYNOPSIS
    Wraps CMake Visual Studio solution generation and build for LLVM as used by the LLVM.NET project

.PARAMETER BuildOutputPath
    The path to where the projects are generated and the binaries they build will be located.

.PARAMETER Generate
    Switch to run CMAKE configuration and project/solution generation

.PARAMETER Build
    Switch to Build the projects generated by the -Generate option

.PARAMETER Register
    Add Registry entries for the location of binaries built and the LLVM header files so that projects using the libraries generated can locate them

.PARAMETER LlvmRoot
    This specifies the root of the LLVM source tree to build. The default value is the folder containing this script, but if the script is not placed
    into the LLVM source tree the path must be specified.

.PARAMETER BaseVsGenerator
    This specifies the base name of the CMAKE Visual Studio Generator. This script will add the "Win64" part of the name when generating 64bit projects.
    The default value is for Visual Studio 2017 as LLVM.NET is migrating to Full VS 2017 support.

.PARAMETER CreateSettingsJson
    This flag generates the VS CMakeSettings.json file with all the CMAKE settings for LLVM as needed by LLVM.NET with Visual C++ tools for CMake in
    Visual Studio 2017.
#>
[CmdletBinding()]
param( [Parameter(Mandatory)]
       [string]
       $BuildOutputPath,

       [switch]
       $Generate,

       [switch]
       $Build,

       [switch]
       $Register,

       [switch]
       $CreateSettingsJson,

       [ValidateNotNullOrEmpty()]
       [string]$LlvmRoot=$PSScriptRoot,

       [ValidateNotNullOrEmpty()]
       [string]
       $BaseVsGenerator="Visual Studio 15 2017"
     )

function Get-CmakeInfo([int]$minMajor, [int]$minMinor, [int]$minPatch)
{
    $cmakePath = where.exe cmake.exe 2>&1 | %{$_.ToString}
    if( $LASTEXITCODE -ne 0 )
    {
        throw "CMAKE.EXE not found - Version {1}.{2}.{3} or later is required and should be in the search path" -f($minMajor,$minMinor,$minPatch)
    }

    $cmakeInfo = cmake -E capabilities | ConvertFrom-Json
    $cmakeVer = $cmakeInfo.version
    if( ($cmakeVer.major -lt $minMajor) -or ($cmakeVer.minor -lt $minMinor) -or ($cmakeVer.patch -lt $minPatch) )
    {
        throw "CMake version not supported. Found: {0}; Require >= {1}.{2}.{3}" -f($cmakeInfo.version.string,$minMajor,$minMinor,$minPatch)
    }
}

function Generate-CMake( $config, [string]$llvmroot )
{
    $activity = "Generating solution for {0}" -f($config.name)
    Write-Information $activity
    if(!(Test-Path -PathType Container $config.buildRoot ))
    {
        New-Item -ItemType Container $config.buildRoot | Out-Null
    }

    # Construct full set of args from fixed options and configuration variables
    $cmakeArgs = New-Object System.Collections.ArrayList
    $cmakeArgs.Add("-G`"{0}`"" -f($config.generator)) | Out-Null
    foreach( $var in $config.variables )
    {
        $cmakeArgs.Add( "-D{0}={1}" -f($var.name,$var.value) ) | Out-Null
    }

    $cmakeArgs.Add( $llvmRoot ) | Out-Null
    
    pushd $config.buildRoot
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try
    { 
        Write-Verbose "cmake $cmakeArgs"
        & cmake $cmakeArgs | %{Write-Progress -Activity $activity -PercentComplete (-1) -SecondsRemaining (-1) -Status ([string]$_) }
        
        if($LASTEXITCODE -ne 0 )
        {
            throw ("Cmake generation exited with non-zero exit code: {0}" -f($LASTEXITCODE))
        }
    }
    finally
    {
        $timer.Stop()
        Write-Progress -Activity $activity -Completed
        Write-Verbose ("Generation Time: {0}" -f($timer.Elapsed.ToString()))
        popd
    }
}

function Build-Cmake($config)
{
    $activity = "Building LLVM for {0}" -f($config.name)
    Write-Information $activity

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try
    {
        cmake --build $config.buildRoot --config $config.configurationType -- ($config.buildCommandArgs.Split(' '))
        if($LASTEXITCODE -ne 0 )
        {
            throw "Cmake build exited with non-zero exit code: {0}" -f($LASTEXITCODE)
        }
    }
    finally
    {
        $timer.Stop()
        Write-Verbose ("Build Time: {0}" -f($timer.Elapsed.ToString()))
    }
}

function Register-Llvm( [string]$llvmVersion, [string] $llvmRoot, [string] $buildRoot )
{
    $regPath = "Software\LLVM\$llvmVersion"
    if( !( Test-Path HKCU:$regPath ) )
    {
        New-Item HKCU:$regPath | Out-Null
    }

    New-ItemProperty -Path HKCU:$regPath -Name "SrcRoot" -Value $llvmRoot -Force | Out-Null
    New-ItemProperty -Path HKCU:$regPath -Name "BuildRoot" -Value $buildRoot -Force | Out-Null
    
    try
    {
        if( !( Test-Path HKLM:$regPath ) )
        {
            New-Item HKLM:$regPath | Out-Null
        }
        New-ItemProperty -Path HKLM:$regPath -Name "SrcRoot" -Value $llvmRoot -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path HKLM:$regPath -Name "BuildRoot" -Value $buildRoot -Force -ErrorAction Stop | Out-Null
    }
    catch [System.Security.SecurityException]
    {
        Write-Warning "Registration of LLVM in System wide registry not set due to access permissions. To register the LLVM source root for the system, run this script with the -Register switch elevated with admin priviliges."
    }
}

function New-CmakeConfig([string]$platform, [string]$config, [string]$BaseGenerator, [string]$baseBuild )
{
    $generator = $BaseGenerator
    # normalize platform name and create final generator name
    $Platform = $Platform.ToLowerInvariant()
    switch($Platform)
    {
        "x86" {}
        "x64" {$generator="{0} Win64" -f($BaseGenerator)}
        default {throw "Invalid Platform" }
    }

    # build a config object suitable for conversion to JSON for VS CMakeSettings.json
    # This is used in the project generation and build as well, since it contains all
    # the information needed for each of those cases. 
    [PSCustomObject]@{ 
        name = "$platform-$config"
        generator = $generator
        configurationType = $config
        buildRoot = (Join-Path $baseBuild "$platform-$config") 
        cmakeCommandArgs = ""
        buildCommandArgs = "-m -v:minimal"
        variables = @(                                                 
            @{name = "LLVM_ENABLE_RTTI";          value = "ON" },
            @{name = "LLVM_BUILD_TOOLS";          value = "OFF"},
            @{name = "LLVM_BUILD_TESTS";          value = "OFF"},
            @{name = "LLVM_BUILD_EXAMPLES";       value = "OFF"},
            @{name = "LLVM_BUILD_DOCS";           value = "OFF"},
            @{name = "LLVM_BUILD_RUNTIME";        value = "OFF"},
            @{name = "CMAKE_INSTALL_PREFIX";      value = "Install"},
            @{name = "CMAKE_CONFIGURATION_TYPES"; value = "$config"}
        )
    }
}

function New-CmakeSettings( $configurations )
{
    ConvertTo-Json -Depth 4 ([PSCustomObject]@{ configurations = $configurations })
}

function Normalize-Path([string]$path )
{
    $path = [System.IO.Path]::Combine((pwd).Path,$path)
    return [System.IO.Path]::GetFullPath($path)
}

function Get-LlvmVersion( [string] $cmakeListPath )
{
    $props = @{}
    $matches = Select-String -Path $cmakeListPath -Pattern "set\(LLVM_VERSION_(MAJOR|MINOR|PATCH) ([0-9])+\)" | %{$_.Matches}
    foreach( $match in $matches )
    {  
        $props = $props + @{$match.Groups[1].Value = [Convert]::ToInt32($match.Groups[2].Value)}
    }
    $versionObj = [PsCustomObject]($props)
    "{0}.{1}.{2}" -f($versionObj.MAJOR,$versionObj.Minor,$versionObj.Patch)
}

#--- Main Script Body

# Force absolute paths for input params dealing in paths
$Script:LlvmRoot = Normalize-Path $Script:LlvmRoot
$Script:BuildOutputPath = Normalize-Path $Script:BuildOutputPath

# Verify Cmake version info
$CmakeInfo = Get-CmakeInfo 3 7 1

Write-Information "LLVM Source Root: $Script:LlvmRoot"
$cmakeListPath = Join-Path $Script:LlvmRoot CMakeLists.txt
if( !( Test-Path -PathType Leaf $cmakeListPath ) )
{
    throw "'$cmakeListPath' is missing, the current directory does not appear to be a valid source directory"
}

# Construct array of configurations to deal with
$configurations = ( (New-CmakeConfig x86 "Release" $BaseVsGenerator $Script:BuildOutputPath),
                    (New-CmakeConfig x86 "Debug" $BaseVsGenerator $Script:BuildOutputPath),
                    (New-CmakeConfig x64 "Release" $BaseVsGenerator $Script:BuildOutputPath),
                    (New-CmakeConfig x64 "Debug" $BaseVsGenerator $Script:BuildOutputPath)
                  )

if( $Generate )
{
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try
    {
        foreach( $config in $configurations )
        {
            Generate-CMake $config $Script:LlvmRoot
        }
    }
    finally
    {
        $timer.Stop()
        Write-Information ("Total Generation Time: {0}" -f($timer.Elapsed.ToString()))
    }
}

if( $Build )
{
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try
    {
        foreach( $config in $configurations )
        {
            Build-Cmake $config
        }
    }
    finally
    {
        $timer.Stop()
        Write-Information ("Total Build Time: {0}" -f($timer.Elapsed.ToString()))
    }
}

if( $Register )
{
    $llvmVersion = Get-LlvmVersion $Script:cmakeListPath
    Register-Llvm $llvmVersion $Script:LlvmRoot $Script:BuildOutputPath
}

if( $CreateSettingsJson )
{
    New-CmakeSettings $configurations | Out-File (join-path $Script:LlvmRoot CMakeSettings.json) 
}