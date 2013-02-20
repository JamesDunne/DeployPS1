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

As you can see, this script is just regular PowerShell code. The script could theoretically do anything
it likes, but for best results it should obviously limit itself to just defining this required `$Deploy`
hash.

First up is the "BuildsDropPath" key. This value is simply a UNC path to where TFS drops your completed
builds. It technically doesn't have to be a TFS drop folder, but all it needs to do is conform to the
conventions established by TFS when it produces the xcopy-able output of a solution. These conventions are:

    {BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}
    {BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}\_PublishedWebsites
    {BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}\_PublishedWebsites\{SiteName1}
    {BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}\_PublishedWebsites\{SiteName2}

The "EnvironmentName" key is used to define the name of the environment being deployed to.

Now, the "Deployments" key is simply an array of hashes used to describe the deployment operations to complete.

Each hash has a `TFSBuildName` and any combination of `WebSites` and `Folders` keys.

The `TFSBuildName` key is used in the constructed UNC path to the TFS build drop folder to discover the latest
completed date-stamped build folder.

For an IIS web site deployment, the `WebSites` key is used to describe an array of hashes, each describing a
particular deployment scenario. These deployments are fairly simply `xcopy` jobs with keys to describe the Source
and Target folder locations.

The `TargetSite` is the local IIS name of the website to deploy to. The WebAdministration module is used to look up
the IIS site's physical folder path. The `SourceSite` is the name of the TFS build's folder name, which may or may not
be identical to the IIS site's name, depending on your IIS configuration and your solution's website project name.

The `SourceFolder` and `TargetFolder` are used to identify subfolders of the web sites to copy; usually you'll just default
these to "." (the root directory). If you have a more complex IIS setup involving virtual directories, you'll want to
set `TargetFolder` to the virtual directory names and reuse the same `TargetSite` name of the root IIS site containing
the virtual directories.

For regular folder xcopy deployment not involving IIS, there's the "Folders" key which is quite simple. There's
SourceFolder (relative to TFS build path) and TargetFolder (absolute path) which determine where to xcopy from and to.
This deployment type is great for deploying simple console applications and Windows services. They don't need much
extra work beyond just an xcopy.

I would recommend maintaining separate rules scripts for each environment you deploy to. That will make maintenance
simple.

The general xcopy logic for web site deployment is:

    xcopy "{BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}\_PublishedWebsites\{SourceSite}\{SourceFolder}" "{TargetSite.IISPath}\{TargetFolder}" /E /C /I /Q

The general xcopy logic for folder deployment is:

    xcopy "{BuildsDropPath}\{TFSBuildName}\{DateStampedBuild}\{SourceFolder}" "{TargetFolder}" /E /C /I /Q

For web site deployments, all mentioned IIS sites are stopped first, all are then deployed to, and all are finally restarted.

Notes
=====

**A fair warning:**  This script does a **full clean** of the target deployment folder before deploying from the source.
If this causes you grief for your setup (e.g. you have LOG files living in your target folder), you'll very much want to
be aware of this fact.

The tool is blunt in this respect, and I don't plan to change it. Feel free to fork the project and provide a solution
to this problem if you need to solve it.

The `deploy.ps1` script is coded to make certain kinds of changes to deployed copies of `web.config` files. Make sure to
review this code and ensure these modifications are to your liking.

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
