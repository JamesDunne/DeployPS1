
$cred = @{
    "Username" = "DOMAIN\username";
    "Password" = 'password';
};

$config = @{
    "pools" = @{
        "PoolName1" = @{
            "Credentials" = $cred;
        };
    };
    "sites" = @{
        "SiteName1" = @{
            "Pool" = "PoolName1";
            "Path" = "C:\inetpub\wwwroot\SiteName1";
            "Bindings" = @(@{ protocol = "http"; bindingInformation = "192.168.1.100:80:"; });
            "Applications" = @{
                "App1" = @{
                    "Pool" = "PoolName1";
                    "Path" = "C:\inetpub\wwwroot\SiteName1\App1";
                };
            };
        };
    };
};
