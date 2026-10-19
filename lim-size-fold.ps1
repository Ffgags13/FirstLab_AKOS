param(
    [Parameter(Mandatory=$true)]
    [string]$TargetDir,

    [Parameter(Mandatory=$true)]
    [string]$Size,

    [string]$VhdPath,

    [string]$MountLetter
)

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "Administrator rights required."
    exit 1
}

if ($Size -notmatch '^\s*(\d+(?:\.\d+)?)\s*(KB|MB|GB|TB)\s*$') {
    Write-Error "Invalid size format. Example: 100MB, 2GB"
    exit 1
}
$num  = [double]$Matches[1]
$unit = $Matches[2].ToUpper()

switch ($unit) {
    'KB' { $SizeBytes = [int64]($num * 1KB) }
    'MB' { $SizeBytes = [int64]($num * 1MB) }
    'GB' { $SizeBytes = [int64]($num * 1GB) }
    'TB' { $SizeBytes = [int64]($num * 1TB) }
}

if ($SizeBytes -lt 10MB) {
    Write-Error "Minimum VHD size is 10 MB."
    exit 1
}

$TargetDir = [System.IO.Path]::GetFullPath($TargetDir)

if (Test-Path $TargetDir) {
    $item = Get-Item $TargetDir
    if ($item.LinkType -eq "Junction") {
        Write-Error "TargetDir is already a junction: $TargetDir -> $($item.Target)"
        exit 1
    }
}

if (-not $VhdPath) {
    $parentDir = Split-Path -Path $TargetDir -Parent
    $leafName  = Split-Path -Path $TargetDir -Leaf

    if ([string]::IsNullOrWhiteSpace($parentDir)) {
        $parentDir = Split-Path -Path $TargetDir -Qualifier
    }
    if ([string]::IsNullOrWhiteSpace($parentDir) -or [string]::IsNullOrWhiteSpace($leafName)) {
        Write-Error "Cannot determine VHD path. Specify -VhdPath explicitly."
        exit 1
    }
    $VhdPath = Join-Path -Path $parentDir -ChildPath ($leafName + ".vhd")
}

$VhdPath = [System.IO.Path]::GetFullPath($VhdPath)

if (Test-Path $VhdPath) {
    Write-Error "VHD already exists: $VhdPath"
    exit 1
}

$vhdParent = Split-Path -Path $VhdPath -Parent
if (-not (Test-Path -Path $vhdParent -PathType Container)) {
    Write-Error "Parent directory for VHD does not exist: $vhdParent"
    exit 1
}

$vhdDrive = (Get-Item $vhdParent).PSDrive
$freeBytes = (Get-PSDrive -Name $vhdDrive.Name).Free

$existingSize = 0
if (Test-Path $TargetDir) {
    $existingSize = (Get-ChildItem -Path $TargetDir -Recurse -File -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
    if ($null -eq $existingSize) { $existingSize = 0 }
}

if ($existingSize -gt $SizeBytes) {
    Write-Error ("Existing data ({0:N2} MB) is larger than VHD size ({1:N2} MB). Increase -Size." -f `
                 ($existingSize/1MB), ($SizeBytes/1MB))
    exit 1
}

if ($freeBytes -lt $SizeBytes) {
    Write-Error ("Not enough free space. Available: {0:N2} MB, required: {1:N2} MB" -f `
                 ($freeBytes/1MB), ($SizeBytes/1MB))
    exit 1
}

if (-not $MountLetter) {
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($c in 'V','W','X','Y','Z','T','S','R','Q','P','O','N','M','L','K','J','I','H','G','F','E','D') {
        if ($c -notin $used) { $MountLetter = $c; break }
    }
    if (-not $MountLetter) {
        Write-Error "No free drive letter. Specify -MountLetter."
        exit 1
    }
}
$MountLetter = $MountLetter.TrimEnd(':').ToUpper() + ":"

Write-Host "Creating VHD: $VhdPath ($Size)"
New-VHD -Path $VhdPath -SizeBytes $SizeBytes -Dynamic | Out-Null

Write-Host "Mounting VHD..."
$disk = Mount-VHD -Path $VhdPath -Passthru | Get-Disk

Initialize-Disk -Number $disk.Number -PartitionStyle MBR -ErrorAction SilentlyContinue
New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $MountLetter.TrimEnd(':') | Out-Null
Format-Volume -DriveLetter $MountLetter.TrimEnd(':') -FileSystem NTFS -NewFileSystemLabel "LimitedStore" -Confirm:$false | Out-Null

Start-Sleep -Seconds 1

$innerFolder = Join-Path "$MountLetter\" (Split-Path $TargetDir -Leaf)
New-Item -ItemType Directory -Path $innerFolder -Force | Out-Null

if (Test-Path $TargetDir) {
    $nonEmpty = Get-ChildItem -Path $TargetDir -Force -ErrorAction SilentlyContinue
    if ($nonEmpty) {
        Write-Host "Copying existing data into VHD..."
        try {
            $rc = Start-Process -FilePath "robocopy.exe" `
                -ArgumentList "`"$TargetDir`" `"$innerFolder`" /E /COPYALL /R:2 /W:2 /NFL /NDL /NP" `
                -Wait -PassThru -NoNewWindow
            if ($rc.ExitCode -ge 8) {
                throw "robocopy failed with exit code $($rc.ExitCode)"
            }
            Write-Host "Copy completed."
        }
        catch {
            Write-Error "Failed to copy existing data into VHD: $_"
            Dismount-VHD -Path $VhdPath -ErrorAction SilentlyContinue
            Remove-Item -Path $VhdPath -Force -ErrorAction SilentlyContinue
            exit 1
        }
    }
}

if (Test-Path $TargetDir) {
    Remove-Item -Path $TargetDir -Force -Recurse
}

cmd /c mklink /J "$TargetDir" "$innerFolder" | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create junction $TargetDir -> $innerFolder"
    exit 1
}

Write-Host "Done."
Write-Host "  Folder: $TargetDir"
Write-Host "  VHD:    $VhdPath"
Write-Host "  Size:   $Size"
Write-Host "  Drive:  $MountLetter"