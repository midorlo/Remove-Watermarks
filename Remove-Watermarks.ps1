<#
.SYNOPSIS
    Removes invisible watermarks (zero-width characters and special patterns) from text files.
.DESCRIPTION
    This script recursively scans a directory for actual text files (using content inspection),
    respects .gitignore rules and hidden attributes (unless -Force is used), and performs the following on each file:
      1) Removes all Unicode format characters (Unicode category Cf)
      2) Removes known zero-width characters as a fallback
      3) Replaces common Cyrillic homoglyphs with their Latin equivalents
    Optionally converts line endings:
      - With -CLRF, converts lone LF ("\n" without a preceding "\r") to CRLF ("\r\n").
      - With -LF, converts all CRLF ("\r\n") to simple LF ("\n").
    With -Touch, restores the original LastWriteTime timestamp after cleaning.
    Use -Verbose for detailed information about each processing step.
.PARAMETER Path
    The root directory to start processing.
.PARAMETER WhatIf
    Shows which files would be modified without actually writing changes.
.PARAMETER Force
    Ignores .gitignore rules and hidden file/folder attributes.
.PARAMETER CLRF
    When set, converts lone LF line endings ("\n" without preceding "\r") to CRLF ("\r\n").
.PARAMETER LF
    When set, converts all CRLF line endings ("\r\n") to lone LF ("\n").
.PARAMETER Touch
    When set, restores the original LastWriteTime timestamp after writing the cleaned file.
.PARAMETER Verbose
    Standard PowerShell verbose switch for detailed output.
.EXAMPLE
    # Dry run with verbose output
    .\Remove-Watermarks.ps1 -Path C:\Projects\MyRepo -WhatIf -Verbose

    # Clean files, convert to LF, restore timestamp, verbose
    .\Remove-Watermarks.ps1 -Path C:\Projects\MyRepo -LF -Touch -Verbose

.INPUTS
    None
.OUTPUTS
    None
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$WhatIf,
    [switch]$Force,
    [switch]$CLRF,
    [switch]$LF,
    [switch]$Touch
)

# Cache for .gitignore patterns
$gitignoreCache = @{}

# Cache for write permission checks
$writePermissionCache = @{}

function Get-GitIgnorePatterns {
    param([string]$Directory)
    if ($gitignoreCache.ContainsKey($Directory)) {
        return $gitignoreCache[$Directory]
    }
    $file = Join-Path $Directory '.gitignore'
    $patterns = @()
    if (Test-Path $file) {
        $patterns = Get-Content $file | Where-Object { $_ -and -not $_.TrimStart().StartsWith('#') }
        Write-Verbose "Loading .gitignore patterns from $file: $patterns"
    }
    $gitignoreCache[$Directory] = $patterns
    return $patterns
}

function Test-WritePermission {
    param([string]$Path)
    
    # Check if we've already tested this path
    if ($writePermissionCache.ContainsKey($Path)) {
        return $writePermissionCache[$Path]
    }
    
    try {
        # For directories, test with a temporary file
        if ((Get-Item -LiteralPath $Path -Force).PSIsContainer) {
            $testFile = Join-Path -Path $Path -ChildPath "~$([Guid]::NewGuid()).tmp"
            
            try {
                [io.file]::OpenWrite($testFile).Close()
                Remove-Item -LiteralPath $testFile -ErrorAction SilentlyContinue
                $hasPermission = $true
                Write-Verbose "Write permission check passed for directory: $Path"
            } catch {
                $hasPermission = $false
                Write-Verbose "Write permission check failed for directory: $Path"
            }
        } 
        # For files, check if we can open for writing
        else {
            try {
                $fileStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                $fileStream.Close()
                $fileStream.Dispose()
                $hasPermission = $true
                Write-Verbose "Write permission check passed for file: $Path"
            } catch [System.UnauthorizedAccessException] {
                $hasPermission = $false
                Write-Verbose "Write permission check failed (access denied) for file: $Path"
            } catch [System.IO.IOException] {
                # File might be in use
                $hasPermission = $false
                Write-Verbose "Write permission check failed (file in use) for file: $Path"
            } catch {
                $hasPermission = $false
                Write-Verbose "Write permission check failed (other error: $_) for file: $Path"
            }
        }
    } catch {
        $hasPermission = $false
        Write-Verbose "Error during permission check for $Path : $_"
    }
    
    # Cache the result
    $writePermissionCache[$Path] = $hasPermission
    return $hasPermission
}

function Should-ProcessPath {
    param(
        [string]$PathToCheck,
        [string[]]$GitIgnorePatterns,
        [bool]$ForceFlag
    )
    if ($ForceFlag) {
        Write-Verbose "Force flag set; processing $PathToCheck despite ignore rules"
        return $true
    }
    $item = Get-Item -LiteralPath $PathToCheck -ErrorAction SilentlyContinue
    if (-not $item) {
        Write-Verbose "Path does not exist: $PathToCheck"
        return $false
    }
    if ($item.Attributes -band [IO.FileAttributes]::Hidden) {
        Write-Verbose "Skipping hidden item: $PathToCheck"
        return $false
    }
    # .gitignore matching
    $rootLength = (Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue).FullName.Length
    $relative = $PathToCheck.Substring($rootLength).TrimStart('\')
    foreach ($pattern in $GitIgnorePatterns) {
        if ($relative -like $pattern) {
            Write-Verbose "Skipping due to .gitignore pattern '$pattern': $relative"
            return $false
        }
    }
    return $true
}

function Is-TextFile {
    param([string]$FilePath)
    try {
        # Read initial bytes and look for null-byte (binary indicator)
        $bytes = Get-Content -LiteralPath $FilePath -Encoding Byte -TotalCount 4096 -ErrorAction Stop
        foreach ($b in $bytes) {
            if ($b -eq 0) {
                Write-Verbose "Binary indicator found in: $FilePath"
                return $false
            }
        }
        Write-Verbose "Text file detected: $FilePath"
        return $true
    } catch {
        Write-Verbose "Error detecting text file: $FilePath; Error: $_"
        return $false
    }
}

function Process-File {
    param([string]$FilePath)
    try {
        Write-Verbose "Starting processing: $FilePath"
        
        # Check write permissions before proceeding
        if (-not $WhatIf -and -not (Test-WritePermission -Path $FilePath)) {
            Write-Host "[SKIPPED] $FilePath - No write permission or file is locked" -ForegroundColor Yellow
            return
        }
        
        # Save original timestamp
        $origItem = Get-Item -LiteralPath $FilePath -ErrorAction Stop
        $origWriteTime = $origItem.LastWriteTime
        Write-Verbose "Original LastWriteTime: $origWriteTime"

        $text = Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop
        # 1) Remove all Unicode format characters (category Cf)
        $text = [regex]::Replace($text, '\p{Cf}', '')
        Write-Verbose "Removed Unicode format characters"
        # 2) Remove known zero-width characters
        $text = $text -replace '[\u200B\u200C\u200D\uFEFF\u2060]', ''
        Write-Verbose "Removed zero-width characters"
        # 3) Replace common Cyrillic homoglyphs with Latin equivalents
        $homoglyphs = @{
            'а'='a'; 'А'='A'; 'е'='e'; 'Е'='E'; 'о'='o'; 'О'='O';
            'р'='p'; 'Р'='P'; 'с'='s'; 'С'='S'; 'х'='x'; 'Х'='X';
            'і'='i'; 'І'='I'
        }
        foreach ($key in $homoglyphs.Keys) {
            $text = $text -replace ([regex]::Escape($key)), $homoglyphs[$key]
        }
        Write-Verbose "Replaced Cyrillic homoglyphs"
        # 4) Optional line ending conversion
        if ($CLRF) {
            $text = [regex]::Replace($text, '(?<!\r)\n', "`r`n")
            Write-Verbose "Applied CRLF conversion"
        } elseif ($LF) {
            $text = $text -replace "`r`n", "`n"
            Write-Verbose "Applied LF conversion"
        }

        if ($WhatIf) {
            Write-Host "[CHANGES] $FilePath" -ForegroundColor Green
        } else {
            Write-Host "[CLEANING] $FilePath" -ForegroundColor Yellow
            Set-Content -LiteralPath $FilePath -Value $text -Encoding UTF8 -ErrorAction Stop
            Write-Verbose "File written: $FilePath"
            if ($Touch) {
                [System.IO.File]::SetLastWriteTime($FilePath, $origWriteTime)
                Write-Verbose "Restored LastWriteTime: $origWriteTime"
            }
            Write-Host "[CLEANED] $FilePath" -ForegroundColor Green
        }
    } catch {
        Write-Host "[ERROR] $FilePath – $_" -ForegroundColor Red
    }
}

# Check if we have access to the root directory
if (-not (Test-WritePermission -Path $Path) -and -not $WhatIf) {
    Write-Host "[ERROR] No write permission for the root path: $Path" -ForegroundColor Red
    Write-Host "Use -WhatIf to perform a dry run without writing changes." -ForegroundColor Yellow
    exit 1
}

# Initialize BFS directory queue
$queue = [System.Collections.Queue]::new()
$start = (Get-Item -LiteralPath $Path -ErrorAction Stop).FullName
$queue.Enqueue($start)

while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    $patterns = Get-GitIgnorePatterns -Directory $current
    
    # Check directory write permission for subdirectory enumeration
    $canAccessDir = Test-WritePermission -Path $current
    if (-not $canAccessDir -and -not $WhatIf) {
        Write-Host "[SKIPPED] Directory $current - No access permission" -ForegroundColor Yellow
        continue
    }
    
    $items = Get-ChildItem -LiteralPath $current -Force:$Force.IsPresent -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        $full = $item.FullName
        if (-not (Should-ProcessPath -PathToCheck $full -GitIgnorePatterns $patterns -ForceFlag $Force.IsPresent)) {
            Write-Verbose "Skipping: $full"
            continue
        }
        if ($item.PSIsContainer) {
            $queue.Enqueue($full)
        } elseif (Is-TextFile $full) {
            Process-File -FilePath $full
        } else {
            Write-Verbose "Not recognized as text: $full"
        }
    }
}
