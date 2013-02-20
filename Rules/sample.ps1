
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
