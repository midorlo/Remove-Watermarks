# Remove-Watermarks

A PowerShell script for removing invisible watermarks from text files.

## Overview

This script recursively scans directories for text files and removes invisible watermarks such as zero-width characters and other hidden formatting characters that may be concealed in documents. It respects `.gitignore` rules and handles hidden files and directories accordingly.

## Features

- **Thorough Watermark Removal**:
  - Removes all Unicode format characters (Unicode category Cf)
  - Eliminates known zero-width characters (invisible characters with no width)
  - Replaces Cyrillic homoglyphs with their Latin equivalents

- **Intelligent File Detection**:
  - Identifies genuine text files through content inspection
  - Automatically skips binary files

- **Respect for Development Conventions**:
  - Honors .gitignore rules
  - Respects hidden files and directories
  - Supports line ending conversion (CRLF ↔ LF)

- **Robust Error Handling**:
  - Checks write permissions before processing
  - Comprehensive error handling and logging
  - Skips files or directories without access rights

## Usage

```powershell
# Basic usage
.\Remove-Watermarks.ps1 -Path C:\Projects\MyRepo

# Dry run without making actual changes with detailed output
.\Remove-Watermarks.ps1 -Path C:\Projects\MyRepo -WhatIf -Verbose

# Clean all files, convert to LF line endings, and preserve timestamps
.\Remove-Watermarks.ps1 -Path C:\Projects\MyRepo -LF -Touch -Verbose

# Process hidden files and ignored files as well
.\Remove-Watermarks.ps1 -Path C:\Projects\MyRepo -Force
```

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-Path`   | The root directory to start processing from. |
| `-WhatIf` | Shows which files would be modified without actually making changes. |
| `-Force`  | Ignores .gitignore rules and hidden file/folder attributes. |
| `-CLRF`   | Converts lone LF line endings ("\n" without a preceding "\r") to CRLF ("\r\n"). |
| `-LF`     | Converts all CRLF line endings ("\r\n") to simple LF ("\n"). |
| `-Touch`  | Restores the original LastWriteTime timestamp after writing. |
| `-Verbose` | Standard PowerShell verbose switch for detailed output. |

## Installation

1. Download the script or clone the repository.
2. Optional: Add the directory containing the script to your PowerShell environment variable.

```powershell
# The script can be run from any directory
Invoke-WebRequest -Uri https://raw.githubusercontent.com/midorlo/Remove-Watermarks/master/Remove-Watermarks.ps1 -OutFile Remove-Watermarks.ps1
```

## Use Cases

- **Developers**: Remove hidden watermarks from code files before committing
- **Editors**: Clean text documents before publication
- **Security Analysts**: Remove potential hidden identifiers from shared files
- **DevOps**: Integrate into CI/CD pipelines for automatic cleaning

## Requirements

- PowerShell 5.1 or higher
- Read permissions for directories to be scanned
- Write permissions for files to be modified

## License

MIT

## Contributing

Contributions are welcome! Please open an issue to report bugs or suggest features, or create a pull request with your changes.

## Security Note

This script modifies files. It is recommended to create a backup before use or to test first with the `-WhatIf` option.
