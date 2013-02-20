Deploy.PS1
==========

Custom PowerShell deployment script for IIS7+

To run the script, simply invoke it from a PowerShell prompt like so:

`.\deploy.ps1 .\Rules\sample.ps1`

The first argument is the name of a rules script.

Rules Scripts
=============

A rules script defines the `$Deploy` hash which describes what deployment steps to take. It's the data
used by the main deployment engine.

The `$Deploy` hash is a very simple format; it's what I'll term a PSON (PowerShell Object Notation), a play on JSON (JavaScript Object Notation).

Let's take a look at the example rules file (in Rules/sample.ps1) and explain it bit by bit:

    $Deploy = @{
        # Default TFS build drop folder:
        "BuildsDropPath"         = "\\TFSDropServer\Builds";

        # Set appSettings/CurrentEnvironment in web.config files to this:
        "EnvironmentName"        = "Development";

        # The list of deployments to make:
        "Deployments" = @(
            @{
                # TFS Build Name to source from:
                "TFSBuildName" = "TestWebSites";
                # Deploy Web Sites to IIS:
                "WebSites" = @(
                    @{
                        "SourceSite"   = "TestSite1";
                        "SourceFolder" = ".";
                        "TargetSite"   = "TestSite1";
                        "TargetFolder" = ".";
                    },
                    @{
                        "SourceSite"   = "TestSite2";
                        "SourceFolder" = ".";
                        "TargetSite"   = "TestSite2";
                        "TargetFolder" = ".";
                    }
                );
            },
            @{
                # TFS Build Name to source from:
                "TFSBuildName" = "TestConsoleApp";
                # Just xcopy folders:
                "Folders" = @(
                    @{
                        "SourceFolder" = ".";
                        "TargetFolder" = "C:\Apps\TestConsoleApp";
                    }
                );
            }
        );
    };

As you can see, this script is just regular PowerShell code. The script could theoretically do anything it likes, but
for best results it should obviously limit itself to just defining this required `$Deploy` hash.

For those not familiar with PowerShell syntax, `@{ a = 1; b = 2; }` defines a hash of key/value pairs and
`@( a, b, c )` defines an array (list) of objects. Hashes and arrays are very generic data structures, useful for
describing most kinds of simplistic configuration data.

First up is the `BuildsDropPath` key. Its value is simply a UNC path to where TFS drops your completed builds. It
technically doesn't have to be a TFS drop folder; all it needs to do is conform to the conventions established by
TFS when it produces the xcopy-able output of a solution.

The general format of a TFS drop folder looks like (assuming you have website projects in your solution):

    {BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}
    {BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}\_PublishedWebsites
    {BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}\_PublishedWebsites\{SiteName1}
    {BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}\_PublishedWebsites\{SiteName2}

The `EnvironmentName` key is used to define the name of the environment being deployed to. This is a remnant of our
own configuration system which you may not need to use.

The `Deployments` key is simply an `array` of `hash`es used to describe the deployment operations to complete. Each
hash has a `TFSBuildName` and any combination of the `WebSites` and `Folders` keys.

The `TFSBuildName` key is used to form part of the final source UNC path to xcopy from. Within each parent TFS build
folder is a list of date-stamped build folders. The date-stamped folder with the latest-modified date is selected.

For an IIS web site deployment, the `WebSites` key is used to describe an array of hashes, each describing a
particular deployment scenario. These deployments are fairly simple `xcopy` jobs with keys to describe the source
and target folder locations.

The `TargetSite` is the local IIS name of the website to deploy to. The WebAdministration module is used to look up
the IIS site's physical folder path. The `SourceSite` is the name of the site found in the TFS build folder. Usually it
will be the name of the website project found in your solution.

The `SourceFolder` and `TargetFolder` are used to identify subfolders of the web sites to copy; usually you'll just
default these to "." (the root directory). If you have a more complex IIS setup involving virtual directories, you'll
want to set `TargetFolder` to the virtual directory names and reuse the same `TargetSite` name of the root IIS site
containing the virtual directories.

For regular folder xcopy deployment not involving IIS, there's the `Folders` deployment type. There's
`SourceFolder` (relative to TFS build path) and `TargetFolder` (absolute path) which determine where to xcopy from
and to. This deployment type is great for deploying simple console applications and Windows services.

The xcopy logic for `WebSites` deployment is:

    xcopy "{BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}\_PublishedWebsites\{SourceSite}\{SourceFolder}" "{TargetSite.IISPath}\{TargetFolder}" /E /C /I /Q

The xcopy logic for `Folders` deployment is:

    xcopy "{BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}\{SourceFolder}" "{TargetFolder}" /E /C /I /Q

For web site deployments, all mentioned IIS sites are stopped first, all are then deployed to, and all are finally restarted.

In order to avoid deploying partially complete builds, the source folders are verified to exist before deployment starts.

I would recommend maintaining separate rules scripts for each environment you deploy to. That will make maintenance
simple.

Notes
=====

**FAIR WARNING:**  This script does a **full clean** of the target deployment folder before deploying from the source.
If this causes you grief for your setup (e.g. you have LOG files living in your target folder), you'll very much want to
be aware of this fact. The tool is blunt in this respect, and I don't plan to change it. Feel free to fork the project and provide a solution
to this problem if you need to solve it.

The `deploy.ps1` script is coded to make certain kinds of changes to deployed copies of `web.config` files. Make sure to
review this code and ensure these modifications are to your liking. Feel free to add customizations to this as appropriate
to your projects. Perhaps in a future release I will add logic to make `web.config` modifications driven by rules scripts.

The `deploy.ps1` script assumes the following:

 * PowerShell v3.0 is installed
 * Current machine is Windows Server 2008 R2 and up
 * PowerShell's execution policy is set to `Unrestricted`
   * Run `Set-ExecutionPolicy Unrestricted` as administrator
 * For web deployments:
   * IIS7+ is installed on current machine (if you desire web deployments)
   * `WebAdministration` PowerShell module is installed
   * All deployed-to IIS sites are on the same machine as the deploy.ps1 script is
   * web.config modifications are allowed
 * Running with administrator privileges
 * Running with network credentials which have access to your configured TFS build drop network shared folder
