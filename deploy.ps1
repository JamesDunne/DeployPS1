#
# Powershell v3.0 deployment script for Server 2012 OSes to deploy IIS sites
# and custom folders directly from TFS build drop folders.
#

Param (
    # Name of PS1 script that creates $Deploy variable, e.g. "Rules\sample.ps1"
    [Parameter(Mandatory=$true,Position=0)]
    [string] $ConfigScriptPath
);

Import-Module WebAdministration;

# Custom web.config modifications:
function Config-Set-CurrentEnvironment ( [System.Xml.XmlDocument]$doc )
{
    $root = $doc.get_DocumentElement();

    # Set <appSettings> keys according to deployment configuration
    foreach ($item in $root.appSettings.add) {
        if ($item.key -eq "CurrentEnvironment") {
            $item.value = $EnvironmentName;
            "    Updated CurrentEnvironment value = '$EnvironmentName'";
        }
    }
}

function Config-Update ( $path )
{
    # Find web.config:
    $webConfigPath = [System.IO.Path]::Combine( $path, "web.config" );
    if ( [System.IO.File]::Exists( $webConfigPath ) )
    {
        "    Updating '$webConfigPath'";

        [System.Xml.XmlDocument]$doc = new-object System.Xml.XmlDocument;
        $doc.Load($webConfigPath);

        $root = $doc.get_DocumentElement();

        # Change compilation mode to debug="false"  
        $root."system.web".compilation.debug = "false";

        # Add any other automated web.config customizations here.

        # Set CurrentEnvironment:
        Config-Set-CurrentEnvironment $doc;

        $doc.Save($webConfigPath);

        "    Updated '$webConfigPath'";
    }

    # Find *.exe.config files:
    $appConfigFiles = [System.IO.Directory]::GetFiles($path, "*.exe.config");
    foreach ($appConfigPath in $appConfigFiles) {
        "    Updating '$appConfigPath'";

        [System.Xml.XmlDocument]$doc = new-object System.Xml.XmlDocument;
        $doc.Load($appConfigPath);

        # Set CurrentEnvironment:
        Config-Set-CurrentEnvironment $doc;

        $doc.Save($appConfigPath);

        "    Updated '$webConfigPath'";
    }
}

function Clear-And-Copy ( $src, $dest )
{
    # Clear out the target directory:
    "    Clearing existing directory: $dest";
    if ([System.IO.Directory]::Exists($dest)) {
        # Delete the directory recursively:
        Remove-Item -Path $dest -Recurse -Force;

       #[System.IO.Directory]::Delete($dest, $true);
    }
    "";

    "    Copying from '$src' to '$dest'";
    xcopy $src $dest /E /I /C /Q;
}

function Deploy-Site ( $ws, $destRelPath, $srcAbsPath )
{
    $siteName = $ws.Name;
    if ($destRelPath -ne ".") {
        $siteName = $siteName + "/" + $destRelPath;
    }

    "    Deploying to $siteName";

    $dest = [System.IO.Path]::GetFullPath( [System.IO.Path]::Combine($ws.physicalPath, $destRelPath) );

    # Clear out existing folder and copy to it:
    Clear-And-Copy $srcAbsPath $dest;

    # Find the web.config/*.exe.config files and update them accordingly:
    Config-Update $dest;

    "    Deployed to $siteName";
}

function Require-IIS-Website ( $name )
{
    $ws = Get-Website -Name $name;
    if (!$ws) {
        throw "  Could not access IIS data, or site named '$name' does not exist! Try running as Administrator.";
    }
    if ($ws.Name -ne $name) {
        throw "  IIS site named '${ws.Name}' is not named as expected: '$name'!";
    }
    return $ws;
}

function Require-Path-Exists ( $path )
{
    if ( -not [System.IO.Directory]::Exists( $path ) ) {
        throw "  Required folder '$path' does not exist!";
    }
}

function Deploy-WebSites ( $dp )
{
    $tfsBuildName = $dp["TFSBuildName"];

    "";
    "Deploying WebSites from $tfsBuildName...";

    $buildRootPath = [System.IO.Path]::Combine($BuildsDropPath, $tfsBuildName);

    "  Detecting latest build directory in '$buildRootPath'...";

    $buildDir = (new-object System.IO.DirectoryInfo($buildRootPath)).GetDirectories() |
        Sort-Object LastWriteTime -descending |
        Select-Object -first 1;

    if ($buildDir -eq $null) {
        throw "  Error detecting latest build directory from '$buildRootPath'";
    }

    "  Successfully detected latest build: $buildDir";
    "";

    $buildSitesPath = [System.IO.Path]::Combine($buildRootPath, [System.IO.Path]::Combine($buildDir, "_PublishedWebsites"));

    $sites = $dp["WebSites"];

    # Check that build folder paths exist (build might not be completed yet):
    "  Verifying build is complete...";

    foreach ($site in $sites) {
        # Construct the final source path:
        $site["_SourcePath"] = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::Combine($buildSitesPath, [System.IO.Path]::Combine($site["SourceSite"], $site["SourceFolder"]))
        );

        # Require that the source path exists:
        Require-Path-Exists $site["_SourcePath"];
    }

    "  Verified";
    "";
    "  Verifying IIS configuration...";

    foreach ($site in $sites) {
        # Require that the target IIS site name exists:
        $site["_IISSite"] = Require-IIS-Website $site["TargetSite"];
    }
    
    "  Verified";
    "";
    "  Stopping IIS sites...";

    foreach ($site in $sites) {
        $site["_IISSite"].Stop();
    }

    "";
    "  Deploying new code to IIS sites...";

    foreach ($site in $sites) {
        Deploy-Site $site["_IISSite"] $site["TargetFolder"] $site["_SourcePath"];
    }

    "";
    "  Starting IIS sites...";
    
    foreach ($site in $sites) {
        $site["_IISSite"].Start();
    }

    "";
    "Deployed WebSites";
}

function Deploy-Folders ($dp)
{
    $tfsBuildName = $dp["TFSBuildName"];

    "";
    "Deploying Folders from $tfsBuildName...";

    $buildRootPath = [System.IO.Path]::Combine($BuildsDropPath, $tfsBuildName);

    "  Detecting latest build directory in '$buildRootPath'...";

    $buildDir = (new-object System.IO.DirectoryInfo($buildRootPath)).GetDirectories() |
        Sort-Object LastWriteTime -descending |
        Select-Object -first 1;

    if ($buildDir -eq $null) {
        throw "  Error detecting latest build directory from '$buildRootPath'";
    }

    "  Successfully detected latest build: $buildDir";

    $buildTaskPath = [System.IO.Path]::Combine($buildRootPath, $buildDir);

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

    "";
    "Deployed Folders";
}

#
# Script Starts Here:
#

# Execute the deployment configuration script which sets $Deploy:
$Deploy = $null;

if (!$ConfigScriptPath) {
    "-ConfigScriptPath parameter is required!";
    exit;
}

. $ConfigScriptPath

if ( ($Deploy -eq $null) ) {
    "$ConfigScriptPath script must set `$Deploy hash!";
    exit;
}

$BuildsDropPath  = $Deploy["BuildsDropPath"];
$EnvironmentName = $Deploy["EnvironmentName"];

$MachineName = Get-Content env:computername;

"Deploying for $EnvironmentName environment on $MachineName machine";

foreach ($dp in $Deploy["Deployments"]) {
    if ($dp["Disabled"]) {
        "";
        "  Skipping deployment from '$($dp["TFSBuildName"])' due to Disabled = `$true";
        continue;
    }

    # Deploy WebSites:
    try {
        if ($dp["WebSites"]) { Deploy-WebSites $dp; }
    } catch {
        "$_";
    }

    # Deploy Folders:
    try {
        if ($dp["Folders"])  { Deploy-Folders $dp; }
    } catch {
        "$_";
    }
}

"";
"Deployment complete"
