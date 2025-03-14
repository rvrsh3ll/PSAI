function ConvertTo-AIPrompt {
    <#
    .SYNOPSIS
        Converts a GitHub repository into a single XML file optimized for AI tools.

    .DESCRIPTION
        This function downloads files from a GitHub repository and packages them into a single XML file
        that can be easily used with AI tools like ChatGPT, Claude, Gemini, etc.
        
        The repository content is organized into a structured format with each file's content 
        encapsulated in separate document sections with paths and other metadata.

    .PARAMETER RepoSlug
        The GitHub repository slug in format 'owner/repo'. Optional subfolder can be specified using 'owner/repo/subfolder'.

    .PARAMETER OutputPath
        Path to save the generated XML file. If not provided, the output is returned as a string.

    .PARAMETER Exclude
        Array of file patterns to exclude (wildcards supported, e.g., *.jpg, *.xlsx).
        By default, common binary and non-text formats are excluded (see Notes for the list).

    .PARAMETER Include
        Array of file patterns to include (wildcards supported, e.g., *.ps1, *.md). If not specified, all files are included.

    .PARAMETER Token
        GitHub API token for private repositories. Optional for public repos but recommended to avoid rate limiting.
        If not provided, the function will attempt to use $env:GITHUB_TOKEN.

    .PARAMETER IncludeBinary
        Switch to override the default binary file exclusions. When specified, only the files explicitly
        mentioned in the Exclude parameter will be excluded.

    .EXAMPLE
        ConvertTo-AIPrompt -RepoSlug "dfinke/ImportExcel" -OutputPath "D:\ImportExcel.xml" -Exclude "*.xlsx","*.jpg"
        
        Exports the entire dfinke/ImportExcel repository, excluding xlsx and jpg files and all default binary formats.

    .EXAMPLE
        ConvertTo-AIPrompt -RepoSlug "dfinke/ImportExcel/Examples" -Include "*.ps1","*.md" | Set-Content -Path "ExcelExamples.xml"
        
        Exports only PowerShell and Markdown files from the Examples folder of the ImportExcel repository.

    .EXAMPLE
        ConvertTo-AIPrompt -RepoSlug "owner/repo" -IncludeBinary
        
        Exports all files from the repository, including binary files that would normally be excluded.

    .NOTES
        Requires connectivity to api.github.com.
        Consider using a token to avoid GitHub API rate limits.
        You can set $env:GITHUB_TOKEN environment variable for authentication instead of passing the token parameter.
        
        Default excluded binary and non-text formats:
        - Images: *.jpg, *.jpeg, *.png, *.gif, *.bmp, *.ico, *.svg, *.webp
        - Documents: *.pdf, *.docx, *.xlsx, *.pptx, *.odt, *.ods, *.odp
        - Archives: *.zip, *.tar, *.gz, *.7z, *.rar
        - Executables: *.exe, *.dll, *.so, *.dylib, *.bin
        - Media: *.mp3, *.mp4, *.wav, *.avi, *.mov, *.flac, *.mkv
        - Others: *.dat, *.db, *.sqlite, *.pyc, *.class, *.jar, *.iso, *.pdb
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$RepoSlug,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Exclude,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Include,
        
        [Parameter(Mandatory = $false)]
        [string]$Token,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeBinary
    )

    # Define common binary file formats to exclude by default
    $defaultBinaryExclusions = @(
        # Images
        "*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp", "*.ico", "*.svg", "*.webp",
        # Documents
        "*.pdf", "*.docx", "*.xlsx", "*.pptx", "*.odt", "*.ods", "*.odp",
        # Archives
        "*.zip", "*.tar", "*.gz", "*.7z", "*.rar",
        # Executables
        "*.exe", "*.dll", "*.so", "*.dylib", "*.bin",
        # Media
        "*.mp3", "*.mp4", "*.wav", "*.avi", "*.mov", "*.flac", "*.mkv",
        # Others
        "*.dat", "*.db", "*.sqlite", "*.pyc", "*.class", "*.jar", "*.iso", "*.pdb"
    )
    
    # Merge default exclusions with user-provided ones unless IncludeBinary is specified
    if (-not $IncludeBinary) {
        if ($Exclude) {
            $Exclude = $Exclude + $defaultBinaryExclusions | Select-Object -Unique
        }
        else {
            $Exclude = $defaultBinaryExclusions
        }
        Write-Verbose "Excluding binary files by default. Use -IncludeBinary to override."
    }

    # Parse repository information
    $repoInfo = $RepoSlug -split '/'
    if ($repoInfo.Count -lt 2) {
        throw "Invalid repository slug format. Expected 'owner/repo' or 'owner/repo/subfolder'."
    }

    $owner = $repoInfo[0]
    $repo = $repoInfo[1]
    
    # Check if a specific subfolder was requested
    $subfolder = ""
    if ($repoInfo.Count -gt 2) {
        $subfolder = [string]::Join('/', $repoInfo[2..$($repoInfo.Count - 1)])
    }

    Write-Verbose "Processing repository: $owner/$repo, subfolder: $($subfolder ? $subfolder : '(root)')"
    
    if ($Exclude -and $Exclude.Count -gt 0) {
        Write-Verbose "Excluding file patterns: $($Exclude -join ', ')"
    }
    
    if ($Include -and $Include.Count -gt 0) {
        Write-Verbose "Including only file patterns: $($Include -join ', ')"
    }

    # Setup API headers
    $headers = @{
        'Accept' = 'application/vnd.github.v3+json'
    }
    
    # Add token if provided, otherwise check for environment variable
    if ($Token) {
        Write-Verbose "Using provided token for authentication"
        $headers['Authorization'] = "token $Token"
    }
    elseif ($env:GITHUB_TOKEN) {
        Write-Verbose "Using GITHUB_TOKEN environment variable for authentication"
        $headers['Authorization'] = "token $env:GITHUB_TOKEN"
    }
    else {
        Write-Verbose "No authentication token provided. Accessing public repositories only."
    }

    # First check if the repository exists and get the correct case for the repo name
    try {
        Write-Progress -Activity "Verifying Repository" -Status "Checking $owner/$repo" -PercentComplete 0
        $repoUrl = "https://api.github.com/repos/$owner/$repo"
        Write-Verbose "Verifying repository: $repoUrl"
        $repoInfo = Invoke-RestMethod -Uri $repoUrl -Headers $headers -ErrorAction Stop
        
        # Use the correct case from the API response
        $owner = $repoInfo.owner.login
        $repo = $repoInfo.name
        
        Write-Verbose "Using repository with correct case: $owner/$repo"
    }
    catch {
        Write-Progress -Activity "Verifying Repository" -Completed
        if ($_ -match "404") {
            throw "Repository not found: $owner/$repo. Please check that the repository exists and is spelled correctly."
        }
        else {
            throw "Error accessing repository information: $_"
        }
    }

    # Function to recursively get all files from a path in the repo
    function Get-RepoContents {
        param (
            [string]$Path,
            [hashtable]$Headers,
            [string]$Owner,
            [string]$Repo
        )

        # Correctly format the URL for the GitHub API
        # If the path is empty, don't include it in the URL
        $apiPath = if ([string]::IsNullOrEmpty($Path)) { "" } else { "/$Path" }
        $url = "https://api.github.com/repos/$Owner/$Repo/contents$apiPath"
        
        Write-Verbose "Fetching: $url"
        Write-Progress -Activity "Discovering Files" -Status "Scanning $Owner/$Repo/$Path" -PercentComplete -1
        
        try {
            $response = Invoke-RestMethod -Uri $url -Headers $Headers -ErrorAction Stop
            
            $files = @()
            
            # Handle case when response is a single item (not an array)
            if ($response -isnot [System.Array]) {
                $response = @($response)
            }
            
            foreach ($item in $response) {
                if ($item.type -eq "dir") {
                    # Show progress when navigating directories
                    Write-Progress -Activity "Discovering Files" -Status "Scanning directory: $($item.path)" -PercentComplete -1
                    
                    # Recursively get files from subdirectory
                    $subFiles = Get-RepoContents -Path $item.path -Headers $Headers -Owner $Owner -Repo $Repo
                    $files += $subFiles
                }
                elseif ($item.type -eq "file") {
                    # Check if file should be excluded
                    $shouldExclude = $false
                    if ($Exclude) {
                        foreach ($pattern in $Exclude) {
                            if ($item.name -like $pattern) {
                                $shouldExclude = $true
                                Write-Verbose "Excluding file (matched pattern '$pattern'): $($item.path)"
                                break
                            }
                        }
                    }
                    
                    # Check if file should be included
                    $shouldInclude = $true
                    if ($Include) {
                        $shouldInclude = $false
                        foreach ($pattern in $Include) {
                            if ($item.name -like $pattern) {
                                $shouldInclude = $true
                                break
                            }
                        }
                        
                        if (-not $shouldInclude) {
                            Write-Verbose "Skipping file (no match in Include patterns): $($item.path)"
                        }
                    }
                    
                    if (-not $shouldExclude -and $shouldInclude) {
                        Write-Verbose "Including file: $($item.path)"
                        $files += $item
                    }
                }
            }
            
            return $files
        }
        catch {
            # Make error message more helpful
            if ($_ -match "404") {
                # If the subfolder isn't found, we'll try different case variations
                if (-not [string]::IsNullOrEmpty($Path)) {
                    Write-Verbose "Path not found, checking parent directory for case-insensitive match"
                    
                    # Get the parent directory
                    $parentPath = Split-Path -Path $Path -Parent
                    $leafName = Split-Path -Path $Path -Leaf
                    
                    # If we're already at the root, there's no parent to check
                    if ([string]::IsNullOrEmpty($parentPath)) {
                        Write-Error "Path not found: $Path. Check that the path exists and is spelled correctly (GitHub is case-sensitive)."
                        throw
                    }
                    
                    try {
                        # Get the contents of the parent directory
                        $parentUrl = "https://api.github.com/repos/$Owner/$Repo/contents/$parentPath"
                        $parentContents = Invoke-RestMethod -Uri $parentUrl -Headers $Headers
                        
                        # Handle case when response is a single item (not an array)
                        if ($parentContents -isnot [System.Array]) {
                            $parentContents = @($parentContents)
                        }
                        
                        # Look for a case-insensitive match for the directory
                        foreach ($item in $parentContents) {
                            if ($item.type -eq "dir" -and $item.name -ieq $leafName) {
                                Write-Verbose "Found case-insensitive match: $($item.name) instead of $leafName"
                                # Use the correct case from the API response
                                return Get-RepoContents -Path $item.path -Headers $Headers -Owner $Owner -Repo $Repo
                            }
                        }
                    }
                    catch {
                        # If we can't check parent, just show the original error
                        Write-Error "Path not found: $Path. Check that the path exists and is spelled correctly (GitHub is case-sensitive)."
                        throw
                    }
                }
                
                Write-Error "Repository or path not found: $url. Make sure the repository and subfolder exist and are accessible."
            } 
            else {
                Write-Error "Failed to get repository contents: $_"
            }
            throw
        }
    }

    # Get all files from the repository
    $allFiles = @()
    try {
        Write-Progress -Activity "Discovering Files" -Status "Scanning repository structure" -PercentComplete 0
        $allFiles = Get-RepoContents -Path $subfolder -Headers $headers -Owner $owner -Repo $repo
        Write-Progress -Activity "Discovering Files" -Completed
    }
    catch {
        Write-Progress -Activity "Discovering Files" -Completed
        throw "Failed to retrieve repository contents: $_"
    }

    # If no files were found, inform the user
    if ($allFiles.Count -eq 0) {
        Write-Warning "No files found in repository $owner/$repo$(if ($subfolder) { "/$subfolder" })"
    }
    else {
        Write-Verbose "Found $($allFiles.Count) files to process"
    }

    # Generate the XML document
    $xmlOutput = [System.Text.StringBuilder]::new()
    [void]$xmlOutput.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$xmlOutput.AppendLine('<documents>')
    
    $fileIndex = 1
    $totalFiles = $allFiles.Count
    
    # Process each file
    foreach ($file in $allFiles) {
        try {
            $percentComplete = [Math]::Min(100, [Math]::Round(($fileIndex / $totalFiles) * 100))
            Write-Progress -Activity "Processing Files" -Status "Processing file $fileIndex of $totalFiles" -CurrentOperation "$($file.path)" -PercentComplete $percentComplete
            
            Write-Verbose "Processing file: $($file.path)"
            
            # Get file content via GitHub API
            $fileUrl = $file.download_url
            if (-not $fileUrl) {
                Write-Warning "No download URL for $($file.path), skipping"
                continue
            }
            
            $fileContent = Invoke-RestMethod -Uri $fileUrl -Headers $headers -ErrorAction Stop
            
            # Add document entry to XML
            [void]$xmlOutput.AppendLine("    <document index='$fileIndex'>")
            [void]$xmlOutput.AppendLine("        <source>$($file.path)</source>")
            [void]$xmlOutput.AppendLine("        <document_content>")
            [void]$xmlOutput.AppendLine("            $([System.Security.SecurityElement]::Escape($fileContent))")
            [void]$xmlOutput.AppendLine("        </document_content>")
            [void]$xmlOutput.AppendLine("    </document>")
            
            $fileIndex++
        }
        catch {
            Write-Error "Error processing file $($file.path): $_"
        }
    }
    
    # Complete the progress bar
    Write-Progress -Activity "Processing Files" -Completed
    
    [void]$xmlOutput.AppendLine('</documents>')
    
    $result = $xmlOutput.ToString()
    
    # Either save to file or return as string
    if ($OutputPath) {
        $result | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Verbose "Output saved to: $OutputPath"
        return $OutputPath
    }
    else {
        return $result
    }
}
