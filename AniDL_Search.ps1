Write-Host "Welcome to DKB Search and Script Generator"

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

# --- Helper: Experimental Feature Prompt ---
function Get-ExperimentalFeatureConsent {
    while ($true) {
        $input = Read-Host 'Wanna use the experimental feature? Y/N'
        switch ($input.ToLower()) {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
            default { Write-Host "Please enter Y/N or Yes/No." }
        }
    }
}

# --- Parse-Series Function ---
function Parse-Series {
    param($searchResults)
    $foundSeries = @()
    # Allowed languages list.
    $allowedLangs = @("en-US", "en-IN", "es-419", "es-ES", "fr-FR", "pt-BR", "pt-PT", "ar-ME", "ar-SA", "it-IT", "de-DE", "ru-RU", "tr-TR", "hi-IN", "ca-ES", "pl-PL", "th-TH", "ta-IN", "ms-MY", "vi-VN", "id-ID", "te-IN", "zh-CN", "zh-HK", "zh-TW", "ko-KR", "ja-JP")
    foreach ($line in $searchResults -split "`r?`n") {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -match "^(Found movie lists:|Found episodes:|Newly added:)") { continue }
        if ($trimmedLine -match "^(Top results:|Found series:|Total results:)") { continue }
        # HIDIVE series pattern.
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
        # Crunchyroll pattern using Z: prefix.
        if ($serviceOption -eq "crunchy" -and $trimmedLine -match "^\[Z:([^\|\]]+)(?:\|SRZ\.[^\]]+)?\]\s+(.+?)\s+\(Seasons:\s*(\d+)(?:,\s*EPs:\s*(\d+))?\)\s+\[(.*?)\]") {
            $zMatches = [regex]::Matches($trimmedLine, "^\[Z:([^\|\]]+)(?:\|SRZ\.[^\]]+)?\]\s+(.+?)\s+\(Seasons:\s*(\d+)(?:,\s*EPs:\s*(\d+))?\)\s+\[(.*?)\]")
            foreach ($m in $zMatches) {
                $obj = [PSCustomObject]@{
                    Title        = $m.Groups[2].Value.Trim()
                    Season       = $m.Groups[3].Value.Trim()
                    Type         = $m.Groups[5].Value.Trim()
                    EpisodeCount = if ($m.Groups[4].Success) { $m.Groups[4].Value.Trim() } else { $null }
                    SeriesID     = $null
                    ZID          = $m.Groups[1].Value.Trim()
                    Versions     = $null
                    Subtitles    = $null
                }
                if (-not ($foundSeries | Where-Object { $_.Title -eq $obj.Title -and $_.Season -eq $obj.Season -and $_.ZID -eq $obj.ZID })) {
                    $foundSeries += $obj
                }
            }
        }
        # Crunchyroll pattern using S: prefix.
        elseif ($trimmedLine -match "^\[S:([^\]]+)\]\s+(.+?)\s+\(Season:? (\d+)\)\s+\[(.*?)\]") {
            $sMatches = [regex]::Matches($trimmedLine, "^\[S:([^\]]+)\]\s+(.+?)\s+\(Season:? (\d+)\)\s+\[(.*?)\]")
            foreach ($m in $sMatches) {
                $obj = [PSCustomObject]@{
                    Title        = $m.Groups[2].Value.Trim()
                    Season       = $m.Groups[3].Value.Trim()
                    Type         = $m.Groups[4].Value.Trim()
                    EpisodeCount = $null
                    SeriesID     = $m.Groups[1].Value.Trim()
                    ZID          = $null
                    Versions     = $null
                    Subtitles    = $null
                }
                if (-not ($foundSeries | Where-Object { $_.Title -eq $obj.Title -and $_.Season -eq $obj.Season -and $_.SeriesID -eq $obj.SeriesID })) {
                    $foundSeries += $obj
                }
            }
        }
        # Process Versions with allowed language filtering.
        elseif ($trimmedLine -match "^- Versions:\s*(.+)") {
            $rawVersions = $matches[1].Trim()
            $parsedVersions = $rawVersions -split "," | ForEach-Object { $_.Trim() } | Where-Object { $allowedLangs -contains $_ }
            if ($foundSeries.Count -gt 0) { $foundSeries[-1].Versions = $parsedVersions }
        }
        # Process Subtitles with allowed language filtering.
        elseif ($trimmedLine -match "^- Subtitles:\s*(.+)") {
            $rawSubs = $matches[1].Trim()
            $parsedSubs = $rawSubs -split "," | ForEach-Object { $_.Trim() } | Where-Object { $allowedLangs -contains $_ }
            if ($foundSeries.Count -gt 0) {
                if (-not $foundSeries[-1].PSObject.Properties["Subtitles"]) {
                    $foundSeries[-1] | Add-Member -MemberType NoteProperty -Name Subtitles -Value $parsedSubs
                }
                else { $foundSeries[-1].Subtitles = $parsedSubs }
            }
        }
    }
    return $foundSeries
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
        # Ask for anime name
        $animeName = Read-Host "Enter Anime Name or type New to check the latest series (Experimental):"
        $serviceOption = "crunchy"
        $extraParam = @('--crapi','web')
        if ($animeName -ieq "new") {
            $searchResults = & $aniDLPath --service $serviceOption @extraParam --new
        } else {
            $searchResults = & $aniDLPath --service $serviceOption @extraParam --search "$animeName"
        }
        if (-not $searchResults) {
            Write-Host "No results found. Try again."
            continue
        }
        $foundSeries = Parse-Series $searchResults
        $foundSeries = @($foundSeries)
        Write-DebugInfo -rawResults $searchResults -seriesArray $foundSeries
        if (-not $foundSeries) {
            Write-Host "No anime found. Exiting experimental."
            return
        }
        Write-Host "---- Available Series (Experimental) ----"
        for ($i = 0; $i -lt $foundSeries.Count; $i++) {
            $displayLine = "[$i] $($foundSeries[$i].Title) - Season $($foundSeries[$i].Season) ($($foundSeries[$i].Type))"
            if ($foundSeries[$i].EpisodeCount) { $displayLine += " - EPs: $($foundSeries[$i].EpisodeCount)" }
            if ($foundSeries[$i].SeriesID) { $displayLine += " [S:$($foundSeries[$i].SeriesID)]" }
            if ($foundSeries[$i].ZID) { $displayLine += " [Z:$($foundSeries[$i].ZID)]" }
            Write-Host $displayLine
            if ($foundSeries[$i].Versions) { Write-Host "    - Versions: $($foundSeries[$i].Versions -join ', ')" }
            if ($foundSeries[$i].Subtitles) { Write-Host "    - Subtitles: $($foundSeries[$i].Subtitles -join ', ')" }
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
            if ($serviceOption -eq "crunchy" -and -not [string]::IsNullOrWhiteSpace($series.ZID)) {
                $flag = "--srz"
                $seriesID = $series.ZID
            } else {
                $flag = "-s"
                $seriesID = $series.SeriesID
            }
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
                } else { 
                    $chosenSub = "en-US" 
                }
            }
            # --- End Language Prompts ---
            $chosenVideoTitle = Get-VideoTitle
            while ($true) {
                $episodeSelection = Read-Host "Do you want to download all episodes or specific episodes? (all/specific/all-but-one)"
                if ($episodeSelection -match "^(all|specific|all-but-one)$") { break }
                else { Write-Host "Please choose from: all, specific, or all-but-one." }
            }
            
            if ($episodeSelection -eq "all") {
                $scriptType = "single"
            } elseif ($episodeSelection -eq "specific") {
                $scriptType = Get-SingleMultiple "Do you want a single script or multiple scripts? (Single(S)/Multiple(M))"
            }
            
            $inputShowTitle = Read-Host "Enter new show title for filename (leave blank for default [$($series.Title -replace '[\\/:*?"<>|]', '')])"
            if ($inputShowTitle -ne "") {
                $cleaned = $inputShowTitle -replace '[\\/:*?"<>|]', ""
                $cmdShowTitle = $cleaned.Trim()
                $cmdShowTitle = $cmdShowTitle -replace "[\r\n]+", " "
                $batShowTitle = $cleaned.Trim() -replace ' ', '_'
            } else {
                $cmdShowTitle = $series.Title -replace '[\\/:*?"<>|]', ''
                $cmdShowTitle = $cmdShowTitle -replace "[\r\n]+", " "
                $batShowTitle = $series.Title -replace '[\\/:*?"<>|]', '' -replace '\s+', '_'
            }
            
            $inputSeason = Read-Host "Enter new season value (leave blank for default [$($series.Season)])"
            if ($inputSeason -ne "") {
                if ($inputSeason -match "^\d+$") { 
                    $cmdSeason = Normalize-Number $inputSeason 
                } else { 
                    $cmdSeason = $inputSeason 
                }
                $batSeason = $cmdSeason
            } else {
                $cmdSeason = Normalize-Number $series.Season
                $batSeason = $cmdSeason
            }
            
            if ($episodeSelection -eq "all") {
                # For 'all' episodes, pass only --all to the generated script.
                $episodeOption = "--all"
                $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" ' + $extraParam + ' ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                $pushdMaster = 'pushd "' + $masterPath + '"'
                $callAuth = 'call "' + $authScriptCurrent + '"'
                $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
                $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%ORIGINAL%"'
                $setBase = '    set "BASE=%%~nV"'
                $setAudio = '    set "AUDIO=!BASE!.Japanese.audio.m4s"'
                $batchContent = @(
                    "@echo off",
                    "chcp 65001",
                    $pushdMaster,
                    $callAuth,
                    "set `"ACTUAL_SHOW_NAME=$($cmdShowTitle -replace '[\r\n\t]', ' ')`"",
                    $cmd,
                    "popd",
                    $moveVideos,
                    "if not defined SKIP_PAUSE pause"
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
                    if ($serviceOption -eq "hidive") {
                        $cmd1 = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                        $cmd2 = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                        $pushdMaster = 'pushd "' + $masterPath + '"'
                        $callAuth = 'call "' + $authScriptCurrent + '"'
                        $pushdVideos = 'pushd "' + $masterPath + '\videos"'
                        $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
                        $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%ORIGINAL%"'
                        $setBase = '    set "BASE=%%~nV"'
                        $setAudio = '    set "AUDIO=!BASE!.Japanese.audio.m4s"'
                        $batchContent = @(
                            "@echo off",
                            "chcp 65001",
                            "@echo off",
                            "SET ORIGINAL=%CD%",
                            $pushdMaster,
                            $callAuth,
                            "set `"ACTUAL_SHOW_NAME=$($cmdShowTitle -replace '[\r\n\t]', ' ')`"",
                            $cmd1,
                            $cmd2,
                            $pushdVideos,
                            "",
                            $callRename,
                            "popd",
                            $moveVideos,
                            "if not defined SKIP_PAUSE pause"
                        )
                    }
                    else {
                        $cmd1 = '"' + $aniDLPath + '" --service "crunchy" --crapi web --cs ps5 --noaudio ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                        $cmd2 = '"' + $aniDLPath + '" --service "crunchy" --crapi web --cs android --novids --nosubs ' + $flag + ' ' + $seriesID + ' --chapters false ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                        $pushdMaster = 'pushd "' + $masterPath + '"'
                        $callAuth = 'call "' + $authScriptCurrent + '"'
                        $pushdVideos = 'pushd "' + $masterPath + '\videos"'
                        $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
                        $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%ORIGINAL%"'
                        $setBase = '    set "BASE=%%~nV"'
                        $setAudio = '    set "AUDIO=!BASE!.Japanese.audio.m4s"'
                        $batchContent = @(
                            "@echo off",
                            "chcp 65001 >nul",
                            $pushdMaster,
                            $callAuth,
                            "set `"ACTUAL_SHOW_NAME=$($cmdShowTitle -replace '[\r\n\t]', ' ')`"",
                            $cmd1,
                            $cmd2,
                            "REM -MUX AUDIO INTO VIDEO-",
                            "setlocal enabledelayedexpansion",
                            "@echo on",
                            $pushdVideos,
                            "",
                            'dir "Anime_Show - S*.mkv"',
                            'for %%V in ("Anime_Show - S*.mkv") do (',
                            '    echo Processing: %%V',
                            '    set "BASE=%%~nV"',
                            '    set "AUDIO=!BASE!.Japanese.audio.m4s"',
                            '    mkvmerge -o "!BASE!_muxed.mkv" ^',
                            '      "%%V" ^',
                            '      --language 0:ja-JP --track-name 0:"Japanese" ^',
                            '      "!AUDIO!"',
                            '    if exist "!BASE!_muxed.mkv" (',
                            '        del "%%V"',
                            '        ren "!BASE!_muxed.mkv" "%%~nxV"',
                            '        del "!AUDIO!"',
                            '    )',
                            ')',
                            '',
                            'rem -- Rename Anime_Show to actual show name',
                            'dir "Anime_Show - S*.mkv"',
                            'for %%F in ("Anime_Show - S*.mkv") do (',
                            '    set "NEWNAME=%%~nxF"',
                            '    set "NEWNAME=!NEWNAME:Anime_Show=%ACTUAL_SHOW_NAME%!"',
                            '    echo ren "%%~nxF" "!NEWNAME!"',
                            '    ren "%%~nxF" "!NEWNAME!"',
                            '    echo Rename errorlevel: !errorlevel!',
                            ')',
                            "popd",
                            "endlocal",
                            "",
                            "popd",
                            $moveVideos,
                            "if not defined SKIP_PAUSE pause"
                        )
                    }
                    $batFile = $scriptOutputPath + "\" + $batShowTitle + "_Season_" + $batSeason + ".bat"
                    [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                    Write-Host "Created script: " + $batFile
                }
                elseif ($scriptType -eq "multiple") {
                    # Get the episode numbers.
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
                    # If the input is a range, ask for filename modification.
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
                        $actualShowName = $cmdShowTitle
                        $sanitizedShowName = ($cmdShowTitle -replace '[^A-Za-z0-9]', '_')
                        $dynamicFileNameArg = '--fileName "Anime_Show - S' + $cmdSeason + 'E' + $currentEpTag + ' [${height}p]"'
                        $batFileName = $batShowTitle + "_Season_" + $batSeason + "_E" + $currentEpTag + ".bat"
                        $episodeOption = "-e " + $ep
                        if ($serviceOption -eq "hidive") {
                            $cmd1 = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                            $cmd2 = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                            $pushdMaster = 'pushd "' + $masterPath + '"'
                            $callAuth = 'call "' + $authScriptCurrent + '"'
                            $pushdVideos = 'pushd "' + $masterPath + '\videos"'
                            $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
                            $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%ORIGINAL%"'
                            $setBase = '    set "BASE=%%~nV"'
                            $setAudio = '    set "AUDIO=!BASE!.Japanese.audio.m4s"'
                            $batchContent = @(
                                "@echo off",
                                "chcp 65001",
                                "@echo off",
                                "SET ORIGINAL=%CD%",
                                $pushdMaster,
                                $callAuth,
                                "set `"ACTUAL_SHOW_NAME=$($cmdShowTitle -replace '[\r\n\t]', ' ')`"",
                                $cmd1,
                                $cmd2,
                                $pushdVideos,
                                "",
                                $callRename,
                                "popd",
                                $moveVideos,
                                "if not defined SKIP_PAUSE pause"
                            )
                        } else {
                            $cmd1 = '"' + $aniDLPath + '" --service "crunchy" --crapi web --cs ps5 --noaudio ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                            $cmd2 = '"' + $aniDLPath + '" --service "crunchy" --crapi web --cs android --novids --nosubs ' + $flag + ' ' + $seriesID + ' --chapters false ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                            $pushdMaster = 'pushd "' + $masterPath + '"'
                            $callAuth = 'call "' + $authScriptCurrent + '"'
                            $pushdVideos = 'pushd "' + $masterPath + '\videos"'
                            $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
                            $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%ORIGINAL%"'
                            $setBase = '    set "BASE=%%~nV"'
                            $setAudio = '    set "AUDIO=!BASE!.Japanese.audio.m4s"'
                            $batchContent = @(
                                "@echo off",
                                "chcp 65001 >nul",
                                $pushdMaster,
                                $callAuth,
                                "set `"ACTUAL_SHOW_NAME=$($cmdShowTitle -replace '[\r\n\t]', ' ')`"",
                                $cmd1,
                                $cmd2,
                                "REM -MUX AUDIO INTO VIDEO-",
                                "setlocal enabledelayedexpansion",
                                "@echo on",
                                $pushdVideos,
                                "",
                                'dir "Anime_Show - S*.mkv"',
                                'for %%V in ("Anime_Show - S*.mkv") do (',
                                '    echo Processing: %%V',
                                '    set "BASE=%%~nV"',
                                '    set "AUDIO=!BASE!.Japanese.audio.m4s"',
                                '    mkvmerge -o "!BASE!_muxed.mkv" ^',
                                '      "%%V" ^',
                                '      --language 0:ja-JP --track-name 0:"Japanese" ^',
                                '      "!AUDIO!"',
                                '    if exist "!BASE!_muxed.mkv" (',
                                '        del "%%V"',
                                '        ren "!BASE!_muxed.mkv" "%%~nxV"',
                                '        del "!AUDIO!"',
                                '    )',
                                ')',
                                '',
                                'rem -- Rename Anime_Show to actual show name',
                                'dir "Anime_Show - S*.mkv"',
                                'for %%F in ("Anime_Show - S*.mkv") do (',
                                '    set "NEWNAME=%%~nxF"',
                                '    set "NEWNAME=!NEWNAME:Anime_Show=%ACTUAL_SHOW_NAME%!"',
                                '    echo ren "%%~nxF" "!NEWNAME!"',
                                '    ren "%%~nxF" "!NEWNAME!"',
                                '    echo Rename errorlevel: !errorlevel!',
                                ')',
                                "popd",
                                "endlocal",
                                "",
                                "popd",
                                $moveVideos,
                                "if not defined SKIP_PAUSE pause"
                            )
                        }
                        $batFile = $scriptOutputPath + "\" + $batFileName
                        [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                        Write-Host "Created script: " + $batFile
                    }
                }
            }
        }
        if (-not (Get-YesNo "Do you want to search for another anime? (yes/no)")) { break }
    }
}
# --- End Experimental Crunchyroll Script Generator ---

# --- Service & Master Path Setup ---
$chosenService = Get-SelectionFromListWithDefault "Choose a service" $services "Crunchyroll"
if ($chosenService -eq "Hidive") {
    $masterPath = "REPLACE_WITH_YOUR_HIDIVE_PATH".Trim()
    $authScriptCurrent = "$masterPath\Auth_HDV.bat"
    $serviceOption = "hidive"
    $extraParam = ""
} else {
    $masterPath = "REPLACE_WITH_YOUR_CRUNCHY_PATH".Trim()
    $serviceOption = "crunchy"
    $authScriptCurrent = "$masterPath\Auth_CR.bat"
    $aniDLPath = "$masterPath\aniDL.exe"
    $scriptOutputPath = "$masterPath\Generated_Scripts"
    if (!(Test-Path $scriptOutputPath)) { New-Item -ItemType Directory -Path $scriptOutputPath | Out-Null }
    # --- NEW: Experimental prompt for Crunchyroll ---
    if (Get-ExperimentalFeatureConsent) {
        Generate-ExperimentalCrunchyrollScript -aniDLPath $aniDLPath -masterPath $masterPath -authScriptCurrent $authScriptCurrent -scriptOutputPath $scriptOutputPath
        return
    }
    $extraParam = @('--crapi','web')
}
$masterPath = $masterPath.Trim() -replace "(`r`n|`n|`r)", ""
$pushdLine = 'pushd "$masterPath"'
$moveLine  = 'move "' + $masterPath + '\videos\*.mkv" "%CD%"'

# --- Main Loop ---
while ($true) {
    Write-Host "Enter Anime Name or type New to check the latest series:" -NoNewline
    $animeName = Read-Host

    if ($serviceOption -eq "crunchy" -and $animeName -ieq "new") {
        $searchResults = & $aniDLPath --service $serviceOption $extraParam --new
    }
    elseif ($serviceOption -eq "crunchy") {
        $searchResults = & $aniDLPath --service $serviceOption $extraParam --search "$animeName"
    }
    else {
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
        if ($foundSeries[$i].ZID) { $displayLine += " [Z:$($foundSeries[$i].ZID)]" }
        Write-Host $displayLine
        if ($foundSeries[$i].Versions) { Write-Host "    - Versions: $($foundSeries[$i].Versions -join ', ')" }
        if ($foundSeries[$i].Subtitles) { Write-Host "    - Subtitles: $($foundSeries[$i].Subtitles -join ', ')" }
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
        if ($serviceOption -eq "crunchy" -and -not [string]::IsNullOrWhiteSpace($series.ZID)) {
            $flag = "--srz"
            $seriesID = $series.ZID
        } else {
            $flag = "-s"
            $seriesID = $series.SeriesID
        }
        
        $origShowTitle = ($series.Title -replace '[\\/:*?"<>|]', '') -replace '\s+', ' '
        if ($series.Season -match "^\d+$") {
            if ([int]$series.Season -lt 10) { $origSeason = "0" + [int]$series.Season }
            else { $origSeason = $series.Season }
        } else { 
            $origSeason = $series.Season 
        }
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
            } else { 
                $chosenSub = "en-US" 
            }
        }
        # --- End Language Prompts ---
        
        $chosenVideoTitle = Get-VideoTitle
        
        while ($true) {
            $episodeSelection = Read-Host "Do you want to download all episodes or specific episodes? (all/specific/all-but-one)"
            if ($episodeSelection -match "^(all|specific|all-but-one)$") { break }
            else { Write-Host "Please choose from: all, specific, or all-but-one." }
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
            $batShowTitle = $cleaned.Trim() -replace ' ', '_'
        } else {
            $cmdShowTitle = $origShowTitle
            $cmdShowTitle = $cmdShowTitle -replace "[\r\n]+", " "
            $batShowTitle = $origShowTitle -replace '\s+', '_'
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
        
        $masterPath = $masterPath.Trim() -replace "(`r`n|`n|`r)", ""
        $cmdShowTitle = $cmdShowTitle -replace '[\r\n\t]', ' '
        $cmdShowTitle = $cmdShowTitle -replace '"', ''
        $cmdShowTitle = $cmdShowTitle.Trim()
        
        if ($episodeSelection -eq "all") {
            # For 'all' episodes, pass only --all to the generated script.
            $episodeOption = "--all"
            $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" ' + $extraParam + ' ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
            $pushdMaster = 'pushd "' + $masterPath + '"'
            $callAuth = 'call "' + $authScriptCurrent + '"'
            $pushdVideos = 'pushd "' + $masterPath + '\videos"'
            $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
            $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%ORIGINAL%"'
            $setBase = '    set "BASE=%%~nV"'
            $setAudio = '    set "AUDIO=!BASE!.Japanese.audio.m4s"'
            $batchContent = @(
                "@echo off",
                "chcp 65001",
                $pushdMaster,
                $callAuth,
                "set `"ACTUAL_SHOW_NAME=$($cmdShowTitle -replace '[\r\n\t]', ' ')`"",
                $cmd,
                "popd",
                $moveVideos,
                "if not defined SKIP_PAUSE pause"
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
                if ($serviceOption -eq "hidive") {
                    $cmd1 = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                    $cmd2 = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                    $pushdMaster = 'pushd "' + $masterPath + '"'
                    $callAuth = 'call "' + $authScriptCurrent + '"'
                    $pushdVideos = 'pushd "' + $masterPath + '\videos"'
                    $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
                    $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%ORIGINAL%"'
                    $setBase = '    set "BASE=%%~nV"'
                    $setAudio = '    set "AUDIO=!BASE!.Japanese.audio.m4s"'
                    $batchContent = @(
                        "@echo off",
                        "chcp 65001",
                        "@echo off",
                        "SET ORIGINAL=%CD%",
                        $pushdMaster,
                        $callAuth,
                        "set `"ACTUAL_SHOW_NAME=$($cmdShowTitle -replace '[\r\n\t]', ' ')`"",
                        $cmd1,
                        $cmd2,
                        $pushdVideos,
                        "",
                        $callRename,
                        "popd",
                        $moveVideos,
                        "if not defined SKIP_PAUSE pause"
                    )
                }
                else {
                    $cmd1 = '"' + $aniDLPath + '" --service "crunchy" --crapi web --cs ps5 --noaudio ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                    $cmd2 = '"' + $aniDLPath + '" --service "crunchy" --crapi web --cs android --novids --nosubs ' + $flag + ' ' + $seriesID + ' --chapters false ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" --fileName "' + $cmdShowTitle + ' - S' + $cmdSeason + 'E${episode} [${height}p]"'
                    $pushdMaster = 'pushd "' + $masterPath + '"'
                    $callAuth = 'call "' + $authScriptCurrent + '"'
                    $pushdVideos = 'pushd "' + $masterPath + '\videos"'
                    $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
                    $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%ORIGINAL%"'
                    $setBase = '    set "BASE=%%~nV"'
                    $setAudio = '    set "AUDIO=!BASE!.Japanese.audio.m4s"'
                    $batchContent = @(
                        "@echo off",
                        "chcp 65001 >nul",
                        $pushdMaster,
                        $callAuth,
                        "set `"ACTUAL_SHOW_NAME=$($cmdShowTitle -replace '[\r\n\t]', ' ')`"",
                        $cmd1,
                        $cmd2,
                        "REM -MUX AUDIO INTO VIDEO-",
                        "setlocal enabledelayedexpansion",
                        "@echo on",
                        $pushdVideos,
                        "",
                        'dir "Anime_Show - S*.mkv"',
                        'for %%V in ("Anime_Show - S*.mkv") do (',
                        '    echo Processing: %%V',
                        '    set "BASE=%%~nV"',
                        '    set "AUDIO=!BASE!.Japanese.audio.m4s"',
                        '    mkvmerge -o "!BASE!_muxed.mkv" ^',
                        '      "%%V" ^',
                        '      --language 0:ja-JP --track-name 0:"Japanese" ^',
                        '      "!AUDIO!"',
                        '    if exist "!BASE!_muxed.mkv" (',
                        '        del "%%V"',
                        '        ren "!BASE!_muxed.mkv" "%%~nxV"',
                        '        del "!AUDIO!"',
                        '    )',
                        ')',
                        '',
                        'rem -- Rename Anime_Show to actual show name',
                        'dir "Anime_Show - S*.mkv"',
                        'for %%F in ("Anime_Show - S*.mkv") do (',
                        '    set "NEWNAME=%%~nxF"',
                        '    set "NEWNAME=!NEWNAME:Anime_Show=%ACTUAL_SHOW_NAME%!"',
                        '    echo ren "%%~nxF" "!NEWNAME!"',
                        '    ren "%%~nxF" "!NEWNAME!"',
                        '    echo Rename errorlevel: !errorlevel!',
                        ')',
                        "popd",
                        "endlocal",
                        "",
                        "popd",
                        $moveVideos,
                        "if not defined SKIP_PAUSE pause"
                    )
                }
                $batFile = $scriptOutputPath + "\" + $batShowTitle + "_Season_" + $batSeason + ".bat"
                [System.IO.File]::WriteAllLines($batFile, $batchContent, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "Created script: " + $batFile
            }
            elseif ($scriptType -eq "multiple") {
                # Get the episode numbers.
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
                # If the input is a range, ask for filename modification.
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
                    $actualShowName = $cmdShowTitle
                    $sanitizedShowName = ($cmdShowTitle -replace '[^A-Za-z0-9]', '_')
                    $dynamicFileNameArg = '--fileName "Anime_Show - S' + $cmdSeason + 'E' + $currentEpTag + ' [${height}p]"'
                    $batFileName = $batShowTitle + "_Season_" + $batSeason + "_E" + $currentEpTag + ".bat"
                    $episodeOption = "-e " + $ep
                    if ($serviceOption -eq "hidive") {
                        $cmd1 = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                        $cmd2 = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                        $pushdMaster = 'pushd "' + $masterPath + '"'
                        $callAuth = 'call "' + $authScriptCurrent + '"'
                        $pushdVideos = 'pushd "' + $masterPath + '\videos"'
                        $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
                        $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%ORIGINAL%"'
                        $setBase = '    set "BASE=%%~nV"'
                        $setAudio = '    set "AUDIO=!BASE!.Japanese.audio.m4s"'
                        $batchContent = @(
                            "@echo off",
                            "chcp 65001",
                            "@echo off",
                            "SET ORIGINAL=%CD%",
                            $pushdMaster,
                            $callAuth,
                            "set `"ACTUAL_SHOW_NAME=$($cmdShowTitle -replace '[\r\n\t]', ' ')`"",
                            $cmd1,
                            $cmd2,
                            $pushdVideos,
                            "",
                            $callRename,
                            "popd",
                            $moveVideos,
                            "if not defined SKIP_PAUSE pause"
                        )
                    } else {
                        $cmd1 = '"' + $aniDLPath + '" --service "crunchy" --crapi web --cs ps5 --noaudio ' + $flag + ' ' + $seriesID + ' ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                        $cmd2 = '"' + $aniDLPath + '" --service "crunchy" --crapi web --cs android --novids --nosubs ' + $flag + ' ' + $seriesID + ' --chapters false ' + $episodeOption + ' --dubLang ' + $chosenDubLang + ' --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --kstream 1 --waittime 10000 --partsize 30 --videoTitle "' + $chosenVideoTitle + '" ' + $dynamicFileNameArg
                        $pushdMaster = 'pushd "' + $masterPath + '"'
                        $callAuth = 'call "' + $authScriptCurrent + '"'
                        $pushdVideos = 'pushd "' + $masterPath + '\videos"'
                        $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
                        $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%ORIGINAL%"'
                        $setBase = '    set "BASE=%%~nV"'
                        $setAudio = '    set "AUDIO=!BASE!.Japanese.audio.m4s"'
                        $batchContent = @(
                            "@echo off",
                            "chcp 65001 >nul",
                            $pushdMaster,
                            $callAuth,
                            "set `"ACTUAL_SHOW_NAME=$($cmdShowTitle -replace '[\r\n\t]', ' ')`"",
                            $cmd1,
                            $cmd2,
                            "REM -MUX AUDIO INTO VIDEO-",
                            "setlocal enabledelayedexpansion",
                            "@echo on",
                            $pushdVideos,
                            "",
                            'dir "Anime_Show - S*.mkv"',
                            'for %%V in ("Anime_Show - S*.mkv") do (',
                            '    echo Processing: %%V',
                            '    set "BASE=%%~nV"',
                            '    set "AUDIO=!BASE!.Japanese.audio.m4s"',
                            '    mkvmerge -o "!BASE!_muxed.mkv" ^',
                            '      "%%V" ^',
                            '      --language 0:ja-JP --track-name 0:"Japanese" ^',
                            '      "!AUDIO!"',
                            '    if exist "!BASE!_muxed.mkv" (',
                            '        del "%%V"',
                            '        ren "!BASE!_muxed.mkv" "%%~nxV"',
                            '        del "!AUDIO!"',
                            '    )',
                            ')',
                            '',
                            'rem -- Rename Anime_Show to actual show name',
                            'dir "Anime_Show - S*.mkv"',
                            'for %%F in ("Anime_Show - S*.mkv") do (',
                            '    set "NEWNAME=%%~nxF"',
                            '    set "NEWNAME=!NEWNAME:Anime_Show=%ACTUAL_SHOW_NAME%!"',
                            '    echo ren "%%~nxF" "!NEWNAME!"',
                            '    ren "%%~nxF" "!NEWNAME!"',
                            '    echo Rename errorlevel: !errorlevel!',
                            ')',
                            "popd",
                            "endlocal",
                            "",
                            "popd",
                            $moveVideos,
                            "if not defined SKIP_PAUSE pause"
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
                $cmd = '"' + $aniDLPath + '" --service "' + $serviceOption + '" --srz ' + $seriesID + ' --but -e ' + $skipInput + ' --dubLang ' + $chosenDubLang + ' --fontSize 45 --dlsubs all --defaultAudio ' + $chosenDefaultAudio + ' --defaultSub ' + $chosenSub + ' -q 0 --partsize 30 --videoTitle "' + $chosenVideoTitle + '"'
                $pushdMaster = 'pushd "' + $masterPath + '"'
                $callAuth = 'call "' + $authScriptCurrent + '"'
                $pushdVideos = 'pushd "' + $masterPath + '\videos"'
                $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
                $moveVideos = 'move "' + $masterPath + '\videos\*.mkv" "%ORIGINAL%"'
                $batchContent = @(
                    "chcp 65001",
                    "@echo off",
                    "SET ORIGINAL=%CD%",
                    $pushdMaster,
                    $callAuth,
                    $cmd,
                    $pushdVideos,
                    $callRename,
                    $moveVideos,
                    "if not defined SKIP_PAUSE pause"
                )
            } else {
                $pushdMaster = 'pushd "' + $masterPath + '"'
                $callAuth = 'call "' + $authScriptCurrent + '"'
                $pushdVideos = 'pushd "' + $masterPath + '\videos"'
                $callRename = 'call "' + $masterPath + '\videos\rename_mkv_tracks.bat"'
                $moveVideos = 'move "' + $masterPath + '\videos\%ACTUAL_SHOW_NAME% - S*.mkv" "%ORIGINAL%"'
                $batchContent = @(
                    "@echo off",
                    "chcp 65001 >nul",
                    $pushdMaster,
                    $callAuth,
                    $cmd,
                    $moveVideos,
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