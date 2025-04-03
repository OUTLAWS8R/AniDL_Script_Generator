Write-Host "Welcome to DKB Search and Script Generator"

# Define available services.
$services = @("Crunchyroll", "Hidive")

# --- Helper Functions ---
function Get-SelectionFromListWithDefault($prompt, [string[]]$list, $default) {
    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host "[$i] $($list[$i])"
    }
    $finalPrompt = "$prompt (Leave blank for default $default):"
    while ($true) {
        $selection = Read-Host $finalPrompt
        if ([string]::IsNullOrWhiteSpace($selection)) {
            return $default
        }
        if ($selection -match "^\d+$" -and [int]$selection -ge 0 -and [int]$selection -lt $list.Count) {
            return $list[[int]$selection]
        }
        else {
            Write-Host "Invalid selection. Please enter a number between 0 and $($list.Count - 1), or leave blank for default."
        }
    }
}

function Get-YesNo($prompt) {
    while ($true) {
        $input = Read-Host $prompt
        switch ($input.ToLower()) {
            "yes" { return $true }
            "y"   { return $true }
            "no"  { return $false }
            "n"   { return $false }
            default { Write-Host "Please enter 'yes' or 'no'." }
        }
    }
}

function Get-Selection($prompt, [string[]]$allowed) {
    while ($true) {
        $input = Read-Host $prompt
        if ($allowed -contains $input) { return $input }
        else { Write-Host "Invalid selection. Allowed values: $($allowed -join ', ')." }
    }
}

function Get-VideoTitle {
    $inputVideoTitle = Read-Host "Enter VideoTitle name ([DKB Team] default):"
    if ([string]::IsNullOrWhiteSpace($inputVideoTitle)) { return "[DKB Team]" }
    else { return $inputVideoTitle.Trim() }
}

# Debug function.
$debugMode = $false
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
            Write-Host "Title: $($s.Title), Season: $($s.Season), SeriesID: $($s.SeriesID)"
        }
    }
}

# --- End Helper Functions ---

# --- Service & Master Path Setup ---
$chosenService = Get-SelectionFromListWithDefault "Choose a service:" $services "Crunchyroll"
if ($chosenService -eq "Hidive") {
    $masterPath = "REPLACE_WITH_YOUR_HIDIVE_PATH".Trim()
    $authScriptCurrent = "$masterPath\Auth_HDV.bat"
    $serviceOption = "hidive"
    $extraParam = ""
} else {
    $masterPath = "REPLACE_WITH_YOUR_CR_PATH".Trim()
    $authScriptCurrent = "$masterPath\Auth_CR.bat"
    $serviceOption = "crunchy"
    $extraParam = '--crapi "web"'
}
$aniDLPath = "$masterPath\aniDL.exe"
$scriptOutputPath = "$masterPath\Generated_Scripts"
if (!(Test-Path $scriptOutputPath)) { New-Item -ItemType Directory -Path $scriptOutputPath | Out-Null }
# For Crunchyroll, we use these lines:
$pushdLine = 'pushd "' + $masterPath + '"'
$moveLine  = 'move "' + $masterPath + '\videos\*.mkv" "%CD%"'

# Helper function to normalize numbers.
function Normalize-Number($num) {
    return ([string]::Format("{0:D2}", [int]$num))
}

# --- Parse-Series Function ---
function Parse-Series {
    param($searchResults)
    $foundSeries = @()
    foreach ($line in $searchResults -split "`r?`n") {
        $trimmedLine = $line.Trim()
        # Skip common header lines.
        if ($trimmedLine -match "^(Found movie lists:|Found episodes:|Newly added:)") { continue }
        if ($trimmedLine -match "^(Top results:|Found series:|Total results:)") { continue }
        # HIDIVE series pattern.
        if ($serviceOption -eq "hidive" -and $trimmedLine -match "^\[Z\.([0-9]+)\]\s+(.+?)\s+\((\d+)\s+Seasons\)") {
            $seriesID = $matches[1].Trim()
            $title = $matches[2].Trim()
            $seasonCount = $matches[3].Trim()
            $seriesObj = [PSCustomObject]@{
                Title        = $title
                Season       = "1"       # Default to season 1.
                SeasonCount  = $seasonCount
                Type         = "HIDIVE"
                EpisodeCount = $null
                SeriesID     = $seriesID
                Versions     = $null
                Subtitles    = $null
            }
            $foundSeries += $seriesObj
            continue
        }
        # Crunchyroll series pattern – works for both --search and --new outputs.
        if ($serviceOption -eq "crunchy" -and $trimmedLine -match "^\[Z:[^\]\|]+(?:\|SRZ\.[^\]]+)?\]\s+(.+?)\s+\(Seasons:\s*(\d+)(?:,\s*EPs:\s*(\d+))?\)\s+\[(.*?)\]") {
            $title = $matches[1].Trim()
            $season = $matches[2].Trim()
            $epCount = $matches[3]
            $type = $matches[4].Trim()
            $seriesObj = [PSCustomObject]@{
                Title        = $title
                Season       = $season
                Type         = $type
                EpisodeCount = $epCount
                SeriesID     = $null
                Versions     = $null
                Subtitles    = $null
            }
            $foundSeries += $seriesObj
            continue
        }
        elseif ($trimmedLine -match "^\[S:([^\]]+)\]\s+(.+?)\s+\(Season:? (\d+)\)\s+\[(.*?)\]") {
            $seriesID = $matches[1].Trim()
            $title = $matches[2].Trim()
            $season = $matches[3].Trim()
            $type = $matches[4].Trim()
            $existing = $foundSeries | Where-Object { $_.Title -eq $title -and $_.Season -eq $season }
            if ($existing) {
                foreach ($obj in $existing) { $obj.SeriesID = $seriesID }
            }
            else {
                $seriesObj = [PSCustomObject]@{
                    Title        = $title
                    Season       = $season
                    Type         = $type
                    EpisodeCount = $null
                    SeriesID     = $seriesID
                    Versions     = $null
                    Subtitles    = $null
                }
                $foundSeries += $seriesObj
            }
        }
        elseif ($trimmedLine -match "^- Versions:\s*(.+)") {
            $versions = $matches[1].Trim()
            if ($foundSeries.Count -gt 0) { $foundSeries[-1].Versions = $versions }
        }
        elseif ($trimmedLine -match "^- Subtitles:\s*(.+)") {
            $subs = $matches[1].Trim()
            if ($foundSeries.Count -gt 0) {
                if (-not $foundSeries[-1].PSObject.Properties["Subtitles"]) {
                    $foundSeries[-1] | Add-Member -MemberType NoteProperty -Name Subtitles -Value $subs
                }
                else { $foundSeries[-1].Subtitles = $subs }
            }
        }
    }
    return $foundSeries
}

$defaultShowTitle = '${showTitle}'
$defaultSeason = '${season}'
$defaultEpisode = '${episode}'

# --- Main Loop ---
while ($true) {
    Write-Host "Enter Anime Name or type New to check the latest series:" -NoNewline
    $animeName = Read-Host

    # For Crunchyroll, if the input equals "New" (case-insensitive), use the --new flag.
    if ($serviceOption -eq "crunchy" -and $animeName -ieq "new") {
        $searchResults = & $aniDLPath --service $serviceOption $extraParam --new
    }
    elseif ($serviceOption -eq "crunchy") {
        $searchResults = & $aniDLPath --service $serviceOption $extraParam --search "$animeName"
    }
    else {
        # For HIDIVE, always use --search.
        $searchResults = & $aniDLPath --service $serviceOption --search "$animeName"
    }
    
    if (-not $searchResults) {
        Write-Host "No results found. Try again."
        continue
    }
    
    $foundSeries = Parse-Series $searchResults
    $foundSeries = @($foundSeries)  # Ensure array context

    Write-DebugInfo -rawResults $searchResults -seriesArray $foundSeries

    if (-not $foundSeries) {
        Write-Host "No anime found. Exiting."
        exit
    }
    
    Write-Host "---- Available Series ----"
    for ($i = 0; $i -lt $foundSeries.Count; $i++) {
        $displayLine = "[$i] $($foundSeries[$i].Title) - Season $($foundSeries[$i].Season) ($($foundSeries[$i].Type))"
        if ($foundSeries[$i].EpisodeCount) { $displayLine += " - EPs: $($foundSeries[$i].EpisodeCount)" }
        if ($foundSeries[$i].SeriesID) { $displayLine += " [S:$($foundSeries[$i].SeriesID)]" }
        Write-Host $displayLine
        if ($foundSeries[$i].Versions) { Write-Host "    - Versions: $($foundSeries[$i].Versions)" }
        if ($foundSeries[$i].Subtitles) { Write-Host "    - Subtitles: $($foundSeries[$i].Subtitles)" }
    }
    
    while ($true) {
        $seriesIndices = Read-Host "Enter the numbers of the series (comma-separated)"
        $selectedSeries = $seriesIndices -split "," | ForEach-Object {
            $index = $_.Trim()
            if ($index -match "^\d+$" -and [int]$index -ge 0 -and [int]$index -lt $foundSeries.Count) {
                $foundSeries[[int]$index]
            }
        }
        if ($selectedSeries) { break }
        Write-Host "Invalid selection. Please enter valid numbers from the list."
    }
    
    foreach ($series in $selectedSeries) {
        $seriesID = $series.SeriesID
        $origShowTitle = ($series.Title -replace '[\\/:*?"<>|]', '') -replace '\s+', ' '
        if ($series.Season -match "^\d+$") {
            if ([int]$series.Season -lt 10) { $origSeason = "0" + [int]$series.Season }
            else { $origSeason = $series.Season }
        }
        else { $origSeason = $series.Season }
        $origEpisode = "1"
        
        # --- Language Prompts ---
        if ($serviceOption -eq "hidive") {
            $availableDubLangs = @("jpn", "en-US", "spa-419", "pt-BR")
            $chosenDubLang = Get-SelectionFromListWithDefault "Choose a dub language to download:" $availableDubLangs "jpn"
            $chosenDefaultAudio = Get-SelectionFromListWithDefault "Choose a default Audio language:" $availableDubLangs "jpn"
            $availableSubs = @("en-US", "ja-JP", "spa-419", "pt-BR")
            $chosenSub = Get-SelectionFromListWithDefault "Choose the default subtitle for the script:" $availableSubs "en-US"
        }
        else {
            if ($series.Versions) {
                $availableDubLangs = $series.Versions -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
                $chosenDubLang = Get-SelectionFromListWithDefault "Choose a dub language to download:" $availableDubLangs "ja-JP"
                $chosenDefaultAudio = Get-SelectionFromListWithDefault "Choose a default Audio language:" $availableDubLangs "ja-JP"
            }
            else {
                $chosenDubLang = "ja-JP"
                $chosenDefaultAudio = "ja-JP"
            }
            if ($series.Subtitles) {
                $availableSubs = $series.Subtitles -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
                $chosenSub = Get-SelectionFromListWithDefault "Choose the default subtitle for the script:" $availableSubs "en-US"
            }
            else { $chosenSub = "en-US" }
        }
        # --- End Language Prompts ---
        
        $chosenVideoTitle = Get-VideoTitle
        
        while ($true) {
            $episodeSelection = Read-Host "Do you want to download all episodes or specific episodes? (all/specific/all-but-one)"
            if ($episodeSelection -match "^(all|specific|all-but-one)$") { break }
            else { Write-Host "Please choose from: all, specific, or all-but-one." }
        }
        
        $allScriptType = ""
        if ($episodeSelection -eq "all") {
            $allScriptType = Get-Selection "Do you want a single script or multiple scripts (one per episode)? (single/multiple)" @("single", "multiple")
        }
        
        $inputShowTitle = Read-Host "Enter new show title for filename (leave blank for default [$origShowTitle]):"
        if ($inputShowTitle -ne "") {
            $cleaned = $inputShowTitle -replace '[\\/:*?"<>|]', ""
            $cmdShowTitle = $cleaned.Trim()
            $batShowTitle = $cleaned.Trim() -replace ' ', '_'
        }
        else {
            $cmdShowTitle = $origShowTitle
            $batShowTitle = $origShowTitle -replace '\s+', '_'
        }
        
        $inputSeason = Read-Host "Enter new season value (leave blank for default [$origSeason]):"
        if ($inputSeason -ne "") {
            if ($inputSeason -match "^\d+$") { $cmdSeason = Normalize-Number $inputSeason }
            else { $cmdSeason = $inputSeason }
            $batSeason = $cmdSeason
        }
        else {
            $cmdSeason = Normalize-Number $origSeason
            $batSeason = $cmdSeason
        }
        
        if ($episodeSelection -eq "all") {
            $cmdEpisode = $defaultEpisode
            $batEpisode = "01"
            if ($allScriptType -eq "single") {
                if ($serviceOption -eq "hidive") {
                    $episodeOption = "--all"
                    $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -e 1 -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $fileNameArg
                    $batchContent = @(
                        "chcp 65001",
                        "@echo off",
                        "SET ORIGINAL=%CD%",
                        "pushd ""$masterPath""",
                        "call ""$authScriptCurrent""",
                        "popd",
                        $cmd,
                        "pushd ""$masterPath\videos""",
                        "call ""$masterPath\videos\rename_mkv_tracks.bat""",
                        "move ""$masterPath\videos\*.mkv"" ""%ORIGINAL%""",
                        "if not defined SKIP_PAUSE pause"
                    )
                }
                else {
                    $episodeOption = "--all"
                    $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" ' + $extraParam + ' -s ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $fileNameArg
                    $batchContent = @(
                        "@echo off",
                        "chcp 65001 >nul",
                        $pushdLine,
                        "call ""$authScriptCurrent""",
                        "popd",
                        $cmd,
                        $moveLine,
                        "if not defined SKIP_PAUSE pause"
                    )
                }
                $batFile = $scriptOutputPath + "\" + $batShowTitle + "_Season_" + $batSeason + ".bat"
                [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "Created script: " + $batFile
            }
            else {
                if ($series.EpisodeCount -match "^\d+$") {
                    $epTotal = [int]$series.EpisodeCount
                    $episodes = 1..$epTotal | ForEach-Object { $_.ToString() }
                }
                else {
                    while ($true) {
                        $episodeInput = Read-Host "Episode count not available. Enter episode numbers or range for the script(s) -e (e.g., 1-3, 1,2,3):"
                        $regex = [regex] "^\s*(\d+)\s*-\s*(\d+)\s*$"
                        $match = $regex.Match($episodeInput)
                        if ($match.Success) {
                            $startEp = [int]$match.Groups[1].Value
                            $endEp = [int]$match.Groups[2].Value
                            $episodes = $startEp..$endEp | ForEach-Object { $_.ToString() }
                            break
                        }
                        elseif ($episodeInput -match "^\s*\d+(\s*,\s*\d+)+\s*$") {
                            $episodes = $episodeInput -split "," | ForEach-Object { $_.Trim() }
                            break
                        }
                        else {
                            Write-Host "Invalid input. Please enter a valid range or comma-separated list."
                        }
                    }
                }
                if (Get-YesNo "Use modified start count for generated script names? (yes/no)") {
                    $counter = [int]$batEpisode
                }
                else {
                    $counter = 1
                }
                foreach ($ep in $episodes) {
                    $epPadded = ([string]::Format("{0:D2}", $counter))
                    $dynamicFileNameArg = '--fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E' + $epPadded + ' [${height}p]"'
                    $batFileName = $batShowTitle + "_Season_" + $batSeason + "_E" + $epPadded + ".bat"
                    $episodeOption = "-e " + $ep
                    if ($serviceOption -eq "hidive") {
                        $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                        $batchContent = @(
                            "chcp 65001",
                            "@echo off",
                            "SET ORIGINAL=%CD%",
                            "pushd ""$masterPath""",
                            "call ""$authScriptCurrent""",
                            "popd",
                            $cmd,
                            "pushd ""$masterPath\videos""",
                            "call ""$masterPath\videos\rename_mkv_tracks.bat""",
                            "move ""$masterPath\videos\*.mkv"" ""%ORIGINAL%""",
                            "if not defined SKIP_PAUSE pause"
                        )
                    }
                    else {
                        $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" ' + $extraParam + ' -s ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                        $batchContent = @(
                            "@echo off",
                            "chcp 65001 >nul",
                            $pushdLine,
                            "call ""$authScriptCurrent""",
                            "popd",
                            $cmd,
                            $moveLine,
                            "if not defined SKIP_PAUSE pause"
                        )
                    }
                    $batFile = $scriptOutputPath + "\" + $batFileName
                    [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                    Write-Host "Created script: " + $batFile
                    $counter++
                }
            }
        }
        elseif ($episodeSelection -eq "specific") {
            $scriptType = Get-Selection "Do you want a single script or multiple scripts? (single/multiple)" @("single", "multiple")
            if ($scriptType -eq "single") {
                while ($true) {
                    $episodeInput = Read-Host "Enter episode numbers or range for the script(s) -e (e.g., 1-3, 1,2,3)"
                    if ($episodeInput -match "^\s*(\d+)\s*-\s*(\d+)\s*$" -or $episodeInput -match "^\s*\d+(\s*,\s*\d+)*\s*$") { break }
                    else { Write-Host "Invalid input. Please enter a valid range or comma-separated list." }
                }
                $episodeOption = "-e " + $episodeInput
                if ($serviceOption -eq "hidive") {
                    $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $fileNameArg
                    $batchContent = @(
                        "chcp 65001",
                        "@echo off",
                        "SET ORIGINAL=%CD%",
                        "pushd ""$masterPath""",
                        "call ""$authScriptCurrent""",
                        "popd",
                        $cmd,
                        "pushd ""$masterPath\videos""",
                        "call ""$masterPath\videos\rename_mkv_tracks.bat""",
                        "move ""$masterPath\videos\*.mkv"" ""%ORIGINAL%""",
                        "if not defined SKIP_PAUSE pause"
                    )
                }
                else {
                    $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" ' + $extraParam + ' -s ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $fileNameArg
                    $batchContent = @(
                        "@echo off",
                        "chcp 65001 >nul",
                        $pushdLine,
                        "call ""$authScriptCurrent""",
                        "popd",
                        $cmd,
                        $moveLine,
                        "if not defined SKIP_PAUSE pause"
                    )
                }
                $batFile = $scriptOutputPath + "\" + $batShowTitle + "_Season_" + $batSeason + ".bat"
                [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "Created script: " + $batFile
            }
            elseif ($scriptType -eq "multiple") {
                $validInput = $false
                while (-not $validInput) {
                    $episodeInput = Read-Host "Enter episode numbers or range for the script(s) -e (e.g., 1-3, 1,2,3)"
                    $regex = [regex] "^\s*(\d+)\s*-\s*(\d+)\s*$"
                    $match = $regex.Match($episodeInput)
                    if ($match.Success) {
                        $validInput = $true
                        $startEp = [int]$match.Groups[1].Value
                        $endEp = [int]$match.Groups[2].Value
                        $episodes = $startEp..$endEp | ForEach-Object { $_.ToString() }
                    }
                    elseif ($episodeInput -match "^\s*\d+(\s*,\s*\d+)+\s*$") {
                        $validInput = $true
                        $episodes = $episodeInput -split "," | ForEach-Object { $_.Trim() }
                    }
                    else { Write-Host "Invalid input. Please enter a valid range or comma-separated list." }
                }
                if (($batEpisode) -ne $null) { $counter = [int]$batEpisode } else { $counter = 1 }
                foreach ($ep in $episodes) {
                    $epPadded = ([string]::Format("{0:D2}", $counter))
                    $dynamicFileNameArg = '--fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E' + $epPadded + ' [${height}p]"'
                    $batFileName = $batShowTitle + "_Season_" + $batSeason + "_E" + $epPadded + ".bat"
                    $episodeOption = "-e " + $ep
                    if ($serviceOption -eq "hidive") {
                        $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                        $batchContent = @(
                            "chcp 65001",
                            "@echo off",
                            "SET ORIGINAL=%CD%",
                            "pushd ""$masterPath""",
                            "call ""$authScriptCurrent""",
                            "popd",
                            $cmd,
                            "pushd ""$masterPath\videos""",
                            "call ""$masterPath\videos\rename_mkv_tracks.bat""",
                            "move ""$masterPath\videos\*.mkv"" ""%ORIGINAL%""",
                            "if not defined SKIP_PAUSE pause"
                        )
                    }
                    else {
                        $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" ' + $extraParam + ' -s ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                        $batchContent = @(
                            "@echo off",
                            "chcp 65001 >nul",
                            $pushdLine,
                            "call ""$authScriptCurrent""",
                            "popd",
                            $cmd,
                            $moveLine,
                            "if not defined SKIP_PAUSE pause"
                        )
                    }
                    $batFile = $scriptOutputPath + "\" + $batFileName
                    [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                    Write-Host "Created script: " + $batFile
                    $counter++
                }
            }
        }
        elseif ($episodeSelection -eq "all-but-one") {
            while ($true) {
                $skipInput = Read-Host "This will download all episodes but one. Which episode(s) do you want to skip? (e.g., '1' or '1,3,7')"
                if ($skipInput -match "^\s*\d+(\s*,\s*\d+)*\s*$") { break }
                else { Write-Host "Invalid input. Please enter a valid number or comma-separated list." }
            }
            $skipForFilename = ($skipInput -replace "\s", "") -replace ",", "_"
            if ($serviceOption -eq "hidive") {
                $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' --but -e ' + $skipInput + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $fileNameArg
                $batchContent = @(
                    "chcp 65001",
                    "@echo off",
                    "SET ORIGINAL=%CD%",
                    "pushd ""$masterPath""",
                    "call ""$authScriptCurrent""",
                    "popd",
                    $cmd,
                    "pushd ""$masterPath\videos""",
                    "call ""$masterPath\videos\rename_mkv_tracks.bat""",
                    "move ""$masterPath\videos\*.mkv"" ""%ORIGINAL%""",
                    "if not defined SKIP_PAUSE pause"
                )
            }
            else {
                $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" ' + $extraParam + ' -s ' + $seriesID + ' --but -e ' + $skipInput + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $fileNameArg
                $batchContent = @(
                    "@echo off",
                    "chcp 65001 >nul",
                    $pushdLine,
                    "call ""$authScriptCurrent""",
                    "popd",
                    $cmd,
                    $moveLine,
                    "if not defined SKIP_PAUSE pause"
                )
            }
            $batFile = $scriptOutputPath + "\" + $batShowTitle + "_Season_" + $batSeason + "_all-but-" + $skipForFilename + ".bat"
            [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "Created script: " + $batFile
        }
    }
    
    if (-not (Get-YesNo "Do you want to search for another anime? (yes/no)")) { break }
}
