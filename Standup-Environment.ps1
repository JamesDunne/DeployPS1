# This script stands up an IIS environment
#

Param (
    [Parameter(Mandatory=$true,Position=0)]
    [string] $ConfigScriptPath
)

# Must stop on all errors:
$ErrorActionPreference = "Stop";

function Setup-ApplicationPools ( $pools ) {
    foreach ($poolName in $pools.Keys) {
        # Create the Application Pool if it doesn't exist:
        "$poolName";
        try {
            $pool = Get-Item "IIS:\AppPools\$poolName" -ErrorAction SilentlyContinue;
        } catch {
            $pool = $null;
        }

        if ($pool -eq $null) {
            "   Creating pool...";
            try {
                $pool = New-WebAppPool -Name $poolName;
            } catch {
                "Failed to create pool: $_";
                break;
            }

            $creds = $pools[$poolName]["Credentials"];
            if ($creds -ne $null) {
                "   Assigning credentials...";
                try {
                    Set-ItemProperty "IIS:\AppPools\$poolName" -Name managedRuntimeVersion "v4.0";
                    Set-ItemProperty "IIS:\AppPools\$poolName" -Name autoStart "true";

                    Set-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.identityType "SpecificUser";
                    Set-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.userName ($creds["Username"]);
                    Set-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.password ($creds["Password"]);
                } catch {
                    "$_";
                    break;
                }
            }
        }
    }
}

function Setup-Sites ( $sites ) {
    foreach ($siteName in $sites.Keys) {
        "$siteName";
        $siteConfig = $sites[$siteName];

        $poolName = $siteConfig["Pool"];
        $path = $siteConfig["Path"];
        $bindings = $siteConfig["Bindings"];

        try {        
            $site = Get-Item "IIS:\Sites\$siteName" -ErrorAction SilentlyContinue;
        } catch {
            $site = $null;
        }

        # Create the site if it doesn't exist:
        if ($site -eq $null) {
            mkdir -Path $path -Force | Out-Null;
            "    Creating site...";
            try {
                $site = New-Item "IIS:\Sites\$siteName" -ApplicationPool $poolName -PhysicalPath $path -Bindings $bindings;
            } catch {
                "Failed to create site: $_";
                break;
            }

            # Create applications for this site:
            $apps = $siteConfig["Applications"];
            if ($apps -ne $null) {
                "    Creating applications...";
                foreach ($appName in $apps.Keys) {
                    $app = $apps[$appName];

                    $appPath = $app["Path"];
                    $appPool = $app["Pool"];

                    try {
                        $siteApp = Get-WebApplication -Site $siteName -Name $appName -ErrorAction SilentlyContinue;
                    } catch {
                        $siteApp = $null;
                    }

                    if ($siteApp -eq $null) {
                        mkdir -Path $appPath -Force | Out-Null;
                        $siteApp = New-WebApplication -Site $siteName -Name $appName -ApplicationPool $appPool -PhysicalPath $appPath;
                    }
                }
            }
        }
    }
}


# Main script:

Import-Module WebAdministration;

. $ConfigScriptPath;

if ($config -eq $null) {
    "$ConfigScriptPath needs to set `$config!";
    exit;
}

"Creating application pools...";
Setup-ApplicationPools ($config["pools"]);

"Creating sites...";
Setup-Sites ($config["sites"]);

"Done";
