param(
    [switch]$DebugMode
)

Write-Host "Welcome to DKB Search and Script Generator"

#Debug mode: enable via -DebugMode switch, DKB_DEBUG=1 env var, or force it here
$debugMode = $DebugMode.IsPresent -or ($env:DKB_DEBUG -eq '1')
# $debugMode = $true   # <-- or uncomment this line to always debug

# Operating System Detection
if ($IsLinux -or ($PSVersionTable.PSObject.Properties['OS'] -and $PSVersionTable.OS -match 'Linux')) {
    $scriptOS = "Linux"
}
elseif (
    $IsWindows -or # PowerShell 7+ on Windows
    $PSVersionTable.PSEdition -eq 'Desktop' -or
    $env:OS -eq 'Windows_NT' -or 
    [System.Environment]::OSVersion.Platform -eq 'Win32NT'  # .NET-level check
) {
    $scriptOS = "Windows"
}
else {
    Write-Host "[FATAL ERROR] Unsupported operating system." -ForegroundColor Red
    exit
}

Write-Host "Running on: $scriptOS" -ForegroundColor Cyan

#Helper Functions (defined early so checks below can use them)
function Normalize-Number($num) {
    return ([string]::Format("{0:D2}", [int]$num))
}

#Filename Sanitizer
function ConvertTo-SafeFileName($name) {
    # Strips Windows-illegal chars PLUS shell-hostile ones: ' ` $ !
    $safe = $name -replace '[\\/:*?"<>|''`$!]', ''
    $safe = $safe -replace '\s+', '_'
    $safe = $safe -replace '\.', '_'
    return $safe
}

#EOF-Guarded Input (prevents CPU-spin zombie if terminal closes)
function Read-UserInput($prompt) {
    if ($prompt) { Write-Host "${prompt}: " -NoNewline }
    $eof = $false
    try { $eof = [System.Console]::In.EndOfStream } catch { $eof = $true }
    if ($eof) {
        Write-Host "`n[INFO] Input stream closed (terminal closed?). Exiting gracefully." -ForegroundColor Yellow
        exit 0
    }
    return (Read-Host)
}

#Press ANY key (like Windows 'pause'), used for exit prompts
function Read-AnyKey($prompt) {
    if ($prompt) { Write-Host $prompt -NoNewline }
    try {
        [void][System.Console]::ReadKey($true)
    }
    catch {
        # Fallback if key reading is unavailable (e.g. redirected input)
        Read-Host
    }
    Write-Host ""
}

#Debug output
function Write-DebugInfo {
    param(
        [string]$rawResults,
        [array]$seriesArray
    )
    if ($debugMode) {
        Write-Host "DEBUG: Raw search results:" -ForegroundColor Cyan
        Write-Host $rawResults
        Write-Host "DEBUG: Parsed series:" -ForegroundColor Cyan
        foreach ($s in $seriesArray) {
            Write-Host "Title: $($s.Title), Season: $($s.Season), Type: $($s.Type), SeriesID: $($s.SeriesID), ZID: $($s.ZID)"
        }
    }
}

function Handle-NoResults {
    while ($true) {
        Write-Host "No Anime found. " -NoNewline -ForegroundColor Yellow
        $userInput = Read-UserInput "Wanna do a new search(n), change service(s) or exit(Press Enter)?"
        switch ($userInput.Trim().ToLower()) {
            'n' { return "NEW_SEARCH" }
            'new search' { return "NEW_SEARCH" }
            's' { return "CHANGE_SERVICE" }
            'change service' { return "CHANGE_SERVICE" }
            '' { return "EXIT" } # Handles the Enter key
            'exit' { return "EXIT" }
            default {
                Write-Host "Invalid selection. Please enter 'n'/'new search', 's'/'change service', or 'exit' (or just press Enter)." -ForegroundColor Red
            }
        }
    }
}

function Get-NextAction {
    while ($true) {
        $userInput = Read-UserInput "Do you want to search for another anime (Yes(y)/No(n))? or change service(cs)"
        switch ($userInput.Trim().ToLower()) {
            "yes" { return "YES" }
            "y" { return "YES" }
            "no" { return "NO" }
            "n" { return "NO" }
            "cs" { return "CHANGE_SERVICE" }
            "change service" { return "CHANGE_SERVICE" }
            default { Write-Host "Invalid selection. Please enter Yes(y), No(n), or Change Service(cs)." -ForegroundColor Red }
        }
    }
}

function Get-SelectionFromListWithDefault($prompt, [string[]]$list, $default) {
    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host "[$i] $($list[$i])"
    }
    $finalPrompt = "$prompt (Leave blank for default $default)"
    while ($true) {
        $selection = Read-UserInput $finalPrompt
        if ([string]::IsNullOrWhiteSpace($selection)) {
            return $default
        }
        if ($selection -match "^\d+$" -and [int]$selection -ge 0 -and [int]$selection -lt $list.Count) {
            return $list[[int]$selection]
        }
        else {
            Write-Host "Invalid selection. Please enter a number between 0 and $($list.Count - 1), or leave blank for default." -ForegroundColor Red
        }
    }
}

function Get-MultiSelectionFromListWithDefault($prompt, [string[]]$list, $defaultIndex, $defaultLabel) {
    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host "[$i] $($list[$i])"
    }
    $finalPrompt = "$prompt [Default: $defaultLabel]"
    while ($true) {
        $selection = Read-UserInput $finalPrompt
        if ([string]::IsNullOrWhiteSpace($selection)) {
            return , @($list[$defaultIndex])
        }
        
        $selectedItems = @()
        $invalid = $false
        $parts = $selection -split ',' | ForEach-Object { $_.Trim() }
        
        foreach ($part in $parts) {
            if ($part -match "^\d+$" -and [int]$part -ge 0 -and [int]$part -lt $list.Count) {
                $selectedItems += $list[[int]$part]
            }
            else {
                $invalid = $true
                break
            }
        }
        
        if (-not $invalid -and $selectedItems.Count -gt 0) {
            return , $selectedItems
        }
        else {
            Write-Host "Invalid selection. Please enter comma-separated numbers between 0 and $($list.Count - 1)." -ForegroundColor Red
        }
    }
}

function Get-YesNo($prompt) {
    while ($true) {
        $userInput = Read-UserInput $prompt
        switch ($userInput.ToLower()) {
            "yes" { return $true }
            "y" { return $true }
            "no" { return $false }
            "n" { return $false }
            default { Write-Host "Please enter 'yes' or 'no'." }
        }
    }
}

function Get-Selection($prompt, [string[]]$allowed) {
    while ($true) {
        $userInput = Read-UserInput $prompt
        if ($allowed -contains $userInput) { return $userInput }
        else { Write-Host "Invalid selection. Allowed values: $($allowed -join ', ')" }
    }
}

function Get-SingleMultiple($prompt) {
    while ($true) {
        $userInput = Read-UserInput $prompt
        $lc = $userInput.ToLower().Trim(":"[0], " "[0])
        if ($lc -eq "single" -or $lc -eq "s") { return "single" }
        elseif ($lc -eq "multiple" -or $lc -eq "m") { return "multiple" }
        else { Write-Host "Invalid selection. Please enter Single(S) or Multiple(M)." }
    }
}

function Get-VideoTitle {
    $userInputVideoTitle = Read-UserInput "Enter VideoTitle name ([DKB Team] default)"
    if ([string]::IsNullOrWhiteSpace($userInputVideoTitle)) { return "[DKB Team]" }
    else { return $userInputVideoTitle.Trim() }
}

function Parse-Series {
    param($searchResults)

    $foundSeries = @()
    $lastMasterTitle = ""
    $lastMasterZID = ""

    foreach ($rawLine in $searchResults -split "`r?`n") {
        # Strip ANSI color/format codes that new aniDL builds may emit
        $line = $rawLine -replace "\x1b\[[0-9;?]*[A-Za-z]", "" -replace "\x1b\][^\x07]*\x07", "" -replace "\x1b[=>]", ""
        $trimmedLine = $line.Trim()

        if ($trimmedLine -match "^(Found movie lists:|Found episodes:|Newly added:|Top results:|Found series:|Total results:|===|USER:|Your Country:)" -or [string]::IsNullOrWhiteSpace($trimmedLine)) {
            continue
        }

        if ($serviceOption -eq "hidive" -and $trimmedLine -match "^\[Z\.([0-9]+)\]\s+(.+?)\s+\((\d+)\s+Seasons?\)") {
            $seriesID = $matches[1].Trim()
            $title = $matches[2].Trim()
            $seasonCount = $matches[3].Trim()
            $seriesObj = [PSCustomObject]@{
                Title        = $title
                Season       = "1"
                SeasonCount  = $seasonCount
                Type         = "HIDIVE"
                EpisodeCount = $null
                SeriesID     = $seriesID
                ZID          = $null
                Versions     = $null
                Subtitles    = $null
            }
            $foundSeries += $seriesObj
            continue
        }

        if ($line -match "^(\s*)\[(Z|S):([^\|\]]+)[^\]]*\]\s+(.+?)(?:\s*\((.*?)\))?\s*\[(.*?)\]\s*$") {
            $indentation = $matches[1]
            $idPrefix = $matches[2]
            $idValue = $matches[3].Trim()
            $title = $matches[4].Trim()
            
            # Handle cases where metadata parentheses are missing (e.g. movies)
            $metadata = if ($matches[5]) { $matches[5].Trim() } else { "" }
            $type = $matches[6].Trim()

            $seriesObj = [PSCustomObject]@{
                Title        = $title
                Season       = "1"
                Type         = $type
                EpisodeCount = $null
                SeriesID     = $null
                ZID          = $null
                Versions     = $null
                Subtitles    = $null
            }

            if ($metadata -match "Seasons?:\s*(\d+)") { $seriesObj.Season = $matches[1] }
            if ($metadata -match "EPs:\s*(\d+)") { $seriesObj.EpisodeCount = $matches[1] }

            if ($idPrefix -eq 'Z') {
                $seriesObj.ZID = $idValue
                $lastMasterTitle = $seriesObj.Title
                $lastMasterZID = $seriesObj.ZID
            }
            else {
                $seriesObj.SeriesID = $idValue
                $seriesObj.ZID = $lastMasterZID
                if ($indentation.Length -gt 0 -and $seriesObj.Title -match "^\s*Season\s+\d+\s*$") {
                    $seriesObj.Title = $lastMasterTitle
                }
            }
            
            $foundSeries += $seriesObj
        }
        elseif ($trimmedLine -match "^-\s+Versions:\s*(.+)") {
            if ($foundSeries.Count -gt 0) {
                $rawVersions = $matches[1].Trim()
                $parsedVersions = $rawVersions -split "," | ForEach-Object { $_.Trim() } | Where-Object { $globalAllowedLangs -contains $_ }
                $foundSeries[-1].Versions = $parsedVersions
            }
        }
        elseif ($trimmedLine -match "^-\s+Subtitles:\s*(.+)") {
            if ($foundSeries.Count -gt 0) {
                $rawSubs = $matches[1].Trim()
                $parsedSubs = $rawSubs -split "," | ForEach-Object { $_.Trim() } | Where-Object { $globalAllowedLangs -contains $_ }
                if (-not $foundSeries[-1].PSObject.Properties["Subtitles"]) {
                    $foundSeries[-1] | Add-Member -MemberType NoteProperty -Name Subtitles -Value $parsedSubs
                }
                else { $foundSeries[-1].Subtitles = $parsedSubs }
            }
        }
    }
    $seenKeys = [System.Collections.Generic.HashSet[string]]::new()
    $uniqueSeries = [System.Collections.Generic.List[psobject]]::new()

    foreach ($series in $foundSeries) {
        $uniqueKey = if (-not [string]::IsNullOrWhiteSpace($series.SeriesID)) { $series.SeriesID } else { $series.ZID }
        if ($seenKeys.Add($uniqueKey)) {
            $uniqueSeries.Add($series)
        }
    }

    $finalArray = $uniqueSeries.ToArray()
    return $finalArray
}

# Unified Script Generator Function
function New-GeneratedScript {
    param(
        [string]$Cmd,
        [string]$FileName,
        [string]$ServiceOption,
        [string]$ScriptOS,
        [string]$ScriptOutputPath,
        [string]$MoveVideos
    )

    $batchContent = @()
    $batchContent += $script:headerLines
    
    if ($ServiceOption -eq "hidive") { 
        if ($ScriptOS -eq "Windows") { $batchContent += "SET ORIGINAL=%CD%" }
        else { $batchContent += 'ORIGINAL="$PWD"' }
    }

    $batchContent += $script:pushdMaster
    $batchContent += $script:callAuth
    $batchContent += $script:popdMaster
    $batchContent += $Cmd
    $batchContent += $MoveVideos
    $batchContent += $script:pauseCmd

    $batFile = Join-Path -Path $ScriptOutputPath -ChildPath $FileName
    [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))

    # --- AUTOMATIC CHMOD FOR LINUX ---
    if ($ScriptOS -eq "Linux") {
        & bash -c "chmod +x `"$batFile`""
    }
    # ---------------------------------

    Write-Host "Created script: $batFile" -ForegroundColor Green
}

# --- Node.js Check ---
$nodeCommand = Get-Command -Name "node" -CommandType Application -ErrorAction SilentlyContinue
if (-not $nodeCommand) {
    Write-Host "[FATAL ERROR] Node.js ('node') was not found in PATH." -ForegroundColor Red
    Write-Host "On Fedora install it with: sudo dnf install nodejs" -ForegroundColor Yellow
    Read-AnyKey "Press any key to exit..."
    exit
}

# --- Global Allowed Languages ---
$globalAllowedLangs = @("ja-JP", "en-US", "es-419", "es-ES", "fr-FR", "pt-BR", "pt-PT", "ar-ME", "ar-SA", "it-IT", "de-DE", "ru-RU", "tr-TR", "hi-IN", "ca-ES", "pl-PL", "th-TH", "tl-PH", "ta-IN", "ms-MY", "vi-VN", "id-ID", "te-IN", "zh-CN", "zh-HK", "zh-TW", "ko-KR")

# --- Path Auto-Discovery ---
try {
    if ($scriptOS -eq "Windows") {
        $aniDLCommand = Get-Command -Name "aniDL.exe" -CommandType Application -ErrorAction Stop
    }
    else {
        $aniDLCommand = Get-Command -Name "aniDL" -CommandType Application -ErrorAction Stop
    }

    $aniDLFullPath = $aniDLCommand.Source
    $masterPath = Split-Path -Path $aniDLFullPath -Parent

    Write-Host "aniDL master path automatically detected: $masterPath" -ForegroundColor Green
}
catch {
    Write-Host "------------------------------------------------------------" -ForegroundColor Red

    if ($scriptOS -eq "Windows") {
        Write-Host "[FATAL ERROR] Could not find 'aniDL.exe' in your system's PATH." -ForegroundColor Red
    }
    else {
        Write-Host "[FATAL ERROR] Could not find 'aniDL' in your system's PATH." -ForegroundColor Red
    }

    Write-Host "Please ensure aniDL is installed and its location is added to PATH."
    Write-Host "------------------------------------------------------------"
    Read-AnyKey "Press any key to exit..."
    exit
}

# Define available services.
$services = @("Crunchyroll", "Hidive")

$runScript = $true
while ($runScript) {

    $chosenService = Get-SelectionFromListWithDefault "Choose a service" $services "Crunchyroll"
    $aniDLPath = "aniDL"

    if ($chosenService -eq "Hidive") {
        if ($scriptOS -eq "Windows") {
            $authScriptCurrent = Join-Path -Path $masterPath -ChildPath "Auth_HDV.bat"
        }
        else {
            $authScriptCurrent = Join-Path -Path $masterPath -ChildPath "Auth_HDV.sh"
        }

        $serviceOption = "hidive"
    }
    else {
        if ($scriptOS -eq "Windows") {
            $authScriptCurrent = Join-Path -Path $masterPath -ChildPath "Auth_CR.bat"
        }
        else {
            $authScriptCurrent = Join-Path -Path $masterPath -ChildPath "Auth_CR.sh"
        }

        $serviceOption = "crunchy"
    }

    $checkTokenPath = Join-Path -Path $masterPath -ChildPath 'check_token.js'
    
    $script:scriptExt = if ($scriptOS -eq "Windows") { ".bat" } else { ".sh" }
    $script:defaultDest = if ($scriptOS -eq "Windows") { "%CD%" } else { '$PWD' }

    if ($scriptOS -eq "Windows") {
        $script:headerLines = @("@echo off", "chcp 65001 >nul")
        $script:pushdMaster = 'pushd "' + $masterPath + '"'
        $script:callAuth = 'node "' + $checkTokenPath + '" ' + $serviceOption + ' if errorlevel 1 call "' + $authScriptCurrent + '"'
        $script:popdMaster = 'popd'
        $script:pauseCmd = 'if not defined SKIP_PAUSE pause'
    }
    else {
        $script:headerLines = @(
            '#!/bin/bash',
            '# DKB-AUTO-RUN',
            '# If launched without a terminal (double-click), reopen in a visible window',
            'if [ ! -t 0 ] || [ ! -t 1 ]; then',
            '    SELF="$(readlink -f "$0")"',
            '    if command -v konsole >/dev/null 2>&1; then',
            '        exec konsole -e /bin/bash "$SELF"',
            '    else',
            '        exec xterm -e /bin/bash "$SELF"',
            '    fi',
            'fi'
        )
        $script:pushdMaster = 'pushd "' + $masterPath + '" > /dev/null'
        $script:callAuth = 'node "' + $checkTokenPath + '" ' + $serviceOption + ' || bash "' + $authScriptCurrent + '"'
        $script:popdMaster = 'popd > /dev/null'
        $script:pauseCmd = 'if [ -z "$SKIP_PAUSE" ]; then read -n 1 -s -r -p "Press any key to quit..."; echo; fi'
    }

    $videosDir = Join-Path $masterPath "videos"

    # --- Pre-flight Token Check for the Generator ---
    if (Test-Path $checkTokenPath) {
        & node $checkTokenPath $serviceOption

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Master token missing or dead. Running manual authentication..." -ForegroundColor Yellow

            if ($scriptOS -eq "Windows") {
                & cmd /c "$authScriptCurrent"
            }
            else {
                & bash "$authScriptCurrent"
            }
        }
        else {
            Write-Host "Valid master token found - skipping manual login." -ForegroundColor Green
        }
    }
    else {
        Write-Host "check_token.js not found. Running manual authentication..." -ForegroundColor Red

        if ($scriptOS -eq "Windows") {
            & cmd /c "$authScriptCurrent"
        }
        else {
            & bash "$authScriptCurrent"
        }
    }
    # -------------------------------------------------

    $scriptOutputPath = Join-Path -Path $masterPath -ChildPath "Generated_Scripts"
    if (!(Test-Path $scriptOutputPath)) { New-Item -ItemType Directory -Path $scriptOutputPath -Force | Out-Null }

    $searchLoopActive = $true
    while ($searchLoopActive) {
        Write-Host "Enter Anime Name or type New to check the latest series: " -NoNewline
        $animeName = Read-UserInput

        # Capture stdout AND stderr: new builds may log results to stderr
        if ($serviceOption -eq "crunchy" -and $animeName -ieq "new") {
            $searchResults = (& $aniDLPath --service $serviceOption --new 2>&1) -join "`n"
        }
        elseif ($serviceOption -eq "crunchy") {
            $searchResults = (& $aniDLPath --service $serviceOption --search "$animeName" 2>&1) -join "`n"
        }
        else {
            $searchResults = (& $aniDLPath --service $serviceOption --search "$animeName" 2>&1) -join "`n"
        }
        
        $foundSeries = Parse-Series $searchResults

        # Always keep the raw output for diagnostics (works with debug off too)
        $rawDumpFile = Join-Path $scriptOutputPath ".last_search_raw.txt"
        Set-Content -LiteralPath $rawDumpFile -Value $searchResults -Encoding UTF8

        # Debug BEFORE the no-results exit, so we see WHY nothing parsed
        if ($debugMode) {
            Write-DebugInfo -rawResults $searchResults -seriesArray @($foundSeries)
            Write-Host "DEBUG: raw output also saved to $rawDumpFile" -ForegroundColor Cyan
        }

        if (-not $foundSeries) {
            $action = Handle-NoResults
            if ($action -eq "NEW_SEARCH") { continue }
            if ($action -eq "CHANGE_SERVICE") { 
                $searchLoopActive = $false
                continue
            }
            if ($action -eq "EXIT") { 
                $runScript = $false
                $searchLoopActive = $false
                continue
            }
        }
        
        $foundSeries = @($foundSeries)

        Write-Host "---- Available Series ----"
        
        $startIndex = 0
        $displayLimit = 15
        $performNewSearch = $false

        while ($true) {
            $endIndex = [math]::Min($displayLimit, $foundSeries.Count)
            for ($i = $startIndex; $i -lt $endIndex; $i++) {
                $displayLine = "[$i] $($foundSeries[$i].Title) - Season $($foundSeries[$i].Season) ($($foundSeries[$i].Type))"
                if ($foundSeries[$i].EpisodeCount) { $displayLine += " - EPs: $($foundSeries[$i].EpisodeCount)" }
                if ($foundSeries[$i].SeriesID) { $displayLine += "[S:$($foundSeries[$i].SeriesID)]" }
                if ($foundSeries[$i].ZID -and -not $foundSeries[$i].SeriesID) { $displayLine += "[Z:$($foundSeries[$i].ZID)]" }
                Write-Host $displayLine
                if ($foundSeries[$i].Versions) { Write-Host "    - Versions: $($foundSeries[$i].Versions -join ', ')" }
                if ($foundSeries[$i].Subtitles) { Write-Host "    - Subtitles: $($foundSeries[$i].Subtitles -join ', ')" }
            }

            $seriesIndices = Read-UserInput "Enter the number(s) of the serie(s) or new search(n) (comma-separated), more search results(Enter)"
            
            if ([string]::IsNullOrWhiteSpace($seriesIndices)) {
                if ($displayLimit -ge $foundSeries.Count) {
                    Write-Host "No more results to display." -ForegroundColor Yellow
                }
                else {
                    $startIndex = $displayLimit
                    $displayLimit += 15
                }
                continue
            }

            if ($seriesIndices.Trim() -ieq 'n') {
                $performNewSearch = $true
                break
            }
            
            $selectedSeries = $seriesIndices -split "," | ForEach-Object {
                $index = $_.Trim()
                if ($index -match "^\d+$" -and [int]$index -ge 0 -and [int]$index -lt $foundSeries.Count) {
                    $foundSeries[[int]$index]
                }
            }
            if ($selectedSeries) { break }
            Write-Host "Invalid selection. Please enter valid numbers from the list, 'n' for a new search, or press Enter for more results." -ForegroundColor Red
        }

        if ($performNewSearch) { continue }
        
        foreach ($series in $selectedSeries) {
            if ($serviceOption -eq "crunchy" -and -not [string]::IsNullOrWhiteSpace($series.SeriesID)) {
                $flag = "-s"
                $seriesID = $series.SeriesID
            }
            elseif ($serviceOption -eq "crunchy" -and -not [string]::IsNullOrWhiteSpace($series.ZID)) {
                $flag = "--srz"
                $seriesID = $series.ZID
            }
            else {
                $flag = "-s"
                $seriesID = $series.SeriesID
            }
            
            $origShowTitle = ($series.Title -replace '[\\/:*?"<>|]', '') -replace '\s+', ' '
            $batShowTitle = ConvertTo-SafeFileName $origShowTitle

            if ($series.Season -match "^\d+$") {
                if ([int]$series.Season -lt 10) { $origSeason = "0" + [int]$series.Season }
                else { $origSeason = $series.Season }
            }
            else { 
                $origSeason = $series.Season 
            }
            
            if ($serviceOption -eq "hidive") {
                Write-Host "--- Audio Language Selection ---" -ForegroundColor Yellow
                $availableDubLangs = @("ja-JP", "en-US", "spa-419", "pt-BR")
                
                [string[]]$chosenDubLangsArray = Get-MultiSelectionFromListWithDefault "Choose a dub language to download e.g. 0, 1" $availableDubLangs 0 "ja-JP"
                
                # Ensure ja-JP is first if selected
                if ($chosenDubLangsArray -contains "ja-JP") {
                    $chosenDubLangsArray = @("ja-JP") + ($chosenDubLangsArray | Where-Object { $_ -ne "ja-JP" })
                }
                
                $chosenDubLang = ($chosenDubLangsArray -join " ") -replace "\bes-419\b", "spa-419" -replace "\bes-ES\b", "spa-ES"
                
                if ($chosenDubLangsArray -contains "ja-JP") {
                    $defaultAudioLabel = "ja-JP"
                }
                else {
                    $defaultAudioLabel = $chosenDubLangsArray[0]
                }
                
                $chosenDefaultAudio = Get-SelectionFromListWithDefault "Choose a default Audio language" $chosenDubLangsArray $defaultAudioLabel
                
                $availableSubs = @("en-US", "ja-JP", "spa-419", "pt-BR")
                $chosenSub = Get-SelectionFromListWithDefault "Choose the default subtitle for the script" $availableSubs "en-US"
            }
            else { 
                if ($series.Versions) {
                    Write-Host "--- Audio Language Selection ---" -ForegroundColor Yellow
                    $availableDubLangs = $series.Versions;
                    
                    [string[]]$chosenDubLangsArray = Get-MultiSelectionFromListWithDefault "Choose a dub language to download e.g. 0, 1" $availableDubLangs 0 $availableDubLangs[0];
                    
                    # Ensure ja-JP is first if selected
                    if ($chosenDubLangsArray -contains "ja-JP") {
                        $chosenDubLangsArray = @("ja-JP") + ($chosenDubLangsArray | Where-Object { $_ -ne "ja-JP" })
                    }
                    
                    $chosenDubLang = ($chosenDubLangsArray -join " ") -replace "\bes-419\b", "spa-419" -replace "\bes-ES\b", "spa-ES"
                    
                    if ($chosenDubLangsArray -contains "ja-JP") {
                        $defaultAudioLabel = "ja-JP"
                    }
                    else {
                        $defaultAudioLabel = $chosenDubLangsArray[0]
                    }
                    
                    $chosenDefaultAudio = Get-SelectionFromListWithDefault "Choose a default Audio language" $chosenDubLangsArray $defaultAudioLabel
                }
                else {
                    Write-Host "--- Audio Language Selection ---" -ForegroundColor Yellow
                    Write-Host "Audio versions were not listed in search results. Please choose manually, check Crunchyroll for available Audios."
                    
                    [string[]]$chosenDubLangsArray = Get-MultiSelectionFromListWithDefault "Choose a dub language to download e.g. 0, 1" $globalAllowedLangs 0 "ja-JP";
                    
                    # Ensure ja-JP is first if selected
                    if ($chosenDubLangsArray -contains "ja-JP") {
                        $chosenDubLangsArray = @("ja-JP") + ($chosenDubLangsArray | Where-Object { $_ -ne "ja-JP" })
                    }
                    
                    $chosenDubLang = ($chosenDubLangsArray -join " ") -replace "\bes-419\b", "spa-419" -replace "\bes-ES\b", "spa-ES"
                    
                    if ($chosenDubLangsArray -contains "ja-JP") {
                        $defaultAudioLabel = "ja-JP"
                    }
                    else {
                        $defaultAudioLabel = $chosenDubLangsArray[0]
                    }
                    
                    $chosenDefaultAudio = Get-SelectionFromListWithDefault "Choose a default Audio language" $chosenDubLangsArray $defaultAudioLabel
                }

                if ($series.Subtitles) {
                    $availableSubs = $series.Subtitles
                    $chosenSub = Get-SelectionFromListWithDefault "Choose the default subtitle for the script" $availableSubs "en-US"
                }
                else { 
                    $chosenSub = "en-US" 
                }
            }
            
            $chosenVideoTitle = Get-VideoTitle
            
            if ($serviceOption -eq "hidive") {
                while ($true) {
                    $userInputFontSize = Read-UserInput "Enter fontSize (Leave blank for default 48)"
                    if ([string]::IsNullOrWhiteSpace($userInputFontSize)) {
                        $chosenFontSize = 48
                        break
                    }
                    if ($userInputFontSize -match "^\d+$") {
                        $chosenFontSize = [int]$userInputFontSize
                        break
                    }
                    Write-Host "Invalid input. Please enter a number or leave blank." -ForegroundColor Red
                }
            }
            
            $episodeSelection = $null
            while (-not $episodeSelection) {
                $userInput = Read-UserInput "Do you want to download all episodes or specific episodes? (all(a)/specific(s)/all-but-one(ab))"
                switch ($userInput.Trim().ToLower()) {
                    "all" { $episodeSelection = "all" }
                    "a" { $episodeSelection = "all" }
                    "specific" { $episodeSelection = "specific" }
                    "s" { $episodeSelection = "specific" }
                    "all-but-one" { $episodeSelection = "all-but-one" }
                    "ab" { $episodeSelection = "all-but-one" }
                    default { Write-Host "Invalid selection. Please enter all(a), specific(s), or all-but-one(ab)." -ForegroundColor Red }
                }
            }
            
            if ($episodeSelection -eq "all") {
                $scriptType = "single"
            }
            elseif ($episodeSelection -eq "specific") {
                $scriptType = Get-SingleMultiple "Do you want a single script or multiple scripts? (Single(S)/Multiple(M))"
            }
            
            $inputShowTitle = Read-UserInput "Enter new show title for filename (leave blank for default [$origShowTitle])"
            if ($inputShowTitle -ne "") {
                $cleaned = $inputShowTitle -replace '[\\/:*?"<>|]', ""
                $cmdShowTitle = $cleaned.Trim()
                $cmdShowTitle = $cmdShowTitle -replace "[\r\n]+", " "
                $batShowTitle = ConvertTo-SafeFileName $cleaned.Trim()
            }
            else {
                $cmdShowTitle = $origShowTitle
                $cmdShowTitle = $cmdShowTitle -replace "[\r\n]+", " "
                $batShowTitle = ConvertTo-SafeFileName $origShowTitle
            }
            
            $inputSeason = Read-UserInput "Enter new season value (leave blank for default[$origSeason])"
            if ($inputSeason -ne "") {
                if ($inputSeason -match "^\d+$") { 
                    $cmdSeason = Normalize-Number $inputSeason 
                }
                else { 
                    $cmdSeason = $inputSeason 
                }
                $batSeason = $cmdSeason
            }
            else {
                $cmdSeason = Normalize-Number $origSeason
                $batSeason = $cmdSeason
            }
            
            $cmdShowTitle = $cmdShowTitle -replace '[\r\n\t]', ' '
            $cmdShowTitle = $cmdShowTitle -replace '"', ''
            $cmdShowTitle = $cmdShowTitle.Trim()
            
            # Build the base payload
            $fileNamePayload = $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]'
            
            # If Linux, escape $ and backticks so bash doesn't eat the aniDL variables
            if ($scriptOS -eq "Linux") {
                $fileNamePayload = $fileNamePayload.Replace('$', '\$').Replace('`', '\`')
            }

            #CUSTOM PATH INJECTION
            $useCustomPath = Get-YesNo "Want to use a custom path for files? (Y/N)"
            if ($useCustomPath) {
                $customDest = Read-UserInput "Please type your custom path"
                if ([string]::IsNullOrWhiteSpace($customDest)) {
                    $customDest = $script:defaultDest
                }
            }
            else {
                $customDest = $script:defaultDest
            }
            
            # Build the move command safely for both OSes
            if ($scriptOS -eq "Windows") {
                $moveVideos = 'move "' + $videosDir + '\*.mkv" "' + $customDest + '"'
            }
            else {
                # Notice the quote ends before the asterisk! -> "/path/"*.mkv
                $moveVideos = 'mv "' + $videosDir + '/"*.mkv "' + $customDest + '"'
            }

            if ($episodeSelection -eq "all") {
                $episodeOption = "--all"
                if ($serviceOption -eq "hidive") {
                    $cmd = $aniDLPath + ' --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --originalFontSize false --fontSize ' + $chosenFontSize + ' --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $fileNamePayload + '"'
                }
                else {
                    $cmd = $aniDLPath + ' --service "' + $serviceOption + '" ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --tsd --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $fileNamePayload + '"'
                }
                
                $fileName = $batShowTitle + "_Season_" + $batSeason + $script:scriptExt
                New-GeneratedScript -Cmd $cmd -FileName $fileName -ServiceOption $serviceOption -ScriptOS $scriptOS -ScriptOutputPath $scriptOutputPath -MoveVideos $moveVideos
            }
            elseif ($episodeSelection -eq "specific") {
                if ($scriptType -eq "single") {
                    while ($true) {
                        $episodeInput = Read-UserInput "Enter episode numbers or range for the script(s) -e (e.g., 1-3, 1,2,3)"
                        if ($episodeInput -match "^\s*(\d+)\s*-\s*(\d+)\s*$" -or $episodeInput -match "^\s*\d+(\s*,\s*\d+)*\s*$") { break }
                        else { Write-Host "Invalid input. Please enter a valid range or comma-separated list." }
                    }
                    $episodeOption = "-e " + $episodeInput
                    if ($serviceOption -eq "hidive") {
                        $cmd = $aniDLPath + ' --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --originalFontSize false --fontSize ' + $chosenFontSize + ' --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $fileNamePayload + '"'
                    }
                    else {
                        $cmd = $aniDLPath + ' --service "crunchy" ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --tsd --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $fileNamePayload + '"'
                    }
                    
                    $fileName = $batShowTitle + "_Season_" + $batSeason + $script:scriptExt
                    New-GeneratedScript -Cmd $cmd -FileName $fileName -ServiceOption $serviceOption -ScriptOS $scriptOS -ScriptOutputPath $scriptOutputPath -MoveVideos $moveVideos
                }
                elseif ($scriptType -eq "multiple") {
                    $validInput = $false
                    while (-not $validInput) {
                        $episodeInput = Read-UserInput "Enter episode numbers or range for the script(s) -e (e.g., 1-3, 1,2,3)"
                        $regex = [regex] "^\s*(\d+)\s*-\s*(\d+)\s*$"
                        $match = $regex.Match($episodeInput)
                        if ($match.Success) {
                            $validInput = $true
                            $rangeStart = [int]$match.Groups[1].Value
                            $rangeEnd = [int]$match.Groups[2].Value
                            $episodesArray = $rangeStart..$rangeEnd
                            $isRange = $true
                        }
                        elseif ($episodeInput -match "^\s*\d+(\s*,\s*\d+)*\s*$") {
                            $validInput = $true
                            $episodesArray = $episodeInput -split "," | ForEach-Object { [int]$_.Trim() }
                            $isRange = $false
                        }
                        else { 
                            Write-Host "Invalid input. Please enter a valid range or comma-separated list." 
                        }
                    }
                    if ($isRange) {
                        if (Get-YesNo 'Do you want to modify the Filename number of the generated Scripts?(Y/N)') {
                            $newCounter = Read-UserInput "Input the new episode start for the scripts (eg: 01, 13, 25)"
                            if ($newCounter -match "^\d+$") {
                                $counter = [int]$newCounter
                                $useModified = $true
                            }
                            else {
                                Write-Host "Invalid number, defaulting to 1."
                                $counter = 1
                                $useModified = $true
                            }
                        }
                        else {
                            $useModified = $false
                        }
                    }
                    else {
                        $useModified = $false
                    }
                    foreach ($ep in $episodesArray) {
                        if ($useModified) {
                            $epPadded = ([string]::Format("{0:D2}", $counter))
                            $currentEpTag = $epPadded
                            $counter++
                        }
                        else {
                            $epPadded = ([string]::Format("{0:D2}", $ep))
                            $currentEpTag = $epPadded
                        }
                        
                        # Re-evaluate payload for specific episodes so it uses the current tag
                        $specificFileNamePayload = $cmdShowTitle + ' - S' + $cmdSeason + 'E' + $currentEpTag + ' [${height}p]'
                        if ($scriptOS -eq "Linux") {
                            $specificFileNamePayload = $specificFileNamePayload.Replace('$', '\$').Replace('`', '\`')
                        }
                        
                        $episodeOption = "-e " + $ep
                        if ($serviceOption -eq "hidive") {
                            $cmd = $aniDLPath + ' --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --originalFontSize false --fontSize ' + $chosenFontSize + ' --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $specificFileNamePayload + '"'
                        }
                        else {
                            $cmd = $aniDLPath + ' --service "crunchy" ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --tsd --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $specificFileNamePayload + '"'
                        }
                        
                        $fileName = $batShowTitle + "_Season_" + $batSeason + "_E" + $currentEpTag + $script:scriptExt
                        New-GeneratedScript -Cmd $cmd -FileName $fileName -ServiceOption $serviceOption -ScriptOS $scriptOS -ScriptOutputPath $scriptOutputPath -MoveVideos $moveVideos
                    }
                }
            }
            elseif ($episodeSelection -eq "all-but-one") {
                while ($true) {
                    $skipInput = Read-UserInput "This will download all episodes but one. Which episode(s) do you want to skip? (e.g., '1' or '1,3,7')"
                    if ($skipInput -match "^\s*\d+(\s*,\s*\d+)*\s*$") { break }
                    else { Write-Host "Invalid input. Please enter a valid number or comma-separated list." }
                }
                $skipForFilename = ($skipInput -replace "\s", "") -replace ",", "_"
                if ($serviceOption -eq "hidive") {
                    $cmd = $aniDLPath + ' --service "' + $serviceOption + '" --srz ' + $seriesID + ' --but -e ' + $skipInput + ' --dubLang ' + $chosenDubLang + ' --originalFontSize false --fontSize ' + $chosenFontSize + ' --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '"'
                }
                else {
                    $cmd = $aniDLPath + ' --service "crunchy" ' + $flag + ' ' + $seriesID + ' --but -e ' + $skipInput + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --tsd --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $fileNamePayload + '"'
                }
                
                $fileName = $batShowTitle + "_Season_" + $batSeason + "_all-but-" + $skipForFilename + $script:scriptExt
                New-GeneratedScript -Cmd $cmd -FileName $fileName -ServiceOption $serviceOption -ScriptOS $scriptOS -ScriptOutputPath $scriptOutputPath -MoveVideos $moveVideos
            }
        }
        $nextAction = Get-NextAction
        if ($nextAction -eq "NO") {
            $searchLoopActive = $false
            $runScript = $false
        }
        elseif ($nextAction -eq "CHANGE_SERVICE") {
            $searchLoopActive = $false
        }
    }
}