<#
.SYNOPSIS
Deploys an ASP .NET Core Web Application into a docker container running in a specified Docker machine.

.DESCRIPTION
The following script will execute a set of Docker commands against the designated dockermachine.

.PARAMETER Build
Builds the containers using docker-compose build.

.PARAMETER Clean
Clears out any running containers (docker-compose kill, docker-compose rm -f).

.PARAMETER Exec
Executes a command in the container using docker exec.

.PARAMETER GetUrl
Gets the url for the site to open.

.PARAMETER WaitForUrl
Waits for url to respond.

.PARAMETER Run
Removes any conflicting containers running on the same port, then instances the containers using docker-compose up.

.PARAMETER Environment
Specifies the configuration under which the project will be built and run (Debug or Release).

.PARAMETER Machine
Specifies the docker machine name to connect to.

.PARAMETER ProjectFolder
Specifies the project folder, defaults to the parent of the directory containing this script.

.PARAMETER ProjectName
Specifies the project name used by docker-compose, defaults to the name of $ProjectFolder.

.PARAMETER NoCache
Specifies the build argument --no-cache.

.PARAMETER OpenSite
Specifies whether to launch the site once the docker container is running, defaults to $True.

.PARAMTETER RemoteDebugging
Specifies if remote debugging is needed, defaults to $False.

.PARAMTETER ClrDebugVersion
Specifies the version of the debugger, defaults to 'VS2015U2'.

.PARAMTETER Command
Specifies the command to run in the container.

.INPUTS
None. You cannot pipe inputs to DockerTask.

.EXAMPLE
When invoked from the root directory of your project, will compose up the project into the docker-machine instance named 'default', but won't open a browser.
C:\PS> .\Docker\DockerTask.ps1 -Run -Environment Debug -Machine default -OpenSite $False

.LINK
http://aka.ms/DockerToolsForVS
#>

Param(
    [Parameter(ParameterSetName = "Build", Position = 0, Mandatory = $True)]
    [switch]$Build,
    [Parameter(ParameterSetName = "Clean", Position = 0, Mandatory = $True)]
    [switch]$Clean,
    [Parameter(ParameterSetName = "Run", Position = 0, Mandatory = $True)]
    [switch]$Run,
    [Parameter(ParameterSetName = "Exec", Position = 0, Mandatory = $True)]
    [switch]$Exec,
    [Parameter(ParameterSetName = "GetUrl", Position = 0, Mandatory = $True)]
    [switch]$GetUrl,
    [Parameter(ParameterSetName = "WaitForUrl", Position = 0, Mandatory = $True)]
    [switch]$WaitForUrl,
    [parameter(ParameterSetName = "Clean", Position = 1, Mandatory = $True)]
    [parameter(ParameterSetName = "Build", Position = 1, Mandatory = $True)]
    [parameter(ParameterSetName = "Run", Position = 1, Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [String]$Environment,
    [parameter(ParameterSetName = "Clean", Position = 2, Mandatory = $False)]
    [parameter(ParameterSetName = "Build", Position = 2, Mandatory = $False)]
    [parameter(ParameterSetName = "Run", Position = 2, Mandatory = $False)]
    [parameter(ParameterSetName = "Exec", Position = 1, Mandatory = $False)]
    [Parameter(ParameterSetName = "GetUrl", Position = 1, Mandatory = $False)]
    [Parameter(ParameterSetName = "WaitForUrl", Position = 1, Mandatory = $False)]
    [String]$Machine,
    [parameter(ParameterSetName = "Clean", Position = 3, Mandatory = $False)]
    [parameter(ParameterSetName = "Build", Position = 3, Mandatory = $False)]
    [parameter(ParameterSetName = "Run", Position = 3, Mandatory = $False)]
    [parameter(ParameterSetName = "Exec", Position = 2, Mandatory = $False)]
    [ValidateNotNullOrEmpty()]
    [String]$ProjectFolder = (Split-Path -Path $MyInvocation.MyCommand.Definition | Split-Path),
    [parameter(ParameterSetName = "Clean", Position = 4, Mandatory = $False)]
    [parameter(ParameterSetName = "Build", Position = 4, Mandatory = $False)]
    [parameter(ParameterSetName = "Run", Position = 4, Mandatory = $False)]
    [parameter(ParameterSetName = "Exec", Position = 3, Mandatory = $False)]
    [ValidateNotNullOrEmpty()]
    [String]$ProjectName = (Split-Path -Path (Resolve-Path $ProjectFolder) -Leaf).ToLowerInvariant(),
    [parameter(ParameterSetName = "Build", Position = 5, Mandatory = $False)]
    [switch]$NoCache,
    [parameter(ParameterSetName = "Run", Position = 5, Mandatory = $False)]
    [bool]$OpenSite = $True,
    [parameter(ParameterSetName = "Run", Position = 6, Mandatory = $False)]
    [bool]$RemoteDebugging = $False,
    [parameter(ParameterSetName = "Build", Position = 6, Mandatory = $False)]
    [String]$ClrDebugVersion = "VS2015U2",
    [parameter(ParameterSetName = "Exec", Position = 4, Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [String]$Command
)

$ErrorActionPreference = "Stop"

# Calculate the name of the image created by the compose file
$ImageName = "${ProjectName}_musicstore"

# Kills all containers using an image, removes all containers using an image, and removes the image.
function Clean () {
    $composeFileName = Join-Path $ProjectFolder (Join-Path Docker "docker-compose.$Environment.yml")

    if (Test-Path $composeFileName) {
        Write-Host "Cleaning image $ImageName"

        cmd /c docker-compose -f $composeFileName -p $ProjectName kill "2>&1"
        if ($? -eq $False) {
            Write-Error "Failed to kill the running containers"
        }

        cmd /c docker-compose -f $composeFileName -p $ProjectName rm -f "2>&1"
        if ($? -eq $False) {
            Write-Error "Failed to remove the stopped containers"
        }

        $ImageNameRegEx = "\b$ImageName\b"

        # If $ImageName exists remove it
        docker images | select-string -pattern $ImageNameRegEx | foreach {
            $imageName = $_.Line.split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)[0];
            $tag = $_.Line.split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)[1];
            Write-Host "Removing image ${imageName}:$tag";
            docker rmi ${imageName}:$tag *>&1 | Out-Null
        }
    }
    else {
        Write-Error -Message "$Environment is not a valid parameter. File '$composeFileName' does not exist." -Category InvalidArgument
    }
}

# Runs docker build.
function Build () {
    $composeFileName = Join-Path $ProjectFolder (Join-Path Docker "docker-compose.$Environment.yml")

    if (Test-Path $composeFileName) {
        $buildArgs = ""
        if ($NoCache)
        {
            $buildArgs = "--no-cache"
        }

        cmd /c docker-compose -f $composeFileName -p $ProjectName build $buildArgs "2>&1"
        if ($? -eq $False) {
            Write-Error "Failed to build the image"
        }

        $tag = [System.DateTime]::Now.ToString("yyyy-MM-dd_HH-mm-ss")

        cmd /c docker tag $ImageName ${ImageName}:$tag "2>&1"
        if ($? -eq $False) {
            Write-Error "Failed to tag the image"
        }
    }
    else {
        Write-Error -Message "$Environment is not a valid parameter. File '$composeFileName' does not exist." -Category InvalidArgument
    }
}

# Runs docker run
function Run () {
    $composeFileName = Join-Path $ProjectFolder (Join-Path Docker "docker-compose.$Environment.yml")

    if (Test-Path $composeFileName) {
        $conflictingContainerIds = $(docker ps -a | select-string -pattern ":80->" | foreach { Write-Output $_.Line.split()[0] })

        if ($conflictingContainerIds) {
            $conflictingContainerIds = $conflictingContainerIds -Join ' '
            Write-Host "Stopping conflicting containers using port 80"
            $stopCommand = "docker stop $conflictingContainerIds"
            cmd /c $stopCommand "2>&1"
        }

        cmd /c docker-compose -f $composeFileName -p $ProjectName up -d "2>&1"
        if ($? -eq $False) {
            Write-Error "Failed to build the images"
        }
    }
    else {
        Write-Error -Message "$Environment is not a valid parameter. File '$composeFileName' does not exist." -Category InvalidArgument
    }

    OpenSite
}

# Opens the remote site
function OpenSite () {
    # If we're going to debug, the server won't start immediately; don't need to wait for it.
    if (-not $RemoteDebugging)
    {
        $uri = GetUrl

        WaitForUrl $uri

        # Open the site.
        if ($OpenSite) {
            Start-Process $uri
        }
    }
    else
    {
        # Give the container 10 seconds to get ready
        Start-Sleep 10
    }
}

# Runs docker run
function Exec () {
    $containerId = (docker ps -f "name=${ImageName}" -q -n=1)
    if ([System.String]::IsNullOrWhiteSpace($containerId)) {
        Write-Error "Could not find a container for Image $ImageName"
    }
    $shellCommand = "docker exec -i $containerId $Command"
    Invoke-Expression $shellCommand
}

# Gets the Url of the remote container
function GetUrl () {
    if ([System.String]::IsNullOrWhiteSpace($Machine)) {
        return "http://docker"
    }
    else {
        "http://$(docker-machine ip $Machine)"
    }
}

# Checks if the URL is responding
function WaitForUrl ([string]$uri) {
    Write-Host "Opening site $uri " -NoNewline
    $status = 0
    $count = 0

    #Check if the site is available
    while ($status -ne 200 -and $count -lt 300) {
        try {
            $response = Invoke-WebRequest -Uri $uri -Headers @{"Cache-Control"="no-cache";"Pragma"="no-cache"} -UseBasicParsing
            $status = [int]$response.StatusCode
        }
        catch [System.Net.WebException] { }
        if($status -ne 200) {
            Write-Host "." -NoNewline
            # Wait Time max. 5 minutes (300 sec.)
            Start-Sleep 1
            $count += 1
        }
    }
    Write-Host
}

if (![System.String]::IsNullOrWhiteSpace($Machine)) {
# Set the environment variables for the docker machine to connect to
    docker-machine env $Machine --shell powershell | Invoke-Expression
}

# Need the full path of the project for mapping
$ProjectFolder = Resolve-Path $ProjectFolder

$users = Split-Path $env:USERPROFILE -Parent
if (!$ProjectFolder.StartsWith($users, [StringComparison]::InvariantCultureIgnoreCase)) {
   $message  = "VirtualBox by default shares C:\Users as c/Users. If the project is not under c:\Users, please manually add it to the shared folders on VirtualBox. "`
             + "Follow instructions from https://www.virtualbox.org/manual/ch04.html#sharedfolders"
   Write-Warning -Message $message
}
else {
   if (!$ProjectFolder.StartsWith($users, [StringComparison]::InvariantCulture)) {
      # If the project is under C:\Users, fix the casing if necessary. Path in Linux is case sensitive and the default shared folder c/Users
      # on VirtualBox can only be accessed if the project folder starts with the correct casing C:\Users as in $env:USERPROFILE
      $ProjectFolder = $users + $ProjectFolder.Substring($users.Length)
   }
}

$env:CLRDBG_VERSION = $ClrDebugVersion

if ($RemoteDebugging) {
    $env:REMOTE_DEBUGGING = 1
}
else {
    $env:REMOTE_DEBUGGING = 0
}

# Call the correct functions for the parameters that were used
if ($Clean) {
    Clean
}
if ($Build) {
    Build
}
if ($Run) {
    Run
}
if ($Exec) {
    Exec
}
if ($GetUrl) {
    GetUrl
}
if ($WaitForUrl) {
    WaitForUrl (GetUrl)
}
