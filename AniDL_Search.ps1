Write-Host "Welcome to DKB Search and Script Generator"

# --- Path Auto-Discovery ---
# Automatically find the master path where aniDL.exe and its files are located.
try {
    $aniDLFullPath = (Get-Command -Name aniDL.exe -CommandType Application -ErrorAction Stop).Source
    $masterPath = Split-Path -Path $aniDLFullPath -Parent
    Write-Host "aniDL master path automatically detected: $masterPath" -ForegroundColor Green
}
catch {
    Write-Host "------------------------------------------------------------" -ForegroundColor Red
    Write-Host "[FATAL ERROR] Could not find 'aniDL.exe' in your system's PATH." -ForegroundColor Red
    Write-Host "Please ensure aniDL is installed and its location is added to the PATH environment variable before running this script."
    Write-Host "------------------------------------------------------------" -ForegroundColor Red
    Read-Host "Press Enter to exit."
    exit
}

# Define available services.
$services = @("Crunchyroll", "Hidive")

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
            Write-Host "Title: $($s.Title), Season: $($s.Season), Type: $($s.Type), SeriesID: $($s.SeriesID), ZID: $($s.ZID)"
        }
    }
}

function Normalize-Number($num) {
    return ([string]::Format("{0:D2}", [int]$num))
}

# --- Helper Functions ---
function Handle-NoResults {
    while ($true) {
        Write-Host "No Anime found. " -NoNewline -ForegroundColor Yellow
        $input = Read-Host "Wanna do a new search(n), change service(s) or exit(Press Enter)? :"
        
        switch ($input.Trim().ToLower()) {
            'n'              { return "NEW_SEARCH" }
            'new search'     { return "NEW_SEARCH" }
            's'              { return "CHANGE_SERVICE" }
            'change service' { return "CHANGE_SERVICE" }
            ''               { return "EXIT" } # Handles the Enter key
            'exit'           { return "EXIT" }
            default {
                # If none of the above match, show an error and the loop will repeat
                Write-Host "Invalid selection. Please enter 'n'/'new search', 's'/'change service', or 'exit' (or just press Enter)." -ForegroundColor Red
            }
        }
    }
}

function Get-NextAction {
    while ($true) {
        $input = Read-Host "Do you want to search for another anime (Yes(y)/No(n))? or change service(cs)"
        switch ($input.Trim().ToLower()) {
            "yes"            { return "YES" }
            "y"              { return "YES" }
            "no"             { return "NO" }
            "n"              { return "NO" }
            "cs"             { return "CHANGE_SERVICE" }
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
        $selection = Read-Host $finalPrompt
        if ([string]::IsNullOrWhiteSpace($selection)) {
            return $default
        }
        if ($selection -match "^\d+$" -and [int]$selection -ge 0 -and [int]$selection -lt $list.Count) {
            return $list[[int]$selection]
        } else {
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
        else { Write-Host "Invalid selection. Allowed values: $($allowed -join ', ')" }
    }
}

function Get-SingleMultiple($prompt) {
    while ($true) {
        $input = Read-Host $prompt
        $lc = $input.ToLower().Trim(":"[0], " "[0])
        if ($lc -eq "single" -or $lc -eq "s") { return "single" }
        elseif ($lc -eq "multiple" -or $lc -eq "m") { return "multiple" }
        else { Write-Host "Invalid selection. Please enter Single(S) or Multiple(M)." }
    }
}

function Get-VideoTitle {
    $inputVideoTitle = Read-Host "Enter VideoTitle name ([DKB Team] default)"
    if ([string]::IsNullOrWhiteSpace($inputVideoTitle)) { return "[DKB Team]" }
    else { return $inputVideoTitle.Trim() }
}

function Get-ExperimentalFeatureConsent {
    while ($true) {
        $input = Read-Host 'Wanna use the experimental feature?Y/N or Leave blank for Crunchyroll Classic'
        switch ($input.ToLower().Trim()) {
            'y'   { return $true }
            'yes' { return $true }
            'n'   { return $false }
            'no'  { return $false }
            ''    { return $false }
            default { Write-Host "Please enter Y/N or Yes/No." }
        }
    }
}

function Parse-Series {
    param($searchResults)

    $foundSeries = @()
    # State variables to store info from the last "master" [Z:] series.
    $lastMasterTitle = ""
    $lastMasterZID = ""

    # Allowed languages list.
    $allowedLangs = @("en-US", "en-IN", "es-419", "es-ES", "fr-FR", "pt-BR", "pt-PT", "ar-ME", "ar-SA", "it-IT", "de-DE", "ru-RU", "tr-TR", "hi-IN", "ca-ES", "pl-PL", "th-TH", "ta-IN", "ms-MY", "vi-VN", "id-ID", "te-IN", "zh-CN", "zh-HK", "zh-TW", "ko-KR", "ja-JP")

    foreach ($line in $searchResults -split "`r?`n") {
        $trimmedLine = $line.Trim()

        # Skip header or irrelevant lines
        if ($trimmedLine -match "^(Found movie lists:|Found episodes:|Newly added:|Top results:|Found series:|Total results:|===|USER:|Your Country:)" -or [string]::IsNullOrWhiteSpace($trimmedLine)) {
            continue
        }

        # HIDIVE series pattern (kept for compatibility).
        if ($serviceOption -eq "hidive" -and $trimmedLine -match "^\[Z\.([0-9]+)\]\s+(.+?)\s+\((\d+)\s+Seasons\)") {
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

        # --- Universal Regex for both S and Z lines ---
        if ($line -match "^(\s*)\[(Z|S):([^\|\]]+)[^\]]*\]\s+(.+?)\s+\((.*?)\)\s+\[(.*?)\]") {
            $indentation  = $matches[1]
            $idPrefix     = $matches[2]
            $idValue      = $matches[3].Trim()
            $title        = $matches[4].Trim()
            $metadata     = $matches[5].Trim()
            $type         = $matches[6].Trim()

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
                $lastMasterZID   = $seriesObj.ZID
            } else { # idPrefix is 'S'
                $seriesObj.SeriesID = $idValue
                $seriesObj.ZID = $lastMasterZID
                if ($indentation.Length -gt 0 -and $seriesObj.Title -match "^\s*Season\s+\d+\s*$") {
                    $seriesObj.Title = $lastMasterTitle
                }
            }
            
            $foundSeries += $seriesObj
        }
        # Process Versions and Subtitles
        elseif ($trimmedLine -match "^-\s+Versions:\s*(.+)") {
            if ($foundSeries.Count -gt 0) {
                $rawVersions = $matches[1].Trim()
                $parsedVersions = $rawVersions -split "," | ForEach-Object { $_.Trim() } | Where-Object { $allowedLangs -contains $_ }
                $foundSeries[-1].Versions = $parsedVersions
            }
        }
        elseif ($trimmedLine -match "^-\s+Subtitles:\s*(.+)") {
            if ($foundSeries.Count -gt 0) {
                $rawSubs = $matches[1].Trim()
                $parsedSubs = $rawSubs -split "," | ForEach-Object { $_.Trim() } | Where-Object { $allowedLangs -contains $_ }
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

    # Returning all items to allow for dynamic pagination later
    $finalArray = $uniqueSeries.ToArray()
    return $finalArray
}

# --- Global Language map for easy extension ---
$languageDetails = [ordered]@{
    "Japanese" = @{ Code = 'ja-JP'; TrackName = 'Japanese' }
    "Chinese"  = @{ Code = 'zh-CN'; TrackName = 'Chinese (Mainland China)' }
}

# --- Experimental Crunchyroll Script Generator ---
function Generate-ExperimentalCrunchyrollScript {
    param(
        [string]$aniDLPath,
        [string]$masterPath,
        [string]$authScriptCurrent,
        [string]$scriptOutputPath
    )
    while ($true) {
        $animeName = Read-Host "Enter Anime Name or type New to check the latest series (Experimental)"
        $serviceOption = "crunchy"
        if ($animeName -ieq "new") {
            $searchResults = & $aniDLPath --service $serviceOption --new
        } else {
            $searchResults = & $aniDLPath --service $serviceOption --search "$animeName"
        }
        
        $foundSeries = Parse-Series $searchResults
        
        if (-not $foundSeries) {
            $action = Handle-NoResults
            if ($action -eq "NEW_SEARCH") { continue }
            if ($action -eq "CHANGE_SERVICE") { return "CHANGE_SERVICE" }
            if ($action -eq "EXIT") { return "EXIT" }
        }
        
        $foundSeries = @($foundSeries)
        Write-DebugInfo -rawResults $searchResults -seriesArray $foundSeries

        Write-Host "---- Available Series (Experimental) ----"
        
        $startIndex = 0
        $displayLimit = 15
        $performNewSearch = $false

        while ($true) {
            $endIndex = [math]::Min($displayLimit, $foundSeries.Count)
            for ($i = $startIndex; $i -lt $endIndex; $i++) {
                $displayLine = "[$i] $($foundSeries[$i].Title) - Season $($foundSeries[$i].Season) ($($foundSeries[$i].Type))"
                if ($foundSeries[$i].EpisodeCount) { $displayLine += " - EPs: $($foundSeries[$i].EpisodeCount)" }
                if ($foundSeries[$i].SeriesID) { $displayLine += " [S:$($foundSeries[$i].SeriesID)]" }
                if ($foundSeries[$i].ZID -and -not $foundSeries[$i].SeriesID) { $displayLine += " [Z:$($foundSeries[$i].ZID)]" }
                Write-Host $displayLine
                if ($foundSeries[$i].Versions) { Write-Host "    - Versions: $($foundSeries[$i].Versions -join ', ')" }
                if ($foundSeries[$i].Subtitles) { Write-Host "    - Subtitles: $($foundSeries[$i].Subtitles -join ', ')" }
            }

            $seriesIndices = Read-Host "Enter the number(s) of the serie(s) or new search(n) (comma-separated),more search results(Enter):"
            
            # Pagination Trigger
            if ([string]::IsNullOrWhiteSpace($seriesIndices)) {
                if ($displayLimit -ge $foundSeries.Count) {
                    Write-Host "No more results to display." -ForegroundColor Yellow
                } else {
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
                $flag = "-s" # Fallback
                $seriesID = $series.SeriesID
            }
            
            $chosenDubLangCode = "ja-JP"
            $chosenDubLangName = "Japanese"
            $chosenDubTrackName = "Japanese"

            Write-Host "--- Audio Language Selection ---" -ForegroundColor Yellow
            if ($series.Versions) {
                $availableDubLangs = $series.Versions
                $chosenDubLangCode = Get-SelectionFromListWithDefault "Choose a dub language to download:" $availableDubLangs "ja-JP"
                foreach ($langName in $languageDetails.Keys) {
                    if ($languageDetails[$langName].Code -eq $chosenDubLangCode) {
                        $chosenDubLangName = $langName
                        $chosenDubTrackName = $languageDetails[$langName].TrackName
                        break
                    }
                }
            } else {
                Write-Host "Audio versions were not listed in search results. Please choose manually."
                $allowedLangNames = $languageDetails.Keys
                $defaultLangName = ($allowedLangNames | Select-Object -First 1)
                $prompt = "Choose a dub language to download [Default: $defaultLangName]"

                while ($true) {
                    $userInput = Read-Host $prompt
                    if ([string]::IsNullOrWhiteSpace($userInput)) {
                        break
                    }
                    $matchedKey = $allowedLangNames | Where-Object { $_ -eq $userInput }
                    if ($matchedKey) {
                        $chosenDubLangCode = $languageDetails[$matchedKey].Code
                        $chosenDubLangName = $matchedKey
                        $chosenDubTrackName = $languageDetails[$matchedKey].TrackName
                        break
                    }
                    Write-Host "Invalid selection. Please enter one of: $($allowedLangNames -join ', ')" -ForegroundColor Red
                }
            }
            
            if ($series.Subtitles) {
                $availableSubs = $series.Subtitles
                $chosenSub = Get-SelectionFromListWithDefault "Choose the default subtitle for the script:" $availableSubs "en-US"
            } else { 
                $chosenSub = "en-US" 
            }
            
            $chosenVideoTitle = Get-VideoTitle
            
            $episodeSelection = $null
            while (-not $episodeSelection) {
                $input = Read-Host "Do you want to download all episodes or specific episodes? (all(a)/specific(s)/all-but-one(ab))"
                switch ($input.Trim().ToLower()) {
                    "all"           { $episodeSelection = "all" }
                    "a"             { $episodeSelection = "all" }
                    "specific"      { $episodeSelection = "specific" }
                    "s"             { $episodeSelection = "specific" }
                    "all-but-one"   { $episodeSelection = "all-but-one" }
                    "ab"            { $episodeSelection = "all-but-one" }
                    default { Write-Host "Invalid selection. Please enter all(a), specific(s), or all-but-one(ab)." -ForegroundColor Red }
                }
            }
            
            if ($episodeSelection -eq "all") {
                $scriptType = "single"
            } elseif ($episodeSelection -eq "specific") {
                $scriptType = Get-SingleMultiple "Do you want a single script or multiple scripts? (Single(S)/Multiple(M))"
            }
            
            # Clean title: Remove illegal chars AND replace dots with underscores
            $origShowTitle = ($series.Title -replace '[\\/:*?"<>|]', '') -replace '\s+', ' '
            
            $inputShowTitle = Read-Host "Enter new show title for filename (leave blank for default [$origShowTitle])"

            if ($inputShowTitle -ne "") {
                $cleaned = $inputShowTitle -replace '[\\/:*?"<>|]', ""
                $cmdShowTitle = $cleaned.Trim()
                $cmdShowTitle = $cmdShowTitle -replace "[\r\n]+", " "
                # Replace dots with underscores here
                $batShowTitle = ($cleaned.Trim() -replace ' ', '_') -replace '\.', '_'
            } else {
                $cmdShowTitle = $origShowTitle
                $cmdShowTitle = $cmdShowTitle -replace "[\r\n]+", " "
                # Replace dots with underscores here too
                $batShowTitle = ($origShowTitle -replace '\s+', '_') -replace '\.', '_'
            }
            
            if ($series.Season -match "^\d+$") {
                if ([int]$series.Season -lt 10) { $origSeason = "0" + [int]$series.Season }
                else { $origSeason = $series.Season }
            } else { 
                $origSeason = $series.Season 
            }
            
            $inputSeason = Read-Host "Enter new season value (leave blank for default [$origSeason])"
            if ($inputSeason -ne "") {
                if ($inputSeason -match "^\d+$") { 
                    $cmdSeason = Normalize-Number $inputSeason 
                } else { 
                    $cmdSeason = $inputSeason 
                }
                $batSeason = $cmdSeason
            } else {
                $cmdSeason = Normalize-Number $origSeason
                $batSeason = $cmdSeason
            }
            
            $actualShowName = $cmdShowTitle
            $batchEscapedActualShowName = $actualShowName -replace '!', '^!'
            
            $dynamicFileNameArg = '--fileName "Anime_Show - S' + $cmdSeason + 'E${episode} [${height}p]"'
            
            $videosSubDir = "videos"

            $failedMuxLogFile = "failed_mux_list.log"
            $clearLogFile = 'del /Q "' + $masterPath + '\' + $videosSubDir + '\' + $failedMuxLogFile + '" 2>nul' 
            
            $muxingMessage = @(
                "echo.",
                "echo --- Downloads complete. Now for the fucking magic: Muxing and Renaming... ---",
                "echo."
            )

            $reportFailedFiles = @(
                'if exist "' + $masterPath + '\' + $videosSubDir + '\' + $failedMuxLogFile + '" (',
                '    echo.',
                '    echo ^>^>^> WARNING: Audio not found for the following files ^<^<^<',
                '    type "' + $masterPath + '\' + $videosSubDir + '\' + $failedMuxLogFile + '"',
                '    del /Q "' + $masterPath + '\' + $videosSubDir + '\' + $failedMuxLogFile + '"',
                '    echo ^===================================================^',
                '    echo.',
                ')'
            )
            
            $muxAndRenameLogic = @(
                'for %%V in ("Anime_Show - S*.mkv") do (',
                '    set "AUDIO="',
                '    set "FULL=%%~nV"',
                "    for %%A in (`"!FULL!*$($chosenDubTrackName).audio.m4s`") do set `"AUDIO=%%~nxA`"",
                '    if defined AUDIO (',
                "        mkvmerge -q -o `"!FULL!_muxed.mkv`" `"%%V`" --language 0:$($chosenDubLangCode) --track-name 0:`"$($chosenDubTrackName)`" `"!AUDIO!`"",
                '        if exist "!FULL!_muxed.mkv" (',
                '            del /Q "%%V"',
                '            del /Q "!AUDIO!"',
                '        )',
                '    ) else (',
                "        echo WARNING: no audio matching `"!FULL!*$($chosenDubTrackName).audio.m4s`" found for `"%%~nxV`"",
                "        echo %%~nxV >> `"$($failedMuxLogFile)`"",
                '    )',
                ')',
                'for %%F in ("Anime_Show - S*_muxed.mkv") do (',
                '    set "filename=%%~nxF"',
                '    set "no_muxed=!filename:_muxed=!"',
                '    call set "newname=%%no_muxed:Anime_Show=%ACTUAL_SHOW_NAME%%%"',
                '    call ren "%%F" "!newname!"',
                ')'
            )

            if ($episodeSelection -eq "all") {
                $episodeOption = "--all"
                $cmd1 = $aniDLPath + ' --service "crunchy" ----vstream ps5 --tsd --noaudio ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLangCode + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                $cmd2 = $aniDLPath + ' --service "crunchy" --astream android --novids --nosubs ' + $flag + ' ' + $seriesID + ' --chapters false ' + $episodeOption + ' --dubLang ' + $chosenDubLangCode + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                $pushdMaster = 'pushd "' + $masterPath + '"'
                $callAuth = 'call "' + $authScriptCurrent + '"'
                $pushdVideos = 'pushd "' + $masterPath + '\' + $videosSubDir + '"'
                $moveVideos = 'move "' + $masterPath + '\' + $videosSubDir + '\*.mkv" "%CD%" 2>nul'
                $batchContent = @(
                    "@echo off", "chcp 65001 >nul", "SET ORIGINAL=%CD%", "set `"ACTUAL_SHOW_NAME=$($batchEscapedActualShowName -replace '[\r\n\t]', ' ')`"",
                    $pushdMaster, $callAuth, "popd", $clearLogFile, $cmd1, $cmd2
                ) + $muxingMessage + @(
                    "REM --- MUX AUDIO AND RENAME ---", "setlocal enabledelayedexpansion", $pushdVideos
                ) + $muxAndRenameLogic + @(
                    "popd", "endlocal", $moveVideos, "echo.", "echo --- Script finished. ---", $reportFailedFiles, "if not defined SKIP_PAUSE pause"
                )
                $batFile = $scriptOutputPath + "\" + $batShowTitle + "_Season_" + $batSeason + ".bat"
                [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "Created script: " + $batFile
            }
            elseif ($episodeSelection -eq "specific") {
                if ($scriptType -eq "single") {
                    while ($true) {
                        $episodeInput = Read-Host "Enter episode numbers or range for the script(s) -e (e.g., 1-3, 1,2,3)"
                        if ($episodeInput -match "^\s*(\d+)\s*-\s*(\d+)\s*$" -or $episodeInput -match "^\s*\d+(\s*,\s*\d+)*\s*$") { break }
                        else { Write-Host "Invalid input. Please enter a valid range or comma-separated list." }
                    }
                    $episodeOption = "-e " + $episodeInput
                    $cmd1 = $aniDLPath + ' --service "crunchy" --vstream ps5 --tsd --noaudio ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLangCode + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                    $cmd2 = $aniDLPath + ' --service "crunchy" --astream android --novids --nosubs ' + $flag + ' ' + $seriesID + ' --chapters false ' + $episodeOption + ' --dubLang ' + $chosenDubLangCode + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                    $pushdMaster = 'pushd "' + $masterPath + '"'
                    $callAuth = 'call "' + $authScriptCurrent + '"'
                    $pushdVideos = 'pushd "' + $masterPath + '\' + $videosSubDir + '"'
                    $moveVideos = 'move "' + $masterPath + '\' + $videosSubDir + '\*.mkv" "%CD%" 2>nul'
                    $batchContent = @(
                        "@echo off", "chcp 65001 >nul", "SET ORIGINAL=%CD%", "set `"ACTUAL_SHOW_NAME=$($batchEscapedActualShowName -replace '[\r\n\t]', ' ')`"",
                        $pushdMaster, $callAuth, "popd", $clearLogFile, $cmd1, $cmd2
                    ) + $muxingMessage + @(
                        "REM --- MUX AUDIO AND RENAME ---", "setlocal enabledelayedexpansion", $pushdVideos
                    ) + $muxAndRenameLogic + @(
                        "popd", "endlocal", $moveVideos, "echo.", "echo --- Script finished. ---", $reportFailedFiles, "if not defined SKIP_PAUSE pause"
                    )
                    $batFile = $scriptOutputPath + "\" + $batShowTitle + "_Season_" + $batSeason + ".bat"
                    [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                    Write-Host "Created script: " + $batFile
                }
                elseif ($scriptType -eq "multiple") {
                    $validInput = $false
                    while (-not $validInput) {
                        $episodeInput = Read-Host "Enter episode numbers or range for the script(s) -e (e.g., 1-3, 1,2,3)"
                        if ($episodeInput -match "^\s*(\d+)\s*-\s*(\d+)\s*$" -or $episodeInput -match "^\s*\d+(\s*,\s*\d+)*\s*$") {
                            $validInput = $true
                            $match = [regex]::Match($episodeInput, "^\s*(\d+)\s*-\s*(\d+)\s*$")
                            if ($match.Success) {
                                $rangeStart = [int]$match.Groups[1].Value
                                $rangeEnd = [int]$match.Groups[2].Value
                                $episodesArray = $rangeStart..$rangeEnd
                                $isRange = $true
                            } else {
                                $episodesArray = $episodeInput -split "," | ForEach-Object { [int]$_.Trim() }
                                $isRange = $false
                            }
                        } else { Write-Host "Invalid input. Please enter a valid range or comma-separated list." }
                    }
                    if ($isRange) {
                        if (Get-YesNo 'Do you want to modify the Filename number of the generated Scripts?(Y/N)') {
                            $newCounter = Read-Host "Input the new episode start for the scripts (eg: 01, 13, 25)"
                            if ($newCounter -match "^\d+$") { $counter = [int]$newCounter; $useModified = $true }
                            else { Write-Host "Invalid number, defaulting to 1."; $counter = 1; $useModified = $true }
                        } else { $useModified = $false }
                    } else { $useModified = $false }
                    
                    foreach ($ep in $episodesArray) {
                        if ($useModified) {
                            $currentEpTag = Normalize-Number($counter)
                            $counter++
                        } else {
                            $currentEpTag = Normalize-Number($ep)
                        }
                        
                        $batFileName = $batShowTitle + "_Season_" + $batSeason + "_E" + $currentEpTag + ".bat"
                        $episodeOption = "-e " + $ep
                        $dynamicFileNameArg = '--fileName "Anime_Show - S' + $cmdSeason + 'E' + $currentEpTag + ' [${height}p]"'
                        
                        $cmd1 = $aniDLPath + ' --service "crunchy" --vstream ps5 --tsd --noaudio ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLangCode + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                        $cmd2 = $aniDLPath + ' --service "crunchy" --astream android --novids --nosubs ' + $flag + ' ' + $seriesID + ' --chapters false ' + $episodeOption + ' --dubLang ' + $chosenDubLangCode + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                        $pushdMaster = 'pushd "' + $masterPath + '"'
                        $callAuth = 'call "' + $authScriptCurrent + '"'
                        $pushdVideos = 'pushd "' + $masterPath + '\' + $videosSubDir + '"'
                        $moveVideos = 'move "' + $masterPath + '\' + $videosSubDir + '\*.mkv" "%CD%" 2>nul'
                        $batchContent = @(
                            "@echo off", "chcp 65001 >nul", "SET ORIGINAL=%CD%", "set `"ACTUAL_SHOW_NAME=$($batchEscapedActualShowName -replace '[\r\n\t]', ' ')`"",
                            $pushdMaster, $callAuth, "popd", $clearLogFile, $cmd1, $cmd2
                        ) + $muxingMessage + @(
                            "REM --- MUX AUDIO AND RENAME ---", "setlocal enabledelayedexpansion", $pushdVideos
                        ) + $muxAndRenameLogic + @(
                            "popd", "endlocal", $moveVideos, "echo.", "echo --- Script finished. ---", $reportFailedFiles, "if not defined SKIP_PAUSE pause"
                        )
                        $batFile = $scriptOutputPath + "\" + $batFileName
                        [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                        Write-Host "Created script: " + $batFile
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
                $episodeOption = "--but -e " + $skipInput
                
                $cmd1 = $aniDLPath + ' --service "crunchy" --vstream ps5 --tsd --noaudio ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLangCode + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                $cmd2 = $aniDLPath + ' --service "crunchy" --astream android --novids --nosubs ' + $flag + ' ' + $seriesID + ' --chapters false ' + $episodeOption + ' --dubLang ' + $chosenDubLangCode + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                $pushdMaster = 'pushd "' + $masterPath + '"'
                $callAuth = 'call "' + $authScriptCurrent + '"'
                $pushdVideos = 'pushd "' + $masterPath + '\' + $videosSubDir + '"'
                $moveVideos = 'move "' + $masterPath + '\' + $videosSubDir + '\*.mkv" "%CD%" 2>nul'
                $batchContent = @(
                    "@echo off", "chcp 65001 >nul", "SET ORIGINAL=%CD%", "set `"ACTUAL_SHOW_NAME=$($batchEscapedActualShowName -replace '[\r\n\t]', ' ')`"",
                    $pushdMaster, $callAuth, "popd", $clearLogFile, $cmd1, $cmd2
                ) + $muxingMessage + @(
                    "REM --- MUX AUDIO AND RENAME ---", "setlocal enabledelayedexpansion", $pushdVideos
                ) + $muxAndRenameLogic + @(
                    "popd", "endlocal", $moveVideos, "echo.", "echo --- Script finished. ---", $reportFailedFiles, "if not defined SKIP_PAUSE pause"
                )
                $batFile = $scriptOutputPath + "\" + $batShowTitle + "_Season_" + $batSeason + "_all-but-" + $skipForFilename + ".bat"
                [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "Created script: " + $batFile
            }
        }
        $nextAction = Get-NextAction
        if ($nextAction -eq "NO") {
            break
        }
        if ($nextAction -eq "CHANGE_SERVICE") {
            return "CHANGE_SERVICE"
        }
    }
    return "EXIT"
}

$runScript = $true
while($runScript) {

    $chosenService = Get-SelectionFromListWithDefault "Choose a service" $services "Crunchyroll"
    $aniDLPath = "aniDL"

    if ($chosenService -eq "Hidive") {
        $authScriptCurrent = Join-Path -Path $masterPath -ChildPath "Auth_HDV.bat"
        Write-Host "Authenticating..." -ForegroundColor Green
        & cmd /c "$authScriptCurrent"
        $scriptOutputPath = Join-Path -Path $masterPath -ChildPath "Generated_Scripts"
        $serviceOption = "hidive"
    } else { # Crunchyroll
        $authScriptCurrent = Join-Path -Path $masterPath -ChildPath "Auth_CR.bat"
        Write-Host "Authenticating..." -ForegroundColor Green
        & cmd /c "$authScriptCurrent"
        $scriptOutputPath = Join-Path -Path $masterPath -ChildPath "Generated_Scripts"
        $serviceOption = "crunchy"
        
        # --- Ensure output directory exists ---
        if (!(Test-Path $scriptOutputPath)) { New-Item -ItemType Directory -Path $scriptOutputPath -Force | Out-Null }
        
        $useExperimental = Get-ExperimentalFeatureConsent
        
        if ($useExperimental -eq $true) {
            $experimentalResult = Generate-ExperimentalCrunchyrollScript -aniDLPath $aniDLPath -masterPath $masterPath -authScriptCurrent $authScriptCurrent -scriptOutputPath $scriptOutputPath
            if ($experimentalResult -eq "CHANGE_SERVICE") {
                continue
            } else {
                $runScript = $false
                continue
            }
        }
    }
    
    # --- Ensure output directory exists (for non-experimental mode) ---
    if (!(Test-Path $scriptOutputPath)) { New-Item -ItemType Directory -Path $scriptOutputPath -Force | Out-Null }

    $pushdLine = 'pushd "' + $masterPath + '"'
    $moveLine  = 'move "' + $masterPath + '\videos\*.mkv" "%CD%"'

    $searchLoopActive = $true
    while ($searchLoopActive) {
        Write-Host "Enter Anime Name or type New to check the latest series:" -NoNewline
        $animeName = Read-Host

        if ($serviceOption -eq "crunchy" -and $animeName -ieq "new") {
            $searchResults = & $aniDLPath --service $serviceOption --new
        }
        elseif ($serviceOption -eq "crunchy") {
            $searchResults = & $aniDLPath --service $serviceOption --search "$animeName"
        }
        else {
            $searchResults = & $aniDLPath --service $serviceOption --search "$animeName"
        }
        
        $foundSeries = Parse-Series $searchResults

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
        Write-DebugInfo -rawResults $searchResults -seriesArray $foundSeries

        Write-Host "---- Available Series ----"
        
        $startIndex = 0
        $displayLimit = 15
        $performNewSearch = $false

        while ($true) {
            $endIndex = [math]::Min($displayLimit, $foundSeries.Count)
            for ($i = $startIndex; $i -lt $endIndex; $i++) {
                $displayLine = "[$i] $($foundSeries[$i].Title) - Season $($foundSeries[$i].Season) ($($foundSeries[$i].Type))"
                if ($foundSeries[$i].EpisodeCount) { $displayLine += " - EPs: $($foundSeries[$i].EpisodeCount)" }
                if ($foundSeries[$i].SeriesID) { $displayLine += " [S:$($foundSeries[$i].SeriesID)]" }
                if ($foundSeries[$i].ZID -and -not $foundSeries[$i].SeriesID) { $displayLine += " [Z:$($foundSeries[$i].ZID)]" }
                Write-Host $displayLine
                if ($foundSeries[$i].Versions) { Write-Host "    - Versions: $($foundSeries[$i].Versions -join ', ')" }
                if ($foundSeries[$i].Subtitles) { Write-Host "    - Subtitles: $($foundSeries[$i].Subtitles -join ', ')" }
            }

            $seriesIndices = Read-Host "Enter the number(s) of the serie(s) or new search(n) (comma-separated),more search results(Enter):"
            
            # Pagination Trigger
            if ([string]::IsNullOrWhiteSpace($seriesIndices)) {
                if ($displayLimit -ge $foundSeries.Count) {
                    Write-Host "No more results to display." -ForegroundColor Yellow
                } else {
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
                $flag = "-s" # Fallback for Hidive
                $seriesID = $series.SeriesID
            }
            
            # --- Clean title and replace dots with underscores ---
            $origShowTitle = ($series.Title -replace '[\\/:*?"<>|]', '') -replace '\s+', ' '
            $batShowTitle = ($origShowTitle -replace '\s+', '_') -replace '\.', '_'

            if ($series.Season -match "^\d+$") {
                if ([int]$series.Season -lt 10) { $origSeason = "0" + [int]$series.Season }
                else { $origSeason = $series.Season }
            } else { 
                $origSeason = $series.Season 
            }
            $origEpisode = "1"
            
            if ($serviceOption -eq "hidive") {
                $availableDubLangs = @("ja-JP", "en-US", "spa-419", "pt-BR")
                $chosenDubLang = Get-SelectionFromListWithDefault "Choose a dub language to download:" $availableDubLangs "ja-JP"
                $chosenDefaultAudio = Get-SelectionFromListWithDefault "Choose a default Audio language:" $availableDubLangs "ja-JP"
                $availableSubs = @("en-US", "ja-JP", "spa-419", "pt-BR")
                $chosenSub = Get-SelectionFromListWithDefault "Choose the default subtitle for the script:" $availableSubs "en-US"
            }
            else { # --- Crunchyroll Classic Language Selection ---
                if ($series.Versions) {
                    $availableDubLangs = $series.Versions
                    $chosenDubLang = Get-SelectionFromListWithDefault "Choose a dub language to download:" $availableDubLangs "ja-JP"
                    $chosenDefaultAudio = Get-SelectionFromListWithDefault "Choose a default Audio language:" $availableDubLangs "ja-JP"
                }
                else {
                    Write-Host "--- Audio Language Selection ---" -ForegroundColor Yellow
                    Write-Host "Audio versions were not listed in search results. Please choose manually."
                    
                    $allowedLangNames = $languageDetails.Keys
                    $defaultLangName = ($allowedLangNames | Select-Object -First 1)
                    $prompt = "Choose a dub language to download [Default: $defaultLangName]"
                    
                    $chosenDubLang = 'ja-JP'
                    
                    while ($true) {
                        $userInput = Read-Host $prompt
                        if ([string]::IsNullOrWhiteSpace($userInput)) {
                            break
                        }
                        $matchedKey = $allowedLangNames | Where-Object { $_ -eq $userInput }
                        if ($matchedKey) {
                            $chosenDubLang = $languageDetails[$matchedKey].Code
                            break
                        }
                        Write-Host "Invalid selection. Please enter one of: $($allowedLangNames -join ', ')" -ForegroundColor Red
                    }
                    $chosenDefaultAudio = Get-SelectionFromListWithDefault "Choose a default Audio language:" @($chosenDubLang) $chosenDubLang
                }

                if ($series.Subtitles) {
                    $availableSubs = $series.Subtitles
                    $chosenSub = Get-SelectionFromListWithDefault "Choose the default subtitle for the script:" $availableSubs "en-US"
                } else { 
                    $chosenSub = "en-US" 
                }
            }
            
            $chosenVideoTitle = Get-VideoTitle
            
            if ($serviceOption -eq "hidive") {
                while ($true) {
                    $inputFontSize = Read-Host "Enter fontSize (Leave blank for default 48)"
                    if ([string]::IsNullOrWhiteSpace($inputFontSize)) {
                        $chosenFontSize = 48
                        break
                    }
                    if ($inputFontSize -match "^\d+$") {
                        $chosenFontSize = [int]$inputFontSize
                        break
                    }
                    Write-Host "Invalid input. Please enter a number or leave blank." -ForegroundColor Red
                }
            }
            
            $episodeSelection = $null
            while (-not $episodeSelection) {
                $input = Read-Host "Do you want to download all episodes or specific episodes? (all(a)/specific(s)/all-but-one(ab))"
                switch ($input.Trim().ToLower()) {
                    "all"           { $episodeSelection = "all" }
                    "a"             { $episodeSelection = "all" }
                    "specific"      { $episodeSelection = "specific" }
                    "s"             { $episodeSelection = "specific" }
                    "all-but-one"   { $episodeSelection = "all-but-one" }
                    "ab"            { $episodeSelection = "all-but-one" }
                    default { Write-Host "Invalid selection. Please enter all(a), specific(s), or all-but-one(ab)." -ForegroundColor Red }
                }
            }
            
            if ($episodeSelection -eq "all") {
                $scriptType = "single"
            } elseif ($episodeSelection -eq "specific") {
                $scriptType = Get-SingleMultiple "Do you want a single script or multiple scripts? (Single(S)/Multiple(M))"
            }
            
            $inputShowTitle = Read-Host "Enter new show title for filename (leave blank for default [$origShowTitle])"
            if ($inputShowTitle -ne "") {
                $cleaned = $inputShowTitle -replace '[\\/:*?"<>|]', ""
                $cmdShowTitle = $cleaned.Trim()
                $cmdShowTitle = $cmdShowTitle -replace "[\r\n]+", " "
                $batShowTitle = ($cleaned.Trim() -replace ' ', '_') -replace '\.', '_'
            } else {
                $cmdShowTitle = $origShowTitle
                $cmdShowTitle = $cmdShowTitle -replace "[\r\n]+", " "
                # Ensure original title also has dots replaced for the filename
                $batShowTitle = ($origShowTitle -replace '\s+', '_') -replace '\.', '_'
            }
            
            $inputSeason = Read-Host "Enter new season value (leave blank for default [$origSeason])"
            if ($inputSeason -ne "") {
                if ($inputSeason -match "^\d+$") { 
                    $cmdSeason = Normalize-Number $inputSeason 
                } else { 
                    $cmdSeason = $inputSeason 
                }
                $batSeason = $cmdSeason
            } else {
                $cmdSeason = Normalize-Number $origSeason
                $batSeason = $cmdSeason
            }
            
            $cmdShowTitle = $cmdShowTitle -replace '[\r\n\t]', ' '
            $cmdShowTitle = $cmdShowTitle -replace '"', ''
            $cmdShowTitle = $cmdShowTitle.Trim()
            
            if ($episodeSelection -eq "all") {
                $episodeOption = "--all"
                if ($serviceOption -eq "hidive") {
                    $cmd = $aniDLPath + ' --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --originalFontSize false --fontSize ' + $chosenFontSize + ' --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                    $pushdMaster = 'pushd "' + $masterPath + '"'
                    $callAuth = 'call "' + $authScriptCurrent + '"'
                    $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%CD%"'
                    $batchContent = @(
                        "@echo off", "chcp 65001 >nul", "SET ORIGINAL=%CD%",
                        $pushdMaster, $callAuth, "popd", 
                        $cmd, 
                        $moveVideos, 
                        "if not defined SKIP_PAUSE pause"
                    )
                } else {
                    $cmd = $aniDLPath + ' --service "' + $serviceOption + '" ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --tsd --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                    $pushdMaster = 'pushd "' + $masterPath + '"'
                    $callAuth = 'call "' + $authScriptCurrent + '"'
                    $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%CD%"'
                    $batchContent = @(
                        "@echo off", "chcp 65001 >nul", $pushdMaster, $callAuth, "popd",
                        $cmd, $moveVideos, "if not defined SKIP_PAUSE pause"
                    )
                }
                $batFile = $scriptOutputPath + "\" + $batShowTitle + "_Season_" + $batSeason + ".bat"
                [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "Created script: " + $batFile
            }
            elseif ($episodeSelection -eq "specific") {
                if ($scriptType -eq "single") {
                    while ($true) {
                        $episodeInput = Read-Host "Enter episode numbers or range for the script(s) -e (e.g., 1-3, 1,2,3)"
                        if ($episodeInput -match "^\s*(\d+)\s*-\s*(\d+)\s*$" -or $episodeInput -match "^\s*\d+(\s*,\s*\d+)*\s*$") { break }
                        else { Write-Host "Invalid input. Please enter a valid range or comma-separated list." }
                    }
                    $episodeOption = "-e " + $episodeInput
                    if ($serviceOption -eq "hidive") {
                        $cmd = $aniDLPath + ' --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --originalFontSize false --fontSize ' + $chosenFontSize + ' --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                        $pushdMaster = 'pushd "' + $masterPath + '"'
                        $callAuth = 'call "' + $authScriptCurrent + '"'
                        $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%CD%"'
                        $batchContent = @(
                            "@echo off", "chcp 65001 >nul", "SET ORIGINAL=%CD%", $pushdMaster, $callAuth, "popd",
                            $cmd, 
                            $moveVideos, 
                            "if not defined SKIP_PAUSE pause"
                        )
                    }
                    else {
                        $pushdMaster = 'pushd "' + $masterPath + '"'
                        $callAuth = 'call "' + $authScriptCurrent + '"'
                        $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%CD%"'
                        $cmd = $aniDLPath + ' --service "crunchy" ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --tsd --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                        $batchContent = @(
                            "@echo off", "chcp 65001 >nul", $pushdMaster, $callAuth, "popd",
                            $cmd, $moveVideos, "if not defined SKIP_PAUSE pause"
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
                            $newCounter = Read-Host "Input the new episode start for the scripts (eg: 01, 13, 25)"
                            if ($newCounter -match "^\d+$") {
                                $counter = [int]$newCounter
                                $useModified = $true
                            } else {
                                Write-Host "Invalid number, defaulting to 1."
                                $counter = 1
                                $useModified = $true
                            }
                        } else {
                            $useModified = $false
                        }
                    } else {
                        $useModified = $false
                    }
                    foreach ($ep in $episodesArray) {
                        if ($useModified) {
                            $epPadded = ([string]::Format("{0:D2}", $counter))
                            $currentEpTag = $epPadded
                            $counter++
                        } else {
                            $epPadded = ([string]::Format("{0:D2}", $ep))
                            $currentEpTag = $epPadded
                        }
                        $batFileName = $batShowTitle + "_Season_" + $batSeason + "_E" + $currentEpTag + ".bat"
                        $episodeOption = "-e " + $ep
                        if ($serviceOption -eq "hidive") {
                            $cmd = $aniDLPath + ' --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --originalFontSize false --fontSize ' + $chosenFontSize + ' --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E' + $currentEpTag + ' [${height}p]"'
                            $pushdMaster = 'pushd "' + $masterPath + '"'
                            $callAuth = 'call "' + $authScriptCurrent + '"'
                            $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%CD%"'
                            $batchContent = @(
                                "@echo off", "chcp 65001 >nul", "SET ORIGINAL=%CD%",
                                $pushdMaster, $callAuth, "popd", 
                                $cmd, 
                                $moveVideos, 
                                "if not defined SKIP_PAUSE pause"
                            )
                        } else {
                            $pushdMaster = 'pushd "' + $masterPath + '"'
                            $callAuth = 'call "' + $authScriptCurrent + '"'
                            $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%CD%"'
                            $cmd = $aniDLPath + ' --service "crunchy" ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --tsd --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E' + $currentEpTag + ' [${height}p]"'
                            $batchContent = @(
                                "@echo off", "chcp 65001 >nul", $pushdMaster, $callAuth, "popd",
                                $cmd, $moveVideos, "if not defined SKIP_PAUSE pause"
                            )
                        }
                        $batFile = $scriptOutputPath + "\" + $batFileName
                        [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                        Write-Host "Created script: " + $batFile
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
                    $cmd = $aniDLPath + ' --service "' + $serviceOption + '" --srz ' + $seriesID + ' --but -e ' + $skipInput + ' --dubLang ' + $chosenDubLang + ' --originalFontSize false --fontSize ' + $chosenFontSize + ' --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '"'
                    $pushdMaster = 'pushd "' + $masterPath + '"'
                    $callAuth = 'call "' + $authScriptCurrent + '"'
                    $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%CD%"'
                    $batchContent = @(
                        "chcp 65001 >nul", "@echo off", "SET ORIGINAL=%CD%",
                        $pushdMaster, $callAuth, "popd", 
                        $cmd, 
                        $moveVideos, 
                        "if not defined SKIP_PAUSE pause"
                    )
                } else {
                    $pushdMaster = 'pushd "' + $masterPath + '"'
                    $callAuth = 'call "' + $authScriptCurrent + '"'
                    $cmd = $aniDLPath + ' --service "crunchy" ' + $flag + ' ' + $seriesID + ' --but -e ' + $skipInput + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --tsd --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                    $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%CD%"'
                    $batchContent = @(
                        "@echo off", "chcp 65001 >nul", $pushdMaster, $callAuth, "popd",
                        $cmd, $moveVideos, "if not defined SKIP_PAUSE pause"
                    )
                }
                $batFile = $scriptOutputPath + "\" + $batShowTitle + "_Season_" + $batSeason + "_all-but-" + $skipForFilename + ".bat"
                [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "Created script: " + $batFile
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