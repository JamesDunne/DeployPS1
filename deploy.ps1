#
# Powershell deployment script for Server 2012 OSes to deploy sites and folders directly from
# TFS build drop folders.
#
# To be executed from the server being deployed to. CredSSP authentication must be enabled on the
# remote machine in order for AD credentials to float over the remoting session. Kerberos
# authentication (default) will cause access denied errors.
#
# James Dunne <james.jdunne@gmail.com>
# 2013-02-21
#
# For usage instructions, see README.md
#

Param (
    # Name of PS1 script that creates $Deploy variable
    [Parameter(Mandatory=$true,Position=0)]
    [string] $ConfigScriptPath,
    # Hash of mappings of TFS build name to build numbers
    $BuildNumbers = @{},
    # Use -TestMode to disable delete/xcopy
    [switch] $TestMode
);

# Must stop on all errors:
$ErrorActionPreference = "Stop";

# Sets appSettings/CurrentEnvironment value
function Config-Set-CurrentEnvironment ( [System.Xml.XmlDocument]$doc )
{
    $root = $doc.get_DocumentElement();

    # Set <appSettings> keys according to deployment configuration
    foreach ($item in $root.appSettings.add) {
        if ($item.key -eq "CurrentEnvironment") {
            $item.value = $EnvironmentName;
            Write-Host "    Updated CurrentEnvironment value = '$EnvironmentName'";
        }
    }
}

# Do various updates to web.config/app.config files:
function Config-Update ( $path )
{
    if ($TestMode) {
        Write-Host "    TEST MODE: Config-Update path='$path'";
        return;
    }

    # Find web.config:
    $webConfigPath = [System.IO.Path]::Combine( $path, "web.config" );
    if ( [System.IO.File]::Exists( $webConfigPath ) )
    {
        Write-Host "    Updating '$webConfigPath'";

        [System.Xml.XmlDocument]$doc = new-object System.Xml.XmlDocument;
        $doc.Load($webConfigPath);

        $root = $doc.get_DocumentElement();

        # Change compilation mode to debug="false"  
        $root."system.web".compilation.debug = "false";

        # Set CurrentEnvironment:
        Config-Set-CurrentEnvironment $doc;

        $doc.Save($webConfigPath);

        Write-Host "    Updated '$webConfigPath'";
    }

    # Find *.exe.config files:
    $appConfigFiles = [System.IO.Directory]::GetFiles($path, "*.exe.config");
    foreach ($appConfigPath in $appConfigFiles) {
        Write-Host "    Updating '$appConfigPath'";

        [System.Xml.XmlDocument]$doc = new-object System.Xml.XmlDocument;
        $doc.Load($appConfigPath);

        # Set CurrentEnvironment:
        Config-Set-CurrentEnvironment $doc;

        $doc.Save($appConfigPath);

        Write-Host "    Updated '$webConfigPath'";
    }
}

# Clears out the $dest folder and xcopies from $src
function Clear-And-Copy ( $src, $dest )
{
    # System folder paths can easily creep in here:
    if ($dest.StartsWith("C:\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Will not clear out any folders on C: drive!";
    }

    if ($TestMode) {
        Write-Host "    TEST MODE: Clear-And-Copy src='$src' dest='$dest'";
        return;
    }

    # Clear out the target directory:
    Write-Host "    Clearing existing directory: $dest";
    if ([System.IO.Directory]::Exists($dest)) {
        # Delete the directory recursively:
        Remove-Item -Path $dest -Recurse -Force;
    }
    Write-Host "";

    Write-Host "    Copying from '$src' to '$dest'";
    xcopy $src $dest /E /I /C /Q;
}

# Handles a deployment to an IIS site, including xcopy and web.config updates
function Deploy-Site ( $ws, $destRelPath, $srcAbsPath )
{
    $siteName = $ws.Name;
    if ($destRelPath -ne ".") {
        $siteName = $siteName + "/" + $destRelPath;
    }
    
    Write-Host "";
    Write-Host "    Deploying to $siteName";

    $dest = [System.IO.Path]::GetFullPath( [System.IO.Path]::Combine($ws.physicalPath, $destRelPath) );

    # Clear out existing folder and copy to it:
    Clear-And-Copy $srcAbsPath $dest;

    # Find the web.config/*.exe.config files and update them accordingly:
    Config-Update $dest;

    Write-Host "    Deployed to $siteName";
}

# Verifies that a local IIS website exists with the given $name
function Require-IIS-Website ( $name )
{
    $ws = Get-Item "IIS:\Sites\$name";
    if (!$ws) {
        throw "  Could not access IIS data, or site named '$name' does not exist! Try running as Administrator.";
    }
    if ($ws.Name -ne $name) {
        throw "  IIS site named '${ws.Name}' is not named as expected: '$name'!";
    }
    return $ws;
}

# Verifies that a required source path exists, else throws an error
function Require-Path-Exists ( $path )
{
    if ( -not [System.IO.Directory]::Exists( $path ) ) {
        throw "  Required folder '$path' does not exist!";
    }
}

function Get-Build-Dir ( $tfsBuildName, $buildRootPath )
{
    # Look up the TFS Build Name in the $BuildNumbers param hash:
    if (!$BuildNumbers.ContainsKey($tfsBuildName)) {
        Write-Host "  Detecting latest build directory in '$buildRootPath'...";

        $buildDir = (new-object System.IO.DirectoryInfo($buildRootPath)).GetDirectories() |
            Sort-Object LastWriteTime -descending |
            Select-Object -first 1;

        if ($buildDir -eq $null) {
            throw "  Error detecting latest build directory from '$buildRootPath'";
        }

        Write-Host "  Successfully detected latest build: $buildDir";
        return $buildDir;
    } else {
        $buildDir = $BuildNumbers[$tfsBuildName];
        Write-Host "  Using specified build: $buildDir";
        return $buildDir;
    }
}

# Process a "WebSites" deployment rule and controls IIS with stop/start commands
function Deploy-WebSites ( $dp )
{
    $tfsBuildName = $dp["TFSBuildName"];

    Write-Host "";
    Write-Host "Deploying WebSites from $tfsBuildName...";

    $buildRootPath = [System.IO.Path]::Combine($BuildsDropPath, $tfsBuildName);

    $buildDir = Get-Build-Dir $tfsBuildName $buildRootPath;

    Write-Host "";

    $buildSitesPath = [System.IO.Path]::Combine($buildRootPath, [System.IO.Path]::Combine($buildDir, "_PublishedWebsites"));

    $sites = $dp["WebSites"];

    # Check that build folder paths exist (build might not be completed yet):
    Write-Host "  Verifying build is complete...";

    foreach ($site in $sites) {
        # Construct the final source path:
        $site["_SourcePath"] = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::Combine($buildSitesPath, [System.IO.Path]::Combine($site["SourceSite"], $site["SourceFolder"]))
        );

        # Require that the source path exists:
        Require-Path-Exists $site["_SourcePath"];
    }

    Write-Host "  Verified";
    Write-Host "";
    Write-Host "  Verifying IIS configuration...";

    $IISSiteNames = New-Object System.Collections.Generic.HashSet[System.String];
    $IISAppPoolNames = New-Object System.Collections.Generic.HashSet[System.String];

    foreach ($site in $sites) {
        # Require that the target IIS site name exists:
        $mainSite = Require-IIS-Website $site["TargetSite"];
        $site["_IISSite"] = $mainSite;

        $tmp = $IISSiteNames.Add($mainSite.Name);
        $tmp = $IISAppPoolNames.Add($mainSite.applicationPool);

        # NOTE(jsd): Collection includes main site.
        # TODO(jsd): is it recursive?
        foreach ($subsite in $mainSite.Collection) {
            if ($subsite.Name -eq "") { continue; }
            $tmp = $IISSiteNames.Add($subsite.Name);
            $tmp = $IISAppPoolNames.Add($subsite.applicationPool);
        }
    }
    
    Write-Host "  Verified";
    Write-Host "";
    Write-Host "  Stopping IIS sites...";

    foreach ($name in $IISSiteNames) {
        if ($name -eq "") { continue; }
        Write-Host "    Stopping IIS site '$name'...";
        try {
            $iisSite = Get-Website -Name $name;
            $iisSite.Stop();
        } catch {
            Write-Host -ForegroundColor Red "$_";
        }
    }
    foreach ($name in $IISAppPoolNames) {
        if ($name -eq "") { continue; }
        Write-Host "    Stopping IIS app pool '$name'...";
        try {
            $iisAppPool = Get-Item "IIS:\AppPools\$name";
            $iisAppPool.Stop();
        } catch {
            Write-Host -ForegroundColor Red "$_";
        }
    }

    Write-Host "  Waiting for IIS sites to stop...";
    Start-Sleep -Seconds 2;

    Write-Host "";
    Write-Host "  Deploying new code to IIS sites...";

    foreach ($site in $sites) {
        Deploy-Site $site["_IISSite"] $site["TargetFolder"] $site["_SourcePath"];
    }

    Write-Host "";
    Write-Host "  Starting IIS sites...";
    
    foreach ($name in $IISAppPoolNames) {
        if ($name -eq "") { continue; }
        Write-Host "    Starting IIS app pool '$name'...";
        try {
            $iisAppPool = Get-Item "IIS:\AppPools\$name";
            $iisAppPool.Start();
        } catch {
            Write-Host -ForegroundColor Red "$_";
        }
    }
    foreach ($name in $IISSiteNames) {
        if ($name -eq "") { continue; }
        Write-Host "    Starting IIS site '$name'...";
        try {
            $iisSite = Get-Website -Name $name;
            $iisSite.Start();
        } catch {
            Write-Host -ForegroundColor Red "$_";
        }
    }

    Write-Host "";
    Write-Host "Deployed WebSites";
}

# Handles a "Folders" deployment rule with simple xcopy commands
function Deploy-Folders ($dp)
{
    $tfsBuildName = $dp["TFSBuildName"];

    Write-Host "";
    Write-Host "Deploying Folders from $tfsBuildName...";

    $buildRootPath = [System.IO.Path]::Combine($BuildsDropPath, $tfsBuildName);

    $buildDir = Get-Build-Dir $tfsBuildName $buildRootPath;

    $buildTaskPath = [System.IO.Path]::Combine($buildRootPath, $buildDir);

    Write-Host "  Deploying from: $buildTaskPath";

    # TODO(jsd): Need a more robust way of detecting when the build completes:
    if ([System.IO.Directory]::GetFiles($buildTaskPath).Count -eq 0) {
        throw "  Build directory is empty!";
    }

    $folders = $dp["Folders"];
    foreach ($folder in $folders) {
        $sourcePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($buildTaskPath, $folder["SourceFolder"]));

        # Clear out existing folder and copy to it:
        Clear-And-Copy $sourcePath $folder["TargetFolder"];

        # Update the config files:
        Config-Update $folder["TargetFolder"];
    }

    Write-Host "";
    Write-Host "Deployed Folders";
}



#
# Main script starts here:
#


Import-Module WebAdministration;


# Execute the deployment configuration script which sets $Deploy:
$Deploy = $null;

if (!$ConfigScriptPath) {
    Write-Host "-ConfigScriptPath parameter is required!";
    exit;
}

# Execute the script we're given to get the $Deploy hash:
. $ConfigScriptPath

if ( ($Deploy -eq $null) ) {
    Write-Host "$ConfigScriptPath script must set `$Deploy hash!";
    exit;
}


$BuildsDropPath  = $Deploy["BuildsDropPath"];
$EnvironmentName = $Deploy["EnvironmentName"];

$MachineName = Get-Content env:computername;


Write-Host "Deploying for $EnvironmentName environment on $MachineName machine";

# Handle all deployment rules in the $Deploy hash:
foreach ($dp in $Deploy["Deployments"]) {
    if ($dp["Disabled"]) {
        Write-Host "";
        Write-Host "  Skipping deployment from '$($dp["TFSBuildName"])' because its rule has Disabled = `$true";
        continue;
    }

    # Deploy WebSites:
    try {
        if ($dp["WebSites"]) {
            Deploy-WebSites $dp;
        }
    } catch {
        Write-Host -ForegroundColor Red "$_";
    }

    # Deploy Folders:
    try {
        if ($dp["Folders"])  {
            Deploy-Folders $dp;
        }
    } catch {
        Write-Host -ForegroundColor Red "$_";
    }
}

Write-Host "";
Write-Host "Deployment complete"
