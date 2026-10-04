param (
    [Parameter(Mandatory=$true)]
    [string]$TargetDir,

    [Parameter(Mandatory=$true)]
    [int]$Threshold,         # Порог в % (например, 80)

    [Parameter(Mandatory=$true)]
    [int]$M_Files,

    [Parameter(Mandatory=$true)]
    [string]$BackupDir
)

if (-not (Test-Path -Path $TargetDir -PathType Container)) {
    Write-Error "Error: Folder $TargetDir does not exist."
    exit 1
}

if (-not (Test-Path -Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
    Write-Host "Created backup folder: $BackupDir"
}


$FolderSizeBytes = (Get-ChildItem -Path $TargetDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
if ($null -eq $FolderSizeBytes) { $FolderSizeBytes = 0 }

$DriveLetter = (Get-Item $TargetDir).PSDrive.Name
$Drive = Get-PSDrive -Name $DriveLetter
$TotalDiskBytes = $Drive.Used + $Drive.Free

$UsedPercent = if ($TotalDiskBytes -gt 0) { 
    [math]::Round(($FolderSizeBytes / $TotalDiskBytes) * 100, 2) 
} else { 0 }

Write-Host "Folder: $TargetDir"
Write-Host "Folder usage percentage: ${UsedPercent}%"

if ($UsedPercent -lt $Threshold) {
    Write-Host "Folder size is less than threshold, archiving isnt needed"
    exit
}

Write-Host "Threshold exceeded, starting achiving of $M_Files oldest files..."

$FilesToArchive = Get-ChildItem -Path $TargetDir -File | Sort-Object LastWriteTime | Select-Object -First $M_Files
if ($null -eq $FilesToArchive -or $FilesToArchive.Count -eq 0) {
        Write-Host "No files to archive."
        exit 0
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ArchiveName = "backup_$Timestamp.zip"
$ArchivePath = Join-Path -Path $BackupDir -ChildPath $ArchiveName

$TempDir = Join-Path -Path $env:TEMP -ChildPath "arch_temp_$Timestamp"
New-Item -ItemType Directory -Path $TempDir | Out-Null

try {
    $FilesToArchive | Copy-Item -Destination $TempDir
    Compress-Archive -Path "$TempDir\*" -DestinationPath $ArchivePath -Force

    if (Test-Path $ArchivePath) {
        Write-Host "Archive successfully created: $ArchivePath" -ForegroundColor Green
        Write-Host "Archived files: $($FilesToArchive.Name -join ', ')"
    } else {
        Write-Error "Error creating archive."
    }
}
catch {
    Write-Error "An error occurred: $_"
}
finally {
    if (Test-Path $TempDir) { Remove-Item -Path $TempDir -Recurse -Force }
}