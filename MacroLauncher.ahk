#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

global LAUNCHER_VERSION := "2.1.0"

global WORKER_URL := "https://tight-dust-10d2.lewisjenkins558.workers.dev/"
global DISCORD_URL := "https://discord.gg/PQ85S32Ht8"

; Credential & Session Files
global CRED_FILE := ""
global SESSION_FILE := ""
global DISCORD_ID_FILE := ""
global DISCORD_BAN_FILE := ""
global ADMIN_DISCORD_FILE := ""
global SESSION_LOG_FILE := ""
global MACHINE_BAN_FILE := ""
global HWID_BINDING_FILE := ""
global LAST_CRED_HASH_FILE := ""
global HWID_BAN_FILE := ""

; Master Credentials
global MASTER_KEY := ""
global DISCORD_WEBHOOK := ""
global ADMIN_PASS := ""
global SECURE_CONFIG_FILE := ""
global ENCRYPTED_KEY_FILE := ""
global MASTER_KEY_ROTATION_FILE := ""

; Login Settings
global DEFAULT_USER := "AHKvaultmacros@discord"
global MASTER_USER := "master"
global MAX_ATTEMPTS := 10
global LOCKOUT_FILE := A_Temp "\.lockout"

; Auth State
global gLoginGui := 0
global KEY_HISTORY := []
global APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content"
global SECURE_VAULT := APP_DIR "\{" CreateGUID() "}"
global BASE_DIR := SECURE_VAULT "\data"
global VERSION_FILE := SECURE_VAULT "\ver"
global ICON_DIR := SECURE_VAULT "\res"
global MANIFEST_URL := DecryptManifestUrl()
global mainGui := 0
global MACHINE_KEY := ""

global COLORS := {
    bg: "0x0a0e14",
    bgLight: "0x13171d",
    card: "0x161b22",
    cardHover: "0x1c2128",
    accent: "0x0044ff",
    accentHover: "0x2ea043",
    accentAlt: "0x1f6feb",
    text: "0xe6edf3",
    textDim: "0x7d8590",
    border: "0x21262d",
    success: "0x238636",
    warning: "0xd29922",
    danger: "0xda3633",
    favorite: "0xfbbf24"
}

; Stats & Favorites data
global macroStats := Map()
global favorites := Map()

; Hotkeys
#HotIf
^!p:: AdminPanel()
#HotIf

; =========================================
InitializeSecureVault()
SetTaskbarIcon()
LoadStats()
LoadFavorities()
CheckForUpdatesPrompt()
CreateMainGui()

CreateGUID() {
    guid := ""
    loop 32 {
        guid .= Format("{:X}", Random(0, 15))
        if (A_Index = 8 || A_Index = 12 || A_Index = 16 || A_Index = 20)
            guid .= "-"
    }
    return guid
}

; ========== INITIALIZATION ==========
InitializeSecureVault() {
    global APP_DIR, SECURE_VAULT, BASE_DIR, ICON_DIR, VERSION_FILE, MACHINE_KEY
    global STATS_FILE, FAVORITES_FILE, MANIFEST_URL
    global DISCORD_BAN_FILE, ADMIN_DISCORD_FILE
    
    MACHINE_KEY := GetOrCreatePersistentKey()
    HWID_BAN_FILE := SECURE_VAULT "\banned_hwids.txt"
    DISCORD_ID_FILE := SECURE_VAULT "\discord_id.txt"
    dirHash := HashString(MACHINE_KEY . A_ComputerName)
    APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content\{" SubStr(dirHash, 1, 8) "}"
    SECURE_VAULT := APP_DIR "\{" SubStr(dirHash, 9, 8) "}"
    BASE_DIR := SECURE_VAULT "\dat"
    ICON_DIR := SECURE_VAULT "\res"
    VERSION_FILE := SECURE_VAULT "\~ver.tmp"
    STATS_FILE := SECURE_VAULT "\stats.json"
    FAVORITES_FILE := SECURE_VAULT "\favorites.json"
    MANIFEST_URL := DecryptManifestUrl()
    
    DISCORD_BAN_FILE := SECURE_VAULT "\banned_discord_ids.txt"
    ADMIN_DISCORD_FILE := SECURE_VAULT "\admin_discord_ids.txt"
    
    try {
        DirCreate APP_DIR
        DirCreate SECURE_VAULT
        DirCreate BASE_DIR
        DirCreate ICON_DIR
    } catch as err {
        MsgBox "Failed to create application directories: " err.Message, "Initialization Error", "Icon!"
    }
    
    EnsureVersionFile()
    FetchMasterKeyFromManifest()
}

GetOrCreatePersistentKey() {
    regPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo"
    regCurrentKey := "MachineGUID"
    
    try {
        return RegRead(regPath, regCurrentKey)
    } catch {
        newKey := GenerateMachineKey()
        try RegWrite newKey, "REG_SZ", regPath, regCurrentKey
        return newKey
    }
}

GenerateMachineKey() {
    hwid := A_ComputerName . A_UserName . A_OSVersion
    key := HashString(hwid)
    loop 100
        key := HashString(key . hwid . A_Index)
    return key
}

HashString(str) {
    hash := 0
    for char in StrSplit(str) {
        hash := Mod(hash * 31 + Ord(char), 0xFFFFFFFF)
    }
    return Format("{:08X}", hash)
}

DecryptManifestUrl() {
    encrypted :=
        "68747470733A2F2F7261772E67697468756275736572636F6E74656E742E636F6D2F6C657769737772322F"
      . "6D6163726F2D6C61756E636865722D757064617465732F726566732F68656164732F6D61696E2F6D616E"
      . "69666573742E6A736F6E"

    url := ""
    pos := 1
    while (pos <= StrLen(encrypted)) {
        hex := SubStr(encrypted, pos, 2)
        url .= Chr("0x" hex)
        pos += 2
    }
    return url
}

EnsureVersionFile() {
    global VERSION_FILE
    if !FileExist(VERSION_FILE) {
        try FileAppend "0", VERSION_FILE
    }
}

SetTaskbarIcon() {
    global ICON_DIR
    iconPath := ICON_DIR "\v1ln.png"
    
    try {
        if FileExist(iconPath)
            TraySetIcon(iconPath)
        else
            TraySetIcon("shell32.dll", 3)
    } catch {
    }
}

; ========== STATS & FAVORITES SYSTEM ==========

LoadStats() {
    global macroStats, STATS_FILE
    
    if !FileExist(STATS_FILE) {
        macroStats := Map()
        return
    }
    
    try {
        json := FileRead(STATS_FILE, "UTF-8")
        parsed := ParseStatsJSON(json)
        if parsed
            macroStats := parsed
        else
            macroStats := Map()
    } catch {
        macroStats := Map()
    }
}

SaveStats() {
    global macroStats, STATS_FILE
    
    try {
        json := StatsToJSON(macroStats)
        if FileExist(STATS_FILE)
            FileDelete STATS_FILE
        FileAppend json, STATS_FILE, "UTF-8"
    } catch {
    }
}

LoadFavorities() {
    global favorites, FAVORITES_FILE
    
    if !FileExist(FAVORITES_FILE) {
        favorites := Map()
        return
    }
    
    try {
        json := FileRead(FAVORITES_FILE, "UTF-8")
        parsed := ParseFavoritesJSON(json)
        if parsed
            favorites := parsed
        else
            favorites := Map()
    } catch {
        favorites := Map()
    }
}

SaveFavorites() {
    global favorites, FAVORITES_FILE
    
    try {
        json := FavoritesToJSON(favorites)
        if FileExist(FAVORITES_FILE)
            FileDelete FAVORITES_FILE
        FileAppend json, FAVORITES_FILE, "UTF-8"
    } catch {
    }
}

GetMacroKey(macroPath) {
    return StrReplace(StrReplace(macroPath, "\", "_"), ":", "")
}

IncrementRunCount(macroPath) {
    global macroStats
    
    key := GetMacroKey(macroPath)
    
    if macroStats.Has(key) {
        stats := macroStats[key]
        stats.runCount++
        stats.lastRun := A_Now
    } else {
        macroStats[key] := {
            runCount: 1,
            lastRun: A_Now,
            firstRun: A_Now
        }
    }
    
    SaveStats()
}

GetRunCount(macroPath) {
    global macroStats
    key := GetMacroKey(macroPath)
    if macroStats.Has(key)
        return macroStats[key].runCount
    return 0
}

ToggleFavorite(macroPath) {
    global favorites
    key := GetMacroKey(macroPath)
    
    if favorites.Has(key)
        favorites.Delete(key)
    else
        favorites[key] := {
            path: macroPath,
            addedAt: A_Now
        }
    
    SaveFavorites()
}

IsFavorite(macroPath) {
    global favorites
    key := GetMacroKey(macroPath)
    return favorites.Has(key)
}

StatsToJSON(statsMap) {
    if statsMap.Count = 0
        return "{}"
    
    pairs := []
    for key, data in statsMap {
        keyStr := EscapeJSON(key)
        runCount := data.runCount
        lastRun := EscapeJSON(data.lastRun)
        firstRun := EscapeJSON(data.firstRun)
        
        pairs.Push('"' keyStr '":{"runCount":' runCount ',"lastRun":"' lastRun '","firstRun":"' firstRun '"}')
    }
    
    return "{" StrJoin(pairs, ",") "}"
}

FavoritesToJSON(favMap) {
    if favMap.Count = 0
        return "{}"
    
    pairs := []
    for key, data in favMap {
        keyStr := EscapeJSON(key)
        path := EscapeJSON(data.path)
        addedAt := EscapeJSON(data.addedAt)
        
        pairs.Push('"' keyStr '":{"path":"' path '","addedAt":"' addedAt '"}')
    }
    
    return "{" StrJoin(pairs, ",") "}"
}

ParseStatsJSON(json) {
    result := Map()
    
    if !json || json = "{}"
        return result
    
    try {
        content := Trim(SubStr(json, 2, StrLen(json) - 2))
        entries := SplitTopLevel(content)
        
        for entry in entries {
            if !InStr(entry, ":")
                continue
            
            if !RegExMatch(entry, '"([^"]+)":\s*{', &m)
                continue
            
            key := m[1]
            
            runCount := 0
            lastRun := ""
            firstRun := ""
            
            if RegExMatch(entry, '"runCount"\s*:\s*(\d+)', &m2)
                runCount := Integer(m2[1])
            
            if RegExMatch(entry, '"lastRun"\s*:\s*"([^"]+)"', &m3)
                lastRun := m3[1]
            
            if RegExMatch(entry, '"firstRun"\s*:\s*"([^"]+)"', &m4)
                firstRun := m4[1]
            
            result[key] := {
                runCount: runCount,
                lastRun: lastRun,
                firstRun: firstRun
            }
        }
    } catch {
        return Map()
    }
    
    return result
}

ParseFavoritesJSON(json) {
    result := Map()
    
    if !json || json = "{}"
        return result
    
    try {
        content := Trim(SubStr(json, 2, StrLen(json) - 2))
        entries := SplitTopLevel(content)
        
        for entry in entries {
            if !InStr(entry, ":")
                continue
            
            if !RegExMatch(entry, '"([^"]+)":\s*{', &m)
                continue
            
            key := m[1]
            
            path := ""
            addedAt := ""
            
            if RegExMatch(entry, '"path"\s*:\s*"([^"]+)"', &m2)
                path := UnescapeJSON(m2[1])
            
            if RegExMatch(entry, '"addedAt"\s*:\s*"([^"]+)"', &m3)
                addedAt := m3[1]
            
            if path != ""
                result[key] := {
                    path: path,
                    addedAt: addedAt
                }
        }
    } catch {
        return Map()
    }
    
    return result
}

SplitTopLevel(str) {
    result := []
    depth := 0
    current := ""
    
    Loop Parse, str {
        char := A_LoopField
        
        if (char = "{")
            depth++
        else if (char = "}")
            depth--
        
        if (char = "," && depth = 0) {
            if (Trim(current) != "")
                result.Push(Trim(current))
            current := ""
        } else {
            current .= char
        }
    }
    
    if (Trim(current) != "")
        result.Push(Trim(current))
    
    return result
}

EscapeJSON(str) {
    str := StrReplace(str, "\", "\\")
    str := StrReplace(str, '"', '\"')
    str := StrReplace(str, "`n", "\n")
    str := StrReplace(str, "`r", "\r")
    str := StrReplace(str, "`t", "\t")
    return str
}

UnescapeJSON(str) {
    str := StrReplace(str, "\\", "\")
    str := StrReplace(str, '\"', '"')
    str := StrReplace(str, "\n", "`n")
    str := StrReplace(str, "\r", "`r")
    str := StrReplace(str, "\t", "`t")
    return str
}

StrJoin(arr, delim) {
    result := ""
    for item in arr {
        if (result != "")
            result .= delim
        result .= item
    }
    return result
}

; ========== UPDATE FUNCTIONS ==========

CheckForUpdatesPrompt() {
    global MANIFEST_URL, VERSION_FILE, BASE_DIR, ICON_DIR

    tmpManifest := A_Temp "\manifest.json"
    tmpZip := A_Temp "\Macros.zip"
    extractDir := A_Temp "\macro_extract"

    if !SafeDownload(MANIFEST_URL, tmpManifest)
        return

    try json := FileRead(tmpManifest, "UTF-8")
    catch {
        return
    }

    manifest := ParseManifest(json)
    if !manifest
        return

    current := "0"
    try {
        if FileExist(VERSION_FILE)
            current := Trim(FileRead(VERSION_FILE))
    }

    if VersionCompare(manifest.version, current) <= 0
        return

    changelogText := ""
    for line in manifest.changelog
        changelogText .= "• " line "`n"

    choice := MsgBox(
        "Update available!`n`n"
        . "Current: " current "`n"
        . "Latest: " manifest.version "`n`n"
        . "What's new:`n" changelogText "`n"
        . "Do you want to update now?",
        "V1LN clan Update",
        "YesNo Iconi"
    )
    if (choice = "No")
        return

    downloadSuccess := false
    attempts := 0
    maxAttempts := 3

    while (!downloadSuccess && attempts < maxAttempts) {
        attempts++
        if SafeDownload(manifest.zip_url, tmpZip, 30000) && IsValidZip(tmpZip) {
            downloadSuccess := true
        } else {
            try if FileExist(tmpZip) FileDelete(tmpZip)
            if (attempts < maxAttempts)
                Sleep 1000
        }
    }

    if !downloadSuccess {
        MsgBox(
            "Failed to download a valid ZIP after " maxAttempts " attempts.`n`n"
            . "Zip URL:`n" manifest.zip_url,
            "Download Failed",
            "Icon!"
        )
        return
    }

    try {
        if DirExist(extractDir)
            DirDelete extractDir, true
        DirCreate extractDir
    } catch as err {
        ShowUpdateFail("Create extraction directory", err, "extractDir=`n" extractDir)
        return
    }

    extractSuccess := false
    try {
        RunWait 'tar -xf "' tmpZip '" -C "' extractDir '"', , "Hide"
        extractSuccess := DirExist(extractDir) && HasAnyFolders(extractDir)
    } catch {
        extractSuccess := false
    }

    if !extractSuccess {
        try {
            psCmd := 'powershell -Command "Expand-Archive -Path `"' tmpZip '`" -DestinationPath `"' extractDir '`" -Force"'
            RunWait psCmd, , "Hide"
            extractSuccess := DirExist(extractDir) && HasAnyFolders(extractDir)
        } catch as err {
            ShowUpdateFail("Extraction (tar + PowerShell)", err, "zip=`n" tmpZip "`nextractDir=`n" extractDir)
            return
        }
    }

    if !extractSuccess {
        MsgBox "Update failed: extraction produced no folders.", "Error", "Icon!"
        return
    }

    hasMacrosFolder := DirExist(extractDir "\Macros")
    hasIconsFolder := DirExist(extractDir "\icons")
    hasLooseFolders := HasAnyFolders(extractDir)

    useNestedStructure := hasMacrosFolder
    if (!hasMacrosFolder && !hasLooseFolders) {
        MsgBox "Update failed: No valid content found in zip file.", "Error", "Icon!"
        return
    }

    try {
        if DirExist(BASE_DIR)
            DirDelete BASE_DIR, true
        DirCreate BASE_DIR

        if useNestedStructure {
            Loop Files, extractDir "\Macros\*", "D"
                TryDirMove(A_LoopFilePath, BASE_DIR "\" A_LoopFileName, true)
        } else {
            Loop Files, extractDir "\*", "D" {
                if (A_LoopFileName != "icons")
                    TryDirMove(A_LoopFilePath, BASE_DIR "\" A_LoopFileName, true)
            }
        }
    } catch as err {
        ShowUpdateFail("Install / move folders", err, "BASE_DIR=`n" BASE_DIR "`n`nextractDir=`n" extractDir)
        return
    }

    iconsUpdated := false
    if hasIconsFolder {
        try {
            if !DirExist(ICON_DIR)
                DirCreate ICON_DIR
            Loop Files, extractDir "\icons\*.*", "F" {
                TryFileCopy(A_LoopFilePath, ICON_DIR "\" A_LoopFileName, true)
                iconsUpdated := true
            }
        } catch as err {
            ShowUpdateFail("Copy icons", err, "ICON_DIR=`n" ICON_DIR)
        }
    }

    try {
        if FileExist(VERSION_FILE)
            FileDelete VERSION_FILE
        FileAppend manifest.version, VERSION_FILE
    } catch as err {
        ShowUpdateFail("Write version file", err, "VERSION_FILE=`n" VERSION_FILE)
    }

    try {
        if FileExist(tmpZip)
            FileDelete tmpZip
        if DirExist(extractDir)
            DirDelete extractDir, true
    } catch {
    }

    updateMsg := "Update complete!`n`nVersion " manifest.version " installed.`n`n"
    if iconsUpdated
    updateMsg .= "`nChanges:`n" changelogText

    MsgBox updateMsg, "Update Finished", "Iconi"
}

HasAnyFolders(dir) {
    try {
        Loop Files, dir "\*", "D"
            return true
    }
    return false
}

ManualUpdate(*) {
    global MANIFEST_URL, VERSION_FILE, BASE_DIR, ICON_DIR
    
    choice := MsgBox(
        "Check for macro updates?`n`n"
        "This will download the latest macros from the repository.",
        "Check for Updates",
        "YesNo Iconi"
    )
    
    if (choice = "No")
        return
    
    tmpManifest := A_Temp "\manifest.json"
    tmpZip := A_Temp "\Macros.zip"
    extractDir := A_Temp "\macro_extract"
    
    if !SafeDownload(MANIFEST_URL, tmpManifest) {
        MsgBox(
            "Failed to download update information.`n`n"
            "Please check your internet connection.`n`n"
            "Manifest URL: " MANIFEST_URL,
            "Download Failed",
            "Icon!"
        )
        return
    }
    
    json := ""
    try {
        json := FileRead(tmpManifest, "UTF-8")
    } catch {
        MsgBox "Failed to read update information.", "Error", "Icon!"
        return
    }
    
    manifest := ParseManifest(json)
    if !manifest {
        MsgBox "Failed to parse update information.", "Error", "Icon!"
        return
    }
    
    changelogText := ""
    for line in manifest.changelog {
        changelogText .= "• " line "`n"
    }
    
    choice := MsgBox(
        "Update available!`n`n"
        "Latest: " manifest.version "`n`n"
        "What's new:`n" changelogText "`n"
        "Download and install now?",
        "Update Available",
        "YesNo Iconi"
    )
    
    if (choice = "No")
        return
    
    downloadSuccess := false
    attempts := 0
    maxAttempts := 3
    
    while (!downloadSuccess && attempts < maxAttempts) {
        attempts++
        
        if SafeDownload(manifest.zip_url, tmpZip, 30000) {
            try {
                fileSize := 0
                Loop Files, tmpZip
                    fileSize := A_LoopFileSize
                
                if (fileSize >= 100) {
                    downloadSuccess := true
                } else {
                    try FileDelete tmpZip
                    if (attempts < maxAttempts)
                        Sleep 1000
                }
            } catch {
                if (attempts < maxAttempts)
                    Sleep 1000
            }
        }
    }
    
    if !downloadSuccess {
        MsgBox(
            "Failed to download update after " maxAttempts " attempts.`n`n"
            "Please check your internet connection and try again later.`n`n"
            "Zip URL: " manifest.zip_url,
            "Download Failed",
            "Icon!"
        )
        return
    }
    
    try {
        if DirExist(extractDir)
            DirDelete extractDir, true
        DirCreate extractDir
    } catch as err {
        MsgBox "Failed to create extraction directory: " err.Message, "Error", "Icon!"
        return
    }
    
    extractSuccess := false
    try {
        RunWait 'tar -xf "' tmpZip '" -C "' extractDir '"', , "Hide"
        
        hasContent := false
        try {
            Loop Files, extractDir "\*", "D" {
                hasContent := true
                break
            }
        }
        extractSuccess := hasContent
    } catch {
    }
    
    if !extractSuccess {
        try {
            psCmd := 'powershell -Command "Expand-Archive -Path `"' tmpZip '`" -DestinationPath `"' extractDir '`" -Force"'
            RunWait psCmd, , "Hide"
            
            hasContent := false
            try {
                Loop Files, extractDir "\*", "D" {
                    hasContent := true
                    break
                }
            }
            extractSuccess := hasContent
        } catch {
            MsgBox(
                "Failed to extract update archive.`n`n"
                "Both tar and PowerShell extraction methods failed.",
                "Extraction Failed",
                "Icon!"
            )
            return
        }
    }
    
    if !extractSuccess {
        MsgBox "Update failed: extraction produced no folders.", "Error", "Icon!"
        return
    }
    
    hasMacrosFolder := false
    hasIconsFolder := false
    hasLooseFolders := false
    
    try {
        if DirExist(extractDir "\Macros")
            hasMacrosFolder := true
        if DirExist(extractDir "\icons")
            hasIconsFolder := true
        
        Loop Files, extractDir "\*", "D" {
            if (A_LoopFileName != "Macros" && A_LoopFileName != "icons") {
                hasLooseFolders := true
                break
            }
        }
    }
    
    useNestedStructure := hasMacrosFolder
    
    if (!hasMacrosFolder && !hasLooseFolders) {
        MsgBox "Update failed: No valid content found in zip file.", "Error", "Icon!"
        return
    }
    
    installSuccess := false
    try {
        if DirExist(BASE_DIR)
            DirDelete BASE_DIR, true
        DirCreate BASE_DIR
        
        if useNestedStructure {
            Loop Files, extractDir "\Macros\*", "D"
                DirMove A_LoopFilePath, BASE_DIR "\" A_LoopFileName, 1
        } else {
            Loop Files, extractDir "\*", "D" {
                if (A_LoopFileName != "icons")
                    DirMove A_LoopFilePath, BASE_DIR "\" A_LoopFileName, 1
            }
        }
        installSuccess := true
    } catch as err {
        MsgBox "Failed to install macro update: " err.Message, "Error", "Icon!"
        return
    }
    
    iconsUpdated := false
    
    if DirExist(extractDir "\icons") {
        try {
            if !DirExist(ICON_DIR)
                DirCreate ICON_DIR
        }
        
        try {
            iconCount := 0
            Loop Files, extractDir "\icons\*.*" {
                FileCopy A_LoopFilePath, ICON_DIR "\" A_LoopFileName, 1
                iconCount++
            }
            
            if (iconCount > 0)
                iconsUpdated := true
        } catch as err {
        }
    }
    
    try {
        if FileExist(VERSION_FILE)
            FileDelete VERSION_FILE
        FileAppend manifest.version, VERSION_FILE
    }
    
    try {
        if FileExist(tmpZip)
            FileDelete tmpZip
        if DirExist(extractDir)
            DirDelete extractDir, true
    }
    
    updateMsg := "Update complete!`n`nVersion " manifest.version " installed.`n`n"
    if iconsUpdated
    updateMsg .= "`nChanges:`n" changelogText "`n`nRestart the launcher to see changes."
    
    MsgBox(updateMsg, "Update Finished", "Iconi")
    
    try {
        mainGui.Destroy()
        CreateMainGui()
    }
}

SafeDownload(url, out, timeoutMs := 10000) {
    if !url || !out
        return false
    
    try {
        if FileExist(out)
            FileDelete out
        
        ToolTip "Downloading..."
        Download url, out
        
        startTime := A_TickCount
        while !FileExist(out) {
            if (A_TickCount - startTime > timeoutMs) {
                ToolTip
                return false
            }
            Sleep 100
        }
        
        ToolTip
        
        fileSize := 0
        Loop Files, out
            fileSize := A_LoopFileSize
        
        if (fileSize < 100) {
            try FileDelete out
            return false
        }
        
        return true
    } catch {
        ToolTip
        return false
    }
}

VersionCompare(a, b) {
    a := RegExReplace(a, "[^0-9.]", "")
    b := RegExReplace(b, "[^0-9.]", "")
    
    pa := StrSplit(a, ".")
    pb := StrSplit(b, ".")
    
    Loop Max(pa.Length, pb.Length) {
        va := pa.Has(A_Index) ? Integer(pa[A_Index]) : 0
        vb := pb.Has(A_Index) ? Integer(pb[A_Index]) : 0
        
        if (va > vb)
            return 1
        if (va < vb)
            return -1
    }
    
    return 0
}

ParseManifest(json) {
    if !json
        return false
    
    manifest := {
        version: "",
        zip_url: "",
        changelog: []
    }
    
    try {
        if RegExMatch(json, '"version"\s*:\s*"([^"]+)"', &m)
            manifest.version := m[1]
        
        if RegExMatch(json, '"zip_url"\s*:\s*"([^"]+)"', &m)
            manifest.zip_url := m[1]
        
        pat := 's)"changelog"\s*:\s*\[(.*?)\]'
        if RegExMatch(json, pat, &m) {
            block := m[1]
            pos := 1
            while RegExMatch(block, 's)"((?:\\.|[^"\\])*)"', &mm, pos) {
                item := mm[1]
                item := StrReplace(item, '\"', '"')
                item := StrReplace(item, "\\", "\")
                item := StrReplace(item, "\n", "`n")
                item := StrReplace(item, "\r", "`r")
                manifest.changelog.Push(item)
                pos := mm.Pos + mm.Len
            }
        }
    } catch {
        return false
    }
    
    if (!manifest.version || !manifest.zip_url)
        return false
    
    return manifest
}

; ========== MAIN GUI ==========

CreateMainGui() {
    global mainGui, COLORS, BASE_DIR, ICON_DIR
    
    mainGui := Gui("-Resize +Border", " V1LN clan")
    mainGui.BackColor := COLORS.bg
    mainGui.SetFont("s10", "Segoe UI")
    
    iconPath := ICON_DIR "\v1ln.png"
    if FileExist(iconPath) {
        try {
            mainGui.Show("Hide")
            mainGui.Opt("+Icon" iconPath)
        }
    }
    
    mainGui.Add("Text", "x0 y0 w550 h80 Background" COLORS.accent)
    
    launcherImage := ICON_DIR "\v1ln.png"
    if FileExist(launcherImage) {
        try {
            mainGui.Add("Picture", "x5 y0 w75 h75 BackgroundTrans", launcherImage)
        }
    }
    
    titleText := mainGui.Add("Text", "x85 y17 w280 h100 c" COLORS.text " BackgroundTrans", " V1LN clan")
    titleText.SetFont("s24 bold")

    btnNuke := mainGui.Add("Button", "x290 y25 w75 h35 Background" COLORS.danger, "Uninstall")
    btnNuke.SetFont("s9")
    btnNuke.OnEvent("Click", CompleteUninstall)

    btnUpdate := mainGui.Add("Button", "x370 y25 w75 h35 Background" COLORS.accentHover, "Update")
    btnUpdate.SetFont("s10")
    btnUpdate.OnEvent("Click", ManualUpdate)
    
    btnLog := mainGui.Add("Button", "x450 y25 w75 h35 Background" COLORS.accentAlt, "Changelog")
    btnLog.SetFont("s10")
    btnLog.OnEvent("Click", ShowChangelog)

    mainGui.Add("Text", "x25 y100 w500 c" COLORS.text, "Games").SetFont("s12 bold")
    mainGui.Add("Text", "x25 y125 w500 h1 Background" COLORS.border)
    
    categories := GetCategories()
    yPos := 145
    xPos := 25
    cardWidth := 500
    cardHeight := 70
    
    if (categories.Length = 0) {
        noGameText := mainGui.Add("Text", "x25 y145 w500 h120 c" COLORS.textDim " Center", 
            "No game categories found`n`nPlace game folders in the secure vault")
        noGameText.SetFont("s10")
        yPos := 275
    } else {
        for category in categories {
            CreateCategoryCard(mainGui, category, xPos, yPos, cardWidth, cardHeight)
            yPos += cardHeight + 12
        }
    }
    
    bottomY := yPos + 15
    mainGui.Add("Text", "x0 y" bottomY " w550 h1 Background" COLORS.border)
    
    linkY := bottomY + 15
    CreateLink(mainGui, "Discord", "https://discord.gg/PQ85S32Ht8", 25, linkY)
    
    mainGui.Show("w550 h" (bottomY + 60) " Center")
}

GetCategories() {
    global BASE_DIR
    arr := []
    
    if !DirExist(BASE_DIR)
        return arr
    
    try {
        Loop Files, BASE_DIR "\*", "D" {
            if (StrLower(A_LoopFileName) = "icons")
                continue
            arr.Push(A_LoopFileName)
        }
    }
    
    return arr
}

CreateCategoryCard(gui, category, x, y, w, h) {
    global COLORS
    
    card := gui.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)
    
    iconPath := GetGameIcon(category)
    iconX := x + 15
    iconY := y + 15
    iconSize := 40
    
    if (iconPath && FileExist(iconPath)) {
        try {
            gui.Add("Picture", "x" iconX " y" iconY " w" iconSize " h" iconSize " BackgroundTrans", iconPath)
        } catch {
            CreateCategoryBadge(gui, category, iconX, iconY, iconSize)
        }
    } else {
        CreateCategoryBadge(gui, category, iconX, iconY, iconSize)
    }
    
    titleText := gui.Add("Text", "x" (x + 70) " y" (y + 22) " w" (w - 150) " c" COLORS.text " BackgroundTrans", category)
    titleText.SetFont("s11 bold")
    
    openBtn := gui.Add("Button", "x" (x + w - 95) " y" (y + 18) " w80 h34 Background" COLORS.accent, "Open →")
    openBtn.SetFont("s9 bold")
    openBtn.OnEvent("Click", (*) => OpenCategory(category))
}

CreateCategoryBadge(gui, category, x, y, size := 40) {
    global COLORS
    
    initial := SubStr(category, 1, 1)
    iconColor := GetCategoryColor(category)
    
    badge := gui.Add("Text", "x" x " y" y " w" size " h" size " Background" iconColor " Center", initial)
    badge.SetFont("s18 bold c" COLORS.text)
    
    return badge
}

GetGameIcon(category) {
    global ICON_DIR, BASE_DIR
    
    extensions := ["png", "ico", "jpg", "jpeg"]
    
    for ext in extensions {
        iconPath := ICON_DIR "\" category "." ext
        if FileExist(iconPath)
            return iconPath
    }
    
    for ext in extensions {
        iconPath := BASE_DIR "\" category "." ext
        if FileExist(iconPath)
            return iconPath
    }
    
    for ext in extensions {
        iconPath := BASE_DIR "\" category "\icon." ext
        if FileExist(iconPath)
            return iconPath
    }
    
    return ""
}

GetCategoryColor(category) {
    colors := ["0x238636", "0x1f6feb", "0x8957e5", "0xda3633", "0xbc4c00", "0x1a7f37", "0xd29922"]
    
    hash := 0
    for char in StrSplit(category) {
        hash += Ord(char)
    }
    
    return colors[Mod(hash, colors.Length) + 1]
}

CreateLink(gui, label, url, x, y) {
    global COLORS
    
    link := gui.Add("Text", "x" x " y" y " c" COLORS.accent " BackgroundTrans", label)
    link.SetFont("s9 underline")
    link.OnEvent("Click", (*) => SafeOpenURL(url))
}

SafeOpenURL(url) {
    url := Trim(url)
    
    if (!InStr(url, "http://") && !InStr(url, "https://")) {
        MsgBox "Invalid URL: " url, "Error", "Icon!"
        return
    }
    
    try {
        Run url
    } catch as err {
        MsgBox "Failed to open URL: " err.Message, "Error", "Icon!"
    }
}

; ========== CATEGORY VIEW ==========

OpenCategory(category) {
    global COLORS, BASE_DIR
    
    macros := GetMacrosWithInfo(category)
    
    if (macros.Length = 0) {
        MsgBox(
            "No macros found in '" category "'`n`n"
            "To add macros:`n"
            "1. Create a 'Main.ahk' file in each subfolder`n"
            "2. Or run the update to download macros",
            "No Macros",
            "Iconi"
        )
        return
    }
    
    win := Gui("-Resize +Border", category " - Macros")
    win.BackColor := COLORS.bg
    win.SetFont("s10", "Segoe UI")
    
    win.__data := macros
    win.__cards := []
    win.__currentPage := 1
    win.__itemsPerPage := 8
    win.__sortBy := "favorites"
    win.__category := category
    
    gameIcon := GetGameIcon(category)
    if (gameIcon && FileExist(gameIcon)) {
        try {
            win.Show("Hide")
            win.Opt("+Icon" gameIcon)
        }
    }
    
    win.Add("Text", "x0 y0 w750 h90 Background" COLORS.accent)
    
    backBtn := win.Add("Button", "x20 y25 w70 h35 Background" COLORS.accentHover, "← Back")
    backBtn.SetFont("s10")
    backBtn.OnEvent("Click", (*) => win.Destroy())
    
    title := win.Add("Text", "x105 y20 w400 h100 c" COLORS.text " BackgroundTrans", category)
    title.SetFont("s22 bold")
    
    sortLabel := win.Add("Text", "x530 y25 w60 c" COLORS.text " BackgroundTrans", "Sort by:")
    sortLabel.SetFont("s9")
    
    sortDDL := win.Add("DropDownList", "x530 y45 w200 Background" COLORS.card " c" COLORS.text, 
        ["⭐ Favorites First", "🔤 Name (A-Z)", "🔤 Name (Z-A)", "📊 Most Used", "📊 Least Used", "📅 Recently Added"])
    sortDDL.SetFont("s9")
    sortDDL.Choose(1)
    sortDDL.OnEvent("Change", (*) => ChangeSortAndRefresh(win, sortDDL.Text, category))
    
    win.__scrollY := 110
    
    RenderCards(win)
    win.Show("w750 h640 Center")
}

ChangeSortAndRefresh(win, sortText, category) {
    sortMap := Map(
        "⭐ Favorites First", "favorites",
        "🔤 Name (A-Z)", "name_asc",
        "🔤 Name (Z-A)", "name_desc",
        "📊 Most Used", "runs_desc",
        "📊 Least Used", "runs_asc",
        "📅 Recently Added", "recent"
    )
    
    sortBy := sortMap.Has(sortText) ? sortMap[sortText] : "favorites"
    
    win.Destroy()
    Sleep 100
    OpenCategoryWithSort(category, sortBy)
}

OpenCategoryWithSort(category, sortBy := "favorites") {
    global COLORS, BASE_DIR
    
    macros := GetMacrosWithInfo(category, sortBy)
    
    if (macros.Length = 0) {
        MsgBox("No macros found in '" category "'", "No Macros", "Iconi")
        return
    }
    
    win := Gui("-Resize +Border", category " - Macros")
    win.BackColor := COLORS.bg
    win.SetFont("s10", "Segoe UI")
    
    win.__data := macros
    win.__cards := []
    win.__currentPage := 1
    win.__itemsPerPage := 8
    win.__sortBy := sortBy
    win.__category := category
    
    gameIcon := GetGameIcon(category)
    if (gameIcon && FileExist(gameIcon)) {
        try {
            win.Show("Hide")
            win.Opt("+Icon" gameIcon)
        }
    }
    
    win.Add("Text", "x0 y0 w750 h90 Background" COLORS.accent)
    
    backBtn := win.Add("Button", "x20 y25 w70 h35 Background" COLORS.accentHover, "← Back")
    backBtn.SetFont("s10")
    backBtn.OnEvent("Click", (*) => win.Destroy())
    
    title := win.Add("Text", "x105 y20 w400 h100 c" COLORS.text " BackgroundTrans", category)
    title.SetFont("s22 bold")
    
    sortLabel := win.Add("Text", "x530 y25 w60 c" COLORS.text " BackgroundTrans", "Sort by:")
    sortLabel.SetFont("s9")
    
    sortDDL := win.Add("DropDownList", "x530 y45 w200 Background" COLORS.card " c" COLORS.text, 
        ["⭐ Favorites First", "🔤 Name (A-Z)", "🔤 Name (Z-A)", "📊 Most Used", "📊 Least Used", "📅 Recently Added"])
    sortDDL.SetFont("s9")
    
    sortIndexMap := Map(
        "favorites", 1,
        "name_asc", 2,
        "name_desc", 3,
        "runs_desc", 4,
        "runs_asc", 5,
        "recent", 6
    )
    sortDDL.Choose(sortIndexMap.Has(sortBy) ? sortIndexMap[sortBy] : 1)
    sortDDL.OnEvent("Change", (*) => ChangeSortAndRefresh(win, sortDDL.Text, category))
    
    win.__scrollY := 110
    
    RenderCards(win)
    win.Show("w750 h640 Center")
}

RenderCards(win) {
    global COLORS
    
    if !win.HasProp("__data")
        return
    
    if win.HasProp("__cards") && win.__cards.Length > 0 {
        for ctrl in win.__cards {
            try ctrl.Destroy()
            catch {
            }
        }
    }
    win.__cards := []
    
    macros := win.__data
    scrollY := win.__scrollY
    
    if (macros.Length = 0) {
        noResult := win.Add("Text", "x25 y" scrollY " w700 h100 c" COLORS.textDim " Center", "No macros found")
        noResult.SetFont("s10")
        win.__cards.Push(noResult)
        return
    }
    
    itemsPerPage := win.__itemsPerPage
    currentPage := win.__currentPage
    totalPages := Ceil(macros.Length / itemsPerPage)
    
    if (currentPage > totalPages) {
        currentPage := totalPages
        win.__currentPage := currentPage
    }
    
    startIdx := ((currentPage - 1) * itemsPerPage) + 1
    endIdx := Min(currentPage * itemsPerPage, macros.Length)
    
    itemsToShow := endIdx - startIdx + 1
    
    if (itemsToShow = 1) {
        item := macros[startIdx]
        CreateFullWidthCard(win, item, 25, scrollY, 700, 110)
    } else {
        cardWidth := 340
        cardHeight := 110
        spacing := 10
        yPos := scrollY
        
        Loop itemsToShow {
            idx := startIdx + A_Index - 1
            item := macros[idx]
            
            col := Mod(A_Index - 1, 2)
            row := Floor((A_Index - 1) / 2)
            
            xPos := 25 + (col * (cardWidth + spacing))
            yPos := scrollY + (row * (cardHeight + spacing))
            
            CreateGridCard(win, item, xPos, yPos, cardWidth, cardHeight)
        }
    }
    
    if (macros.Length > itemsPerPage) {
        paginationY := scrollY + 470
        
        pageInfo := win.Add("Text", "x25 y" paginationY " w300 c" COLORS.textDim, 
            "Page " currentPage " of " totalPages " (" macros.Length " total)")
        pageInfo.SetFont("s9")
        win.__cards.Push(pageInfo)
        
        if (currentPage > 1) {
            prevBtn := win.Add("Button", "x335 y" (paginationY - 5) " w90 h35 Background" COLORS.accentHover, "← Previous")
            prevBtn.SetFont("s9")
            prevBtn.OnEvent("Click", (*) => ChangePage(win, -1))
            win.__cards.Push(prevBtn)
        }
        
        if (currentPage < totalPages) {
            nextBtn := win.Add("Button", "x635 y" (paginationY - 5) " w90 h35 Background" COLORS.accentHover, "Next →")
            nextBtn.SetFont("s9")
            nextBtn.OnEvent("Click", (*) => ChangePage(win, 1))
            win.__cards.Push(nextBtn)
        }
    }
}

CreateFullWidthCard(win, item, x, y, w, h) {
    global COLORS
    
    card := win.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)
    win.__cards.Push(card)
    
    iconPath := GetMacroIcon(item.path)
    hasIcon := false
    
    if (iconPath && FileExist(iconPath)) {
        try {
            pic := win.Add("Picture", "x" (x + 20) " y" (y + 15) " w80 h80 BackgroundTrans", iconPath)
            win.__cards.Push(pic)
            hasIcon := true
        } catch {
        }
    }
    
    if (!hasIcon) {
        initial := SubStr(item.info.Title, 1, 1)
        iconColor := GetCategoryColor(item.info.Title)
        badge := win.Add("Text", "x" (x + 20) " y" (y + 15) " w80 h80 Background" iconColor " Center", initial)
        badge.SetFont("s32 bold c" COLORS.text)
        win.__cards.Push(badge)
    }
    
    titleCtrl := win.Add("Text", "x" (x + 120) " y" (y + 20) " w340 h100 c" COLORS.text " BackgroundTrans", item.info.Title)
    titleCtrl.SetFont("s13 bold")
    win.__cards.Push(titleCtrl)
    
    creatorCtrl := win.Add("Text", "x" (x + 120) " y" (y + 50) " w340 c" COLORS.textDim " BackgroundTrans", "by " item.info.Creator)
    creatorCtrl.SetFont("s10")
    win.__cards.Push(creatorCtrl)
    
    versionCtrl := win.Add("Text", "x" (x + 120) " y" (y + 75) " w60 h22 Background" COLORS.accentAlt " c" COLORS.text " Center", "v" item.info.Version)
    versionCtrl.SetFont("s9 bold")
    win.__cards.Push(versionCtrl)
    
    runCount := GetRunCount(item.path)
    if (runCount > 0) {
        runCountCtrl := win.Add("Text", "x" (x + 190) " y" (y + 75) " w100 h22 c" COLORS.textDim " BackgroundTrans", "Runs: " runCount)
        runCountCtrl.SetFont("s9")
        win.__cards.Push(runCountCtrl)
    }
    
currentPath := item.path
isFav := IsFavorite(currentPath)
favBtn := win.Add(
    "Button",
    "x" (x + w - 145)
    " y" (y + 20)  ; Adjust Y position slightly
    " w35 h35 Center Background" (isFav ? COLORS.favorite : COLORS.cardHover),
    isFav ? "★" : "✰"
)
favBtn.SetFont("s18", "Segoe UI Symbol")  ; Slightly larger font
favBtn.OnEvent("Click", (*) => ToggleFavoriteAndRefresh(win, currentPath))
win.__cards.Push(favBtn)
    
    runBtn := win.Add("Button", "x" (x + w - 100) " y" (y + 20) " w90 h35 Background" COLORS.success, "▶ Run")
    runBtn.SetFont("s11 bold")
    runBtn.OnEvent("Click", (*) => RunMacro(currentPath))
    win.__cards.Push(runBtn)
    
    if (Trim(item.info.Links) != "") {
        currentLinks := item.info.Links
        linksBtn := win.Add("Button", "x" (x + w - 100) " y" (y + 65) " w90 h30 Background" COLORS.accentAlt, "🔗 Links")
        linksBtn.SetFont("s10")
        linksBtn.OnEvent("Click", (*) => OpenLinks(currentLinks))
        win.__cards.Push(linksBtn)
    }
}

CreateGridCard(win, item, x, y, w, h) {
    global COLORS
    
    card := win.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)
    win.__cards.Push(card)
    
    iconPath := GetMacroIcon(item.path)
    hasIcon := false
    
    if (iconPath && FileExist(iconPath)) {
        try {
            pic := win.Add("Picture", "x" (x + 15) " y" (y + 15) " w60 h60 BackgroundTrans", iconPath)
            win.__cards.Push(pic)
            hasIcon := true
        } catch {
        }
    }
    
    if (!hasIcon) {
        initial := SubStr(item.info.Title, 1, 1)
        iconColor := GetCategoryColor(item.info.Title)
        badge := win.Add("Text", "x" (x + 15) " y" (y + 15) " w60 h60 Background" iconColor " Center", initial)
        badge.SetFont("s24 bold c" COLORS.text)
        win.__cards.Push(badge)
    }
    
    titleCtrl := win.Add("Text", "x" (x + 90) " y" (y + 15) " w" (w - 190) " h30 c" COLORS.text " BackgroundTrans", item.info.Title)
    titleCtrl.SetFont("s11 bold")
    win.__cards.Push(titleCtrl)
    
    creatorCtrl := win.Add("Text", "x" (x + 90) " y" (y + 40) " w" (w - 190) " c" COLORS.textDim " BackgroundTrans", "by " item.info.Creator)
    creatorCtrl.SetFont("s9")
    win.__cards.Push(creatorCtrl)
    
    versionCtrl := win.Add("Text", "x" (x + 90) " y" (y + 63) " w50 h18 Background" COLORS.accentAlt " c" COLORS.text " Center", "v" item.info.Version)
    versionCtrl.SetFont("s8 bold")
    win.__cards.Push(versionCtrl)
    
    runCount := GetRunCount(item.path)
    if (runCount > 0) {
        runCountCtrl := win.Add("Text", "x" (x + 150) " y" (y + 63) " w80 h18 c" COLORS.textDim " BackgroundTrans", "Runs: " runCount)
        runCountCtrl.SetFont("s8")
        win.__cards.Push(runCountCtrl)
    }
    
    currentPath := item.path
    isFav := IsFavorite(currentPath)
favBtn := win.Add(
    "Button",
    "x" (x + w - 110)
    " y" (y + 20)  ; Adjust Y position slightly
    " w20 h20 Center Background" (isFav ? COLORS.favorite : COLORS.cardHover),
    isFav ? "★" : "✰"
)
favBtn.SetFont("s11", "Segoe UI Symbol")  ; Slightly larger font
favBtn.OnEvent("Click", (*) => ToggleFavoriteAndRefresh(win, currentPath))
win.__cards.Push(favBtn)

    
    ; Run button - top right
    runBtn := win.Add("Button", "x" (x + w - 90) " y" (y + 15) " w80 h30 Background" COLORS.success, "▶ Run")
    runBtn.SetFont("s10 bold")
    runBtn.OnEvent("Click", (*) => RunMacro(currentPath))
    win.__cards.Push(runBtn)
    
    ; Links button - moved to bottom right
    if (Trim(item.info.Links) != "") {
        currentLinks := item.info.Links
        linksBtn := win.Add("Button", "x" (x + w - 90) " y" (y + 83) " w80 h22 Background" COLORS.accentAlt, "🔗 Links")
        linksBtn.SetFont("s8")
        linksBtn.OnEvent("Click", (*) => OpenLinks(currentLinks))
        win.__cards.Push(linksBtn)
    }
}

ToggleFavoriteAndRefresh(win, macroPath) {
    ToggleFavorite(macroPath)
    
    winTitle := win.Title
    
    if RegExMatch(winTitle, "^(.+) - Macros$", &m) {
        category := m[1]
        win.Destroy()
        Sleep 100
        OpenCategory(category)
    } else {
        RenderCards(win)
    }
}

ChangePage(win, direction) {
    win.__currentPage := win.__currentPage + direction
    
    totalPages := Ceil(win.__data.Length / win.__itemsPerPage)
    
    if (win.__currentPage < 1)
        win.__currentPage := 1
    if (win.__currentPage > totalPages)
        win.__currentPage := totalPages
    
    RenderCards(win)
}

GetMacroIcon(macroPath) {
    global BASE_DIR, ICON_DIR
    
    try {
        SplitPath macroPath, , &macroDir
        SplitPath macroDir, &macroName
        
        extensions := ["png", "ico", "jpg", "jpeg"]
        
        for ext in extensions {
            iconPath := ICON_DIR "\" macroName "." ext
            if FileExist(iconPath)
                return iconPath
        }
        
        for ext in extensions {
            iconPath := macroDir "\icon." ext
            if FileExist(iconPath)
                return iconPath
        }
        
        SplitPath macroDir, , &gameDir
        for ext in extensions {
            iconPath := gameDir "\" macroName "." ext
            if FileExist(iconPath)
                return iconPath
        }
    }
    
    return ""
}

GetMacrosWithInfo(category, sortBy := "favorites") {
    global BASE_DIR
    out := []
    base := BASE_DIR "\" category
    
    if !DirExist(base)
        return out
    
    try {
        Loop Files, base "\*", "D" {
            subFolder := A_LoopFilePath
            mainFile := subFolder "\Main.ahk"
            
            if FileExist(mainFile) {
                try {
                    info := ReadMacroInfo(subFolder)
                    out.Push({
                        path: mainFile,
                        info: info
                    })
                }
            }
        }
    }
    
    if (out.Length = 0) {
        mainFile := base "\Main.ahk"
        if FileExist(mainFile) {
            try {
                info := ReadMacroInfo(base)
                out.Push({
                    path: mainFile,
                    info: info
                })
            }
        }
    }
    
    if (out.Length > 1) {
        switch sortBy {
            case "favorites":
                out := SortByFavorites(out)
            case "name_asc":
                out := SortByName(out, true)
            case "name_desc":
                out := SortByName(out, false)
            case "runs_desc":
                out := SortByRuns(out, false)
            case "runs_asc":
                out := SortByRuns(out, true)
            case "recent":
                out := SortByRecent(out)
            default:
                out := SortByFavorites(out)
        }
    }
    
    return out
}

SortByFavorites(macros) {
    favs := []
    nonFavs := []
    
    for item in macros {
        if IsFavorite(item.path)
            favs.Push(item)
        else
            nonFavs.Push(item)
    }
    
    sorted := []
    for item in favs
        sorted.Push(item)
    for item in nonFavs
        sorted.Push(item)
    
    return sorted
}

SortByName(macros, ascending := true) {
    if (macros.Length <= 1)
        return macros
    
    sorted := macros.Clone()
    
    Loop sorted.Length - 1 {
        i := A_Index
        Loop sorted.Length - i {
            j := A_Index + i
            
            ; Safely get titles with error handling
            titleI := ""
            titleJ := ""
            
            try {
                if IsObject(sorted[i]) && IsObject(sorted[i].info) && sorted[i].info.HasProp("Title")
                    titleI := sorted[i].info.Title
            }
            
            try {
                if IsObject(sorted[j]) && IsObject(sorted[j].info) && sorted[j].info.HasProp("Title")
                    titleJ := sorted[j].info.Title
            }
            
            if (titleI = "" || titleJ = "")
                continue
            
            ; Use StrCompare for string comparison
            comparison := StrCompare(StrLower(titleI), StrLower(titleJ))
            
            if ascending {
                if (comparison > 0) {
                    temp := sorted[i]
                    sorted[i] := sorted[j]
                    sorted[j] := temp
                }
            } else {
                if (comparison < 0) {
                    temp := sorted[i]
                    sorted[i] := sorted[j]
                    sorted[j] := temp
                }
            }
        }
    }
    
    return sorted
}

SortByRuns(macros, ascending := true) {
    if (macros.Length <= 1)
        return macros
    
    sorted := macros.Clone()
    
    Loop sorted.Length - 1 {
        i := A_Index
        Loop sorted.Length - i {
            j := A_Index + i
            
            runI := 0
            runJ := 0
            
            try {
                if IsObject(sorted[i]) && sorted[i].HasProp("path")
                    runI := GetRunCount(sorted[i].path)
            }
            
            try {
                if IsObject(sorted[j]) && sorted[j].HasProp("path")
                    runJ := GetRunCount(sorted[j].path)
            }
            
            if ascending {
                if (runI > runJ) {
                    temp := sorted[i]
                    sorted[i] := sorted[j]
                    sorted[j] := temp
                }
            } else {
                if (runI < runJ) {
                    temp := sorted[i]
                    sorted[i] := sorted[j]
                    sorted[j] := temp
                }
            }
        }
    }
    
    return sorted
}

SortByRecent(macros) {
    global favorites
    sorted := macros.Clone()
    
    Loop sorted.Length - 1 {
        i := A_Index
        Loop sorted.Length - i {
            j := A_Index + i
            
            keyI := GetMacroKey(sorted[i].path)
            keyJ := GetMacroKey(sorted[j].path)
            
            timeI := favorites.Has(keyI) ? favorites[keyI].addedAt : "0"
            timeJ := favorites.Has(keyJ) ? favorites[keyJ].addedAt : "0"
            
            if (timeI < timeJ) {
                temp := sorted[i]
                sorted[i] := sorted[j]
                sorted[j] := temp
            }
        }
    }
    
    return sorted
}

JsonLoad(jsonText) {
    static doc := ComObject("htmlfile")
    ; Ensure a window exists
    doc.write("<meta http-equiv='X-UA-Compatible' content='IE=9'>")
    return doc.parentWindow.JSON.parse(jsonText)
}

JsonDump(obj) {
    static doc := ComObject("htmlfile")
    doc.write("<meta http-equiv='X-UA-Compatible' content='IE=9'>")
    return doc.parentWindow.JSON.stringify(obj)
}

JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

ReadMacroInfo(macroDir) {
    info := {
        Title: "",
        Creator: "",
        Version: "",
        Links: ""
    }
    
    try {
        SplitPath macroDir, &folder
        info.Title := folder
    } catch {
        info.Title := "Unknown"
    }
    
    ini := macroDir "\info.ini"
    if !FileExist(ini)
        return info
    
    try {
        txt := FileRead(ini, "UTF-8")
    } catch {
        return info
    }
    
    for line in StrSplit(txt, "`n") {
        line := Trim(StrReplace(line, "`r"))
        
        if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
            continue
        
        if !InStr(line, "=")
            continue
        
        parts := StrSplit(line, "=", , 2)
        if (parts.Length < 2)
            continue
        
        k := StrLower(Trim(parts[1]))
        v := Trim(parts[2])
        
        switch k {
            case "title":
                if (v != "")
                    info.Title := v
            case "creator":
                info.Creator := v
            case "version":
                info.Version := v
            case "links":
                info.Links := v
        }
    }
    
    if (info.Version = "")
        info.Version := "1.0"
    if (info.Creator = "")
        info.Creator := "Unknown"
    
    return info
}

; 1. ADD THIS FUNCTION (from Public Release)
OnSetGlobalPassword(defaultUser, *) {
    pw := InputBox("Enter NEW universal password (this pushes to global manifest).", "V1LN clan - Set Global Password", "Password w560 h190")
    if (pw.Result != "OK")
        return

    newPass := Trim(pw.Value)
    if (newPass = "") {
        MsgBox "Password cannot be blank.", "V1LN clan - Invalid", "Icon! 0x30"
        return
    }

    h := HashPassword(newPass)
    body := '{"cred_user":"' defaultUser '","cred_hash":"' h '"}'

    try {
        WorkerPost("/cred/set", body)
        MsgBox "✅ Global password updated in manifest.`n`nNew cred_hash: " h, "V1LN clan", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to set global password:`n" err.Message, "V1LN clan", "Icon! 0x10"
    }
}

; 2. ADD THIS FUNCTION (from Public Release)
HashPassword(password) {
    salt := "V1LN_CLAN_2026_SECURE"
    combined := salt . password . salt
    
    hash := 0
    Loop Parse combined
        hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)
    
    Loop 10000 {
        hash := Mod(hash * 37 + Ord(SubStr(password, Mod(A_Index, StrLen(password)) + 1, 1)), 2147483647)
    }
    
    return hash
}

; 3. ADD THIS FUNCTION (from Public Release)
CopyManifestCredentialSnippet(username) {
    pw := InputBox(
        "Enter the NEW universal password.`n`nThis will copy cred_user + cred_hash for manifest.json.",
        "V1LN clan - Generate manifest snippet",
        "Password w560 h190"
    )
    if (pw.Result != "OK")
        return

    newPass := Trim(pw.Value)
    if (newPass = "") {
        MsgBox "Password cannot be blank.", "V1LN clan - Invalid", "Icon! 0x30"
        return
    }

    h := HashPassword(newPass)
    snippet := '"cred_user": "' username '",' "`n" '"cred_hash": "' h '"'
    A_Clipboard := snippet

    MsgBox "✅ Copied to clipboard.`n`nPaste into manifest.json:`n`n" snippet, "V1LN clan", "Iconi"
}

RunMacro(path) {
    if !FileExist(path) {
        MsgBox "Macro not found:`n" path, "Error", "Icon!"
        return
    }
    
    IncrementRunCount(path)
    
    try {
        SplitPath path, , &dir
        Run '"' A_AhkPath '" "' path '"', dir
    } catch as err {
        MsgBox "Failed to run macro: " err.Message, "Error", "Icon!"
    }
}

OpenLinks(links) {
    if !links || Trim(links) = ""
        return
    
    try {
        for url in StrSplit(links, "|") {
            url := Trim(url)
            if (url != "")
                SafeOpenURL(url)
        }
    } catch as err {
        MsgBox "Failed to open link: " err.Message, "Error", "Icon!"
    }
}

CompleteUninstall(*) {
    global APP_DIR, SECURE_VAULT, BASE_DIR, ICON_DIR, VERSION_FILE, MACHINE_KEY
    global CRED_FILE, SESSION_FILE, DISCORD_ID_FILE, DISCORD_BAN_FILE
    global ADMIN_DISCORD_FILE, SESSION_LOG_FILE, MACHINE_BAN_FILE
    global HWID_BINDING_FILE, LAST_CRED_HASH_FILE, SECURE_CONFIG_FILE
    global ENCRYPTED_KEY_FILE, MASTER_KEY_ROTATION_FILE
    
    choice := MsgBox(
        "⚠️ WARNING ⚠️`n`n"
        . "This will permanently delete:`n"
        . "• All downloaded macros`n"
        . "• All icons and resources`n"
        . "• All encrypted data`n"
        . "• Version information`n"
        . "• Security keys and vault data`n"
        . "• All login credentials and sessions`n"
        . "• Discord ID and ban records`n`n"
        . "This action CANNOT be undone!`n`n"
        . "Are you sure you want to completely uninstall?",
        "Complete Uninstall",
        "YesNo Icon! Default2"
    )
    
    if (choice = "No") {
        return
    }
    
    choice2 := MsgBox(
        "⚠️ FINAL WARNING ⚠️`n`n"
        . "This will permanently delete:`n"
        . "• All downloaded macros`n"
        . "• All encrypted files`n"
        . "• All icons and resources`n"
        . "• All version information`n"
        . "• Machine registration keys`n"
        . "• All authentication data`n"
        . "• All session history`n`n"
        . "This cannot be undone!`n`n"
        . "Are you ABSOLUTELY sure?",
        "Confirm Complete Removal",
        "YesNo Icon! Default2"
    )
    
    if (choice2 = "No")
        return
    
    try {
        ; Clear authentication files first
        try {
            if FileExist(CRED_FILE) {
                RunWait 'attrib -h -s -r "' CRED_FILE '"', , "Hide"
                FileDelete CRED_FILE
            }
        }
        
        try {
            if FileExist(SESSION_FILE) {
                RunWait 'attrib -h -s -r "' SESSION_FILE '"', , "Hide"
                FileDelete SESSION_FILE
            }
        }
        
        try {
            if FileExist(DISCORD_ID_FILE) {
                RunWait 'attrib -h -s -r "' DISCORD_ID_FILE '"', , "Hide"
                FileDelete DISCORD_ID_FILE
            }
        }
        
        try {
            if FileExist(DISCORD_BAN_FILE) {
                RunWait 'attrib -h -s -r "' DISCORD_BAN_FILE '"', , "Hide"
                FileDelete DISCORD_BAN_FILE
            }
        }
        
        try {
            if FileExist(ADMIN_DISCORD_FILE) {
                RunWait 'attrib -h -s -r "' ADMIN_DISCORD_FILE '"', , "Hide"
                FileDelete ADMIN_DISCORD_FILE
            }
        }
        
        try {
            if FileExist(SESSION_LOG_FILE) {
                RunWait 'attrib -h -s -r "' SESSION_LOG_FILE '"', , "Hide"
                FileDelete SESSION_LOG_FILE
            }
        }
        
        try {
            if FileExist(MACHINE_BAN_FILE) {
                RunWait 'attrib -h -s -r "' MACHINE_BAN_FILE '"', , "Hide"
                FileDelete MACHINE_BAN_FILE
            }
        }
        
        try {
            if FileExist(HWID_BINDING_FILE) {
                RunWait 'attrib -h -s -r "' HWID_BINDING_FILE '"', , "Hide"
                FileDelete HWID_BINDING_FILE
            }
        }
        
        try {
            if FileExist(LAST_CRED_HASH_FILE) {
                RunWait 'attrib -h -s -r "' LAST_CRED_HASH_FILE '"', , "Hide"
                FileDelete LAST_CRED_HASH_FILE
            }
        }
        
        try {
            if FileExist(SECURE_CONFIG_FILE) {
                RunWait 'attrib -h -s -r "' SECURE_CONFIG_FILE '"', , "Hide"
                FileDelete SECURE_CONFIG_FILE
            }
        }
        
        try {
            if FileExist(ENCRYPTED_KEY_FILE) {
                RunWait 'attrib -h -s -r "' ENCRYPTED_KEY_FILE '"', , "Hide"
                FileDelete ENCRYPTED_KEY_FILE
            }
        }
        
        try {
            if FileExist(MASTER_KEY_ROTATION_FILE) {
                RunWait 'attrib -h -s -r "' MASTER_KEY_ROTATION_FILE '"', , "Hide"
                FileDelete MASTER_KEY_ROTATION_FILE
            }
        }
        
        ; Remove version file
        if FileExist(VERSION_FILE) {
            RunWait 'attrib -h -s -r "' VERSION_FILE '"', , "Hide"
            FileDelete VERSION_FILE
        }
        
        ; Remove directories
        if DirExist(BASE_DIR) {
            RunWait 'attrib -h -s -r "' BASE_DIR '" /s /d', , "Hide"
            DirDelete BASE_DIR, true
        }
        
        if DirExist(ICON_DIR) {
            RunWait 'attrib -h -s -r "' ICON_DIR '" /s /d', , "Hide"
            DirDelete ICON_DIR, true
        }
        
        if DirExist(SECURE_VAULT) {
            RunWait 'attrib -h -s -r "' SECURE_VAULT '" /s /d', , "Hide"
            DirDelete SECURE_VAULT, true
        }
        
        if DirExist(APP_DIR) {
            RunWait 'attrib -h -s -r "' APP_DIR '"', , "Hide"
            DirDelete APP_DIR, true
        }
        
        ; Clear registry entries (machine key rotation data)
        regPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo"
        try RegDelete regPath, "MachineGUID"
        try RegDelete regPath, "KeyHistory"
        try RegDelete regPath, "LastRotation"
        
        ; Clear lockout file if exists
        try {
            if FileExist(A_Temp "\.lockout") {
                FileDelete A_Temp "\.lockout"
            }
        }
        
        MsgBox(
            "✅ Complete uninstall successful!`n`n"
            . "Removed:`n"
            . "• All macros and encrypted data`n"
            . "• All icons and resources`n"
            . "• All authentication files`n"
            . "• All session history`n"
            . "• All registry keys`n"
            . "• All ban records`n`n"
            . "The launcher will now close.",
            "Uninstall Complete",
            "Iconi"
        )
        
        ExitApp
        
    } catch as err {
        MsgBox(
            "❌ Failed to delete some files:`n`n"
            . err.Message "`n`n"
            . "Some files may require manual deletion.`n"
            . "Location: " SECURE_VAULT,
            "Uninstall Error",
            "Icon!"
        )
    }
}

ShowChangelog(*) {
    global MANIFEST_URL
    
    tmpManifest := A_Temp "\manifest.json"
    
    if !SafeDownload(MANIFEST_URL, tmpManifest) {
        MsgBox "Couldn't download manifest.json`n`nCheck your internet connection.", "Error", "Icon!"
        return
    }
    
    json := ""
    try {
        json := FileRead(tmpManifest, "UTF-8")
    } catch {
        MsgBox "Failed to read manifest file.", "Error", "Icon!"
        return
    }
    
    manifest := ParseManifest(json)
    if !manifest {
        MsgBox "Failed to parse manifest data.", "Error", "Icon!"
        return
    }
    
    text := ""
    if (manifest.changelog.Length > 0) {
        for line in manifest.changelog {
            text .= "• " line "`n"
        }
    }
    
    if (text = "")
        text := "(No changelog available)"
    
    MsgBox "Version: " manifest.version "`n`n" text, "Changelog", "Iconi"
}

; ========== HELPER FUNCTIONS ==========

TryDirMove(src, dst, overwrite := true, retries := 10) {
    loop retries {
        try {
            DirMove src, dst, overwrite ? 1 : 0
            return true
        } catch as err {
            Sleep 250
            if (A_Index = retries)
                throw Error("DirMove failed:`n" err.Message "`n`nFrom:`n" src "`nTo:`n" dst)
        }
    }
    return false
}

TryFileCopy(src, dst, overwrite := true, retries := 10) {
    loop retries {
        try {
            FileCopy src, dst, overwrite ? 1 : 0
            return true
        } catch as err {
            Sleep 250
            if (A_Index = retries)
                throw Error("FileCopy failed:`n" err.Message "`n`nFrom:`n" src "`nTo:`n" dst)
        }
    }
    return false
}

ShowUpdateFail(context, err, extra := "") {
    msg := "❌ Failed to install macro updates`n`n"
        . "Step: " context "`n"
        . "Error: " err.Message "`n`n"
        . "Extra: " extra "`n`n"
        . "A_LastError: " A_LastError "`n"
        . "A_WorkingDir: " A_WorkingDir "`n"
        . "AppData: " A_AppData

    MsgBox msg, "V1LN clan - Update Failed", "Icon! 0x10"
}

IsValidZip(path) {
    try {
        if !FileExist(path)
            return false
        if (FileGetSize(path) < 100)
            return false

        f := FileOpen(path, "r")
        sig := f.Read(2)
        f.Close()

        return (sig = "PK")
    } catch {
        return false
    }
}

; ========== ADMIN PANEL ==========

FetchMasterKeyFromManifest() {
    global MASTER_KEY, MANIFEST_URL
    
    try {
        tmp := A_Temp "\manifest_config.json"
        if SafeDownload(MANIFEST_URL, tmp, 20000) {
            json := FileRead(tmp, "UTF-8")
            if RegExMatch(json, '"master_key"\s*:\s*"([^"]+)"', &m) {
                MASTER_KEY := m[1]
                return true
            }
        }
    } catch {
    }
    
    if (MASTER_KEY = "") {
        MASTER_KEY := GenerateRandomKey(32)
        return false
    }
    
    return false
}

GenerateRandomKey(length := 32) {
    chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*"
    key := ""
    
    loop length {
        idx := Random(1, StrLen(chars))
        key .= SubStr(chars, idx, 1)
    }
    
    return key
}

WorkerPost(endpoint, bodyJson) {
    global WORKER_URL, MASTER_KEY

    if !IsSet(WORKER_URL) || (Trim(WORKER_URL) = "")
        throw Error("WORKER_URL is not set.")
    if !IsSet(MASTER_KEY) || (Trim(MASTER_KEY) = "")
        throw Error("MASTER_KEY is not set.")

    url := RTrim(WORKER_URL, "/") "/" LTrim(endpoint, "/")

    req := ComObject("WinHttp.WinHttpRequest.5.1")

    ; IMPORTANT: Do NOT set req.Option[6] unless you know the correct protocol bitmask.
    ; req.Option[6] := 1 breaks TLS on many systems.

    ; timeouts: resolve, connect, send, receive (ms)
    req.SetTimeouts(15000, 15000, 15000, 15000)

    req.Open("POST", url, false)
    req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
    req.SetRequestHeader("Accept", "application/json")
    req.SetRequestHeader("X-Master-Key", MASTER_KEY)
    req.SetRequestHeader("User-Agent", "v1ln-clan")

    ; Send body
    req.Send(bodyJson)

    status := 0
    resp := ""
    try status := req.Status
    try resp := req.ResponseText

    if (status < 200 || status >= 300) {
        ; include response body for debugging Worker errors
        throw Error("Worker error " status ": " resp)
    }
    return resp
}

GetLinesFromFile(path) {
    arr := []
    if !FileExist(path)
        return arr
    try {
        txt := FileRead(path, "UTF-8")
        for line in StrSplit(txt, "`n", "`r") {
            line := Trim(line)
            if (line != "")
                arr.Push(line)
        }
    } catch {
    }
    return arr
}

WriteLinesToFile(path, arr) {
    out := ""
    for x in arr
        out .= Trim(x) "`n"
    try {
        if FileExist(path)
            FileDelete path
        if (Trim(out) != "")
            FileAppend out, path
    } catch {
    }
}

ResyncListsFromManifestNow() {
    global MANIFEST_URL, DISCORD_BAN_FILE, ADMIN_DISCORD_FILE, HWID_BAN_FILE
    
    tmp := A_Temp "\manifest_live.json"
    
    if !SafeDownload(NoCacheUrl(MANIFEST_URL), tmp, 20000)
        throw Error("Failed to download manifest from server.")
    
    json := FileRead(tmp, "UTF-8")
    lists := ParseManifestLists(json)
    
    if !IsObject(lists)
        throw Error("Failed to parse manifest lists.")
    
    OverwriteListFile(DISCORD_BAN_FILE, lists.banned)
    OverwriteListFile(ADMIN_DISCORD_FILE, lists.admins)
    OverwriteListFile(HWID_BAN_FILE, lists.banned_hwids)
    
    return lists
}

ParseManifestLists(json) {
    obj := { banned: [], admins: [], banned_hwids: [] }

    ; banned_discord_ids
    if RegExMatch(json, '(?s)"banned_discord_ids"\s*:\s*\[(.*?)\]', &m1) {
        inner := m1[1]
        pos := 1
        while (pos := RegExMatch(inner, '"(\d{6,30})"', &mItem, pos)) {
            obj.banned.Push(mItem[1])
            pos += StrLen(mItem[0])
        }
    }

    ; admin_discord_ids
    if RegExMatch(json, '(?s)"admin_discord_ids"\s*:\s*\[(.*?)\]', &m2) {
        inner := m2[1]
        pos := 1
        while (pos := RegExMatch(inner, '"(\d{6,30})"', &mItem2, pos)) {
            obj.admins.Push(mItem2[1])
            pos += StrLen(mItem2[0])
        }
    }

    ; banned_hwids
    if RegExMatch(json, '(?s)"banned_hwids"\s*:\s*\[(.*?)\]', &m3) {
        inner := m3[1]
        pos := 1
        while (pos := RegExMatch(inner, '"([^"]+)"', &mItem3, pos)) {
            v := Trim(mItem3[1])
            if (v != "")
                obj.banned_hwids.Push(v)
            pos += StrLen(mItem3[0])
        }
    }

    return obj
}

OverwriteListFile(filePath, arr) {
    try {
        if (arr.Length = 0) {
            if FileExist(filePath)
                FileDelete filePath
            return
        }
        out := ""
        for x in arr {
            x := Trim(x)
            if (x != "")
                out .= x "`n"
        }
        if FileExist(filePath)
            FileDelete filePath
        FileAppend out, filePath
    } catch {
    }
}

AdminPanel(*) {
    global MASTER_KEY, COLORS, DISCORD_BAN_FILE, ADMIN_DISCORD_FILE
    
    FetchMasterKeyFromManifest()
    
    ib := InputBox("Enter MASTER KEY to open Admin Panel:", "V1LN clan - Admin Panel", "Password w460 h170")
    if (ib.Result != "OK")
        return
    if (Trim(ib.Value) != MASTER_KEY) {
        MsgBox "❌ Invalid master key.", "V1LN clan - Access Denied", "Icon! 0x10"
        return
    }
    
    adminGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "V1LN clan - Admin Panel")
    adminGui.BackColor := COLORS.bg
    adminGui.SetFont("s9 c" COLORS.text, "Segoe UI")
    
    adminGui.Add("Text", "x0 y0 w900 h70 Background" COLORS.accent)
    adminGui.Add("Text", "x20 y20 w860 h30 c" COLORS.text " BackgroundTrans", "Admin Panel").SetFont("s18 bold")
    
    ; ===== LOGIN LOG =====
    adminGui.Add("Text", "x10 y85 w880 c" COLORS.textDim, "✅ Login Log (successful logins)")
    lv := adminGui.Add("ListView"
        , "x10 y105 w880 h210 Background" COLORS.card " c" COLORS.text
        , ["Time", "PC Name", "Discord ID", "Role", "HWID"])
    LoadGlobalSessionLogIntoListView(lv, 200)

    adminGui.Add("Text", "x10 y325 w880 h1 Background" COLORS.border)
    
    ; ===== DISCORD BAN =====
    adminGui.Add("Text", "x10 y335 w880 c" COLORS.textDim, "🔒 Global Ban Management")
    
    adminGui.Add("Text", "x10 y360 w120 c" COLORS.text, "Discord ID:")
    banEdit := adminGui.Add("Edit", "x130 y356 w370 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    banBtn := adminGui.Add("Button", "x520 y356 w110 h28 Background" COLORS.danger, "BAN")
    unbanBtn := adminGui.Add("Button", "x640 y356 w110 h28 Background" COLORS.success, "UNBAN")
    
    bannedLbl := adminGui.Add("Text", "x10 y390 w880 c" COLORS.textDim, "")
    RefreshBannedFromServer(bannedLbl)
    
    ; ===== HWID BAN =====
adminGui.Add("Text", "x10 y420 w120 c" COLORS.text, "HWID:")
hwidEdit := adminGui.Add("Edit", "x130 y416 w370 h28 Background" COLORS.bgLight " c" COLORS.text)

; Initialize with current machine's HWID
try {
    currentHwid := GetHardwareId()
    if (currentHwid != "")
        hwidEdit.Value := currentHwid
} catch {
    ; Silent fail - user can enter manually
}

banHwidBtn := adminGui.Add("Button", "x520 y416 w110 h28 Background" COLORS.danger, "BAN HWID")
unbanHwidBtn := adminGui.Add("Button", "x640 y416 w110 h28 Background" COLORS.success, "UNBAN HWID")
    
    bannedHwidLbl := adminGui.Add("Text", "x10 y450 w880 c" COLORS.textDim, "")
    try RefreshBannedHwidLabel(bannedHwidLbl)
    
    adminGui.Add("Text", "x10 y480 w880 h1 Background" COLORS.border)
    
    ; ===== ADMIN IDS =====
    adminGui.Add("Text", "x10 y490 w880 c" COLORS.textDim, "🛡️ Admin Discord IDs")
    
    adminGui.Add("Text", "x10 y515 w120 c" COLORS.text, "Admin ID:")
    adminEdit := adminGui.Add("Edit", "x130 y511 w370 h28 Background" COLORS.bgLight " c" COLORS.text)
    
    addAdminBtn := adminGui.Add("Button", "x520 y511 w110 h28 Background" COLORS.accentAlt, "Add")
    delAdminBtn := adminGui.Add("Button", "x640 y511 w110 h28 Background" COLORS.danger, "Remove")
    
    adminLbl := adminGui.Add("Text", "x10 y545 w880 c" COLORS.textDim, "")
    RefreshAdminDiscordLabel(adminLbl)
    
    adminGui.Add("Text", "x10 y575 w880 h1 Background" COLORS.border)
    
    ; ===== BUTTONS =====
    refreshBtn := adminGui.Add("Button", "x10 y590 w130 h34 Background" COLORS.card, "Refresh Log")
    clearLogBtn := adminGui.Add("Button", "x150 y590 w130 h34 Background" COLORS.card, "Clear Log")
    setPassBtn := adminGui.Add("Button", "x290 y590 w190 h34 Background" COLORS.accentAlt, "Set Global Password")
    copySnippetBtn := adminGui.Add("Button", "x490 y590 w190 h34 Background" COLORS.card, "Copy Manifest Snippet")
    
    ; ===== EVENTS =====
    banBtn.OnEvent("Click", OnBanDiscordId.Bind(banEdit, bannedLbl))
    unbanBtn.OnEvent("Click", OnUnbanDiscordId.Bind(banEdit, bannedLbl))
    
    banHwidBtn.OnEvent("Click", OnBanHwid.Bind(hwidEdit, bannedHwidLbl))
    unbanHwidBtn.OnEvent("Click", OnUnbanHwid.Bind(hwidEdit, bannedHwidLbl))
    
    addAdminBtn.OnEvent("Click", OnAddAdminDiscord.Bind(adminEdit, adminLbl))
    delAdminBtn.OnEvent("Click", OnRemoveAdminDiscord.Bind(adminEdit, adminLbl))
    
    refreshBtn.OnEvent("Click", (*) => LoadGlobalSessionLogIntoListView(lv, 200))
    clearLogBtn.OnEvent("Click", OnClearLog.Bind(lv))
    
    adminGui.OnEvent("Close", (*) => adminGui.Destroy())
    adminGui.Show("w900 h640 Center")

    setPassBtn.OnEvent("Click", OnSetGlobalPassword.Bind(DEFAULT_USER))
    copySnippetBtn.OnEvent("Click", OnCopySnippet.Bind(DEFAULT_USER))
}

OnCopySnippet(defaultUser, *) {
    CopyManifestCredentialSnippet(defaultUser)
}

OnClearLog(lv, *) {
    try {
        WorkerPost("/logs/clear", "{}")
        LoadGlobalSessionLogIntoListView(lv, 200)
        MsgBox "✅ Global login log cleared.", "V1LN clan - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Clear failed:`n" err.Message, "V1LN clan - Admin", "Icon!"
    }
}

OnBanDiscordId(banEdit, bannedLbl, *) {
    did := Trim(banEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "V1LN clan - Admin", "Icon!"
        return
    }

    try {
        WorkerPost("/ban", '{"discord_id":"' did '"}')
        AddBannedDiscordId(did)
        RefreshBannedFromServer(bannedLbl)
        MsgBox "✅ Globally BANNED: " did, "V1LN clan - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to ban globally:`n" err.Message, "V1LN clan - Admin", "Icon!"
    }
}

OnUnbanDiscordId(banEdit, bannedLbl, *) {
    did := Trim(banEdit.Value)
    did := RegExReplace(did, "[^\d]", "")

    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "V1LN clan - Admin", "Icon!"
        return
    }

    try {
        WorkerPost("/unban", '{"discord_id":"' did '"}')

        stillThere := true
        lists := 0

        Loop 6 {
            Sleep 700
            lists := ResyncListsFromManifestNow()
            RefreshBannedFromServer(bannedLbl)

            stillThere := false
            for x in lists.banned {
                if (Trim(x) = did) {
                    stillThere := true
                    break
                }
            }

            if !stillThere
                break
        }

        if stillThere {
            MsgBox "⚠️ Unban request sent, but ID is STILL in global manifest (GitHub may be caching/lagging).`n`nID: " did, "V1LN clan - Admin", "Icon! 0x30"
        } else {
            MsgBox "✅ Globally UNBANNED: " did, "V1LN clan - Admin", "Iconi"
        }
    } catch as err {
        MsgBox "❌ Failed to unban globally:`n" err.Message, "V1LN clan - Admin", "Icon!"
    }
}

OnAddAdminDiscord(adminEdit, adminLbl, *) {
    did := Trim(adminEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "V1LN clan - Admin", "Icon!"
        return
    }

    try {
        WorkerPost("/admin/add", '{"discord_id":"' did '"}')
        AddAdminDiscordId(did)
        RefreshAdminDiscordLabel(adminLbl)
        MsgBox "✅ Globally added admin: " did, "V1LN clan - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to add admin globally:`n" err.Message, "V1LN clan - Admin", "Icon!"
    }
}

OnRemoveAdminDiscord(adminEdit, adminLbl, *) {
    did := Trim(adminEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "V1LN clan - Admin", "Icon!"
        return
    }

    try {
        WorkerPost("/admin/remove", '{"discord_id":"' did '"}')
        RemoveAdminDiscordId(did)
        RefreshAdminDiscordLabel(adminLbl)
        MsgBox "✅ Globally removed admin: " did, "V1LN clan - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to remove admin globally:`n" err.Message, "V1LN clan - Admin", "Icon!"
    }
}

AddBannedDiscordId(did) {
    global DISCORD_BAN_FILE
    did := StrLower(Trim(did))
    if (did = "" || !RegExMatch(did, "^\d{6,30}$"))
        return
    ids := GetLinesFromFile(DISCORD_BAN_FILE)
    for x in ids
        if (StrLower(Trim(x)) = did)
            return
    ids.Push(did)
    WriteLinesToFile(DISCORD_BAN_FILE, ids)
}

RemoveBannedDiscordId(did) {
    global DISCORD_BAN_FILE
    did := StrLower(Trim(did))
    if (did = "")
        return
    ids := []
    for x in GetLinesFromFile(DISCORD_BAN_FILE) {
        if (StrLower(Trim(x)) != did)
            ids.Push(x)
    }
    WriteLinesToFile(DISCORD_BAN_FILE, ids)
}

RefreshBannedDiscordLabel(lblCtrl) {
    global DISCORD_BAN_FILE
    ids := GetLinesFromFile(DISCORD_BAN_FILE)
    if (ids.Length = 0) {
        lblCtrl.Value := "Banned Discord IDs: (none)"
        return
    }
    s := "Banned Discord IDs: "
    for id in ids
        s .= id ", "
    lblCtrl.Value := RTrim(s, ", ")
}

RefreshBannedFromServer(lblCtrl) {
    global MANIFEST_URL, DISCORD_BAN_FILE
    
    tmp := A_Temp "\manifest_live.json"
    
    if !SafeDownload(NoCacheUrl(MANIFEST_URL), tmp, 20000) {
        lblCtrl.Value := "Banned Discord IDs: (sync failed)"
        return false
    }
    
    try
        json := FileRead(tmp, "UTF-8")
    catch {
        lblCtrl.Value := "Banned Discord IDs: (sync failed)"
        return false
    }
    
    lists := ParseManifestLists(json)
    if !IsObject(lists) {
        lblCtrl.Value := "Banned Discord IDs: (sync failed)"
        return false
    }
    
    OverwriteListFile(DISCORD_BAN_FILE, lists.banned)
    
    if (lists.banned.Length = 0) {
        lblCtrl.Value := "Banned Discord IDs: (none)"
        return true
    }
    
    s := "Banned Discord IDs: "
    for id in lists.banned
        s .= id ", "
    lblCtrl.Value := RTrim(s, ", ")
    
    return true
}

AddAdminDiscordId(did) {
    global ADMIN_DISCORD_FILE
    did := StrLower(Trim(did))
    if (did = "" || !RegExMatch(did, "^\d{6,30}$"))
        return
    ids := GetLinesFromFile(ADMIN_DISCORD_FILE)
    for x in ids
        if (StrLower(Trim(x)) = did)
            return
    ids.Push(did)
    WriteLinesToFile(ADMIN_DISCORD_FILE, ids)
}

RemoveAdminDiscordId(did) {
    global ADMIN_DISCORD_FILE
    did := StrLower(Trim(did))
    if (did = "")
        return
    ids := []
    for x in GetLinesFromFile(ADMIN_DISCORD_FILE) {
        if (StrLower(Trim(x)) != did)
            ids.Push(x)
    }
    WriteLinesToFile(ADMIN_DISCORD_FILE, ids)
}

RefreshAdminDiscordLabel(lblCtrl) {
    global ADMIN_DISCORD_FILE
    ids := GetLinesFromFile(ADMIN_DISCORD_FILE)
    if (ids.Length = 0) {
        lblCtrl.Value := "Admin Discord IDs: (none)"
        return
    }
    s := "Admin Discord IDs: "
    for id in ids
        s .= id ", "
    lblCtrl.Value := RTrim(s, ", ")
}

AddBannedHwid(hwid) {
    global HWID_BAN_FILE
    hwid := Trim(hwid)
    if (hwid = "")
        return
    ids := GetLinesFromFile(HWID_BAN_FILE)
    for x in ids
        if (Trim(x) = hwid)
            return
    ids.Push(hwid)
    WriteLinesToFile(HWID_BAN_FILE, ids)
}

RemoveBannedHwid(hwid) {
    global HWID_BAN_FILE
    ids := []
    for x in GetLinesFromFile(HWID_BAN_FILE)
        if (Trim(x) != Trim(hwid))
            ids.Push(x)
    WriteLinesToFile(HWID_BAN_FILE, ids)
}

IsHwidBanned() {
    global HWID_BAN_FILE
    if !FileExist(HWID_BAN_FILE)
        return false
    hwid := GetHardwareId()
    for x in GetLinesFromFile(HWID_BAN_FILE)
        if (Trim(x) = hwid)
            return true
    return false
}

RefreshBannedHwidLabel(lblCtrl) {
    global HWID_BAN_FILE

    try ResyncListsFromManifestNow()
    catch

    ids := GetLinesFromFile(HWID_BAN_FILE)
    if (ids.Length = 0) {
        lblCtrl.Value := "Banned HWIDs: (none)"
        return
    }

    s := "Banned HWIDs: "
    for id in ids
        s .= id ", "
    lblCtrl.Value := RTrim(s, ", ")
}

OnBanHwid(hwidEdit, bannedHwidLbl, *) {
    ; Get the value from the edit control
    hwidValue := ""
    try {
        hwidValue := hwidEdit.Value
    } catch {
        MsgBox "Failed to read HWID from edit control.", "V1LN clan - Admin", "Icon!"
        return
    }
    
    ; Clean and validate the HWID
    hwid := Trim(hwidValue)
    hwid := RegExReplace(hwid, "[^\d]", "")
    
    if (hwid = "") {
        MsgBox "Enter a valid HWID (numbers only).", "V1LN clan - Admin", "Icon!"
        return
    }
    
    try {
        body := '{"hwid":"' JsonEscape(hwid) '"}'
        resp := WorkerPost("/ban-hwid", body)
        
        ; Resync and refresh display
        try ResyncListsFromManifestNow()
        catch
        
        RefreshBannedHwidLabel(bannedHwidLbl)
        MsgBox "✅ Globally BANNED HWID: " hwid, "V1LN clan - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to ban HWID globally:`n" err.Message, "V1LN clan - Admin", "Icon!"
    }
}

OnUnbanHwid(hwidEdit, bannedHwidLbl, *) {
    ; Get the value from the edit control
    hwidValue := ""
    try {
        hwidValue := hwidEdit.Value
    } catch {
        MsgBox "Failed to read HWID from edit control.", "V1LN clan - Admin", "Icon!"
        return
    }
    
    ; Clean and validate the HWID
    hwid := Trim(hwidValue)
    hwid := RegExReplace(hwid, "[^\d]", "")
    
    if (hwid = "") {
        MsgBox "Enter a valid HWID (numbers only).", "V1LN clan - Admin", "Icon!"
        return
    }
    
    try {
        body := '{"hwid":"' JsonEscape(hwid) '"}'
        resp := WorkerPost("/unban-hwid", body)
        
        ; Resync and refresh display
        try ResyncListsFromManifestNow()
        catch
        
        RefreshBannedHwidLabel(bannedHwidLbl)
        MsgBox "✅ Globally UNBANNED HWID: " hwid, "V1LN clan - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to unban HWID globally:`n" err.Message, "V1LN clan - Admin", "Icon!"
    }
}

GetHardwareId() {
    hwid := ""
    
    ; Get Processor ID
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for proc in objWMI.ExecQuery("SELECT ProcessorId FROM Win32_Processor") {
            if (proc.ProcessorId != "" && proc.ProcessorId != "None") {
                hwid .= proc.ProcessorId
            }
            break
        }
    } catch {
        ; Silent fail, continue to next method
    }
    
    ; Get Motherboard Serial Number
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for board in objWMI.ExecQuery("SELECT SerialNumber FROM Win32_BaseBoard") {
            if (board.SerialNumber != "" && board.SerialNumber != "None") {
                hwid .= board.SerialNumber
            }
            break
        }
    } catch {
        ; Silent fail, continue to next method
    }
    
    ; Get BIOS Serial Number
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for bios in objWMI.ExecQuery("SELECT SerialNumber FROM Win32_BIOS") {
            if (bios.SerialNumber != "" && bios.SerialNumber != "None") {
                hwid .= bios.SerialNumber
            }
            break
        }
    } catch {
        ; Silent fail, continue to next method
    }
    
    ; Get Volume Serial Number (C: drive)
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for disk in objWMI.ExecQuery("SELECT VolumeSerialNumber FROM Win32_LogicalDisk WHERE DeviceID='C:'") {
            if (disk.VolumeSerialNumber != "" && disk.VolumeSerialNumber != "None") {
                hwid .= disk.VolumeSerialNumber
            }
            break
        }
    } catch {
        ; Silent fail, continue to next method
    }
    
    ; Fallback: Use computer name and username if no hardware info found
    if (hwid = "") {
        hwid := A_ComputerName . A_UserName
    }
    
    ; Hash the combined hardware ID to create a unique numeric identifier
    hash := 0
    loop parse hwid {
        hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)
    }
    
    ; Return as string to ensure compatibility
    return String(hash)
}

NoCacheUrl(url) {
    ; Add cache-busting parameter to prevent browser/system caching
    separator := InStr(url, "?") ? "&" : "?"
    return url . separator . "nocache=" . A_TickCount
}

SendGlobalLoginLog(role, loginUser) {
    did := Trim(ReadDiscordId())
    hwid := Trim(GetHardwareId())
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    pc := A_ComputerName
    user := A_UserName

    if (did = "" || hwid = "")
        return

    body := '{"time":"' JsonEscape(ts) '",'
          . '"discord_id":"' JsonEscape(did) '",'
          . '"hwid":"' JsonEscape(hwid) '",'
          . '"pc":"' JsonEscape(pc) '",'
          . '"user":"' JsonEscape(user) '",'
          . '"role":"' JsonEscape(role) '",'
          . '"login_user":"' JsonEscape(loginUser) '"}'

    try {
        resp := WorkerPostPublic("/log", body)
    } catch as err {
        ; Silent fail - logging shouldn't block app
    }
}

LoadGlobalSessionLogIntoListView(lv, limit := 200) {
    lv.Delete()

    resp := ""
    try {
        resp := WorkerPost("/logs/get", '{"limit":' limit '}')
    } catch as err {
        return
    }

    if !RegExMatch(resp, '(?s)"logs"\s*:\s*\[(.*)\]\s*}', &m)
        return

    logsBlock := m[1]
    pos := 1
    
    ; Track unique entries: "discordId|hwid" as key
    seen := Map()

    while (p := RegExMatch(logsBlock, '(?s)\{.*?\}', &mm, pos)) {
        one := mm[0]
        pos := p + StrLen(one)

        t    := JsonExtractAny(one, "t")
        pc   := JsonExtractAny(one, "pc")
        did  := JsonExtractAny(one, "discordId")
        role := JsonExtractAny(one, "role")
        hwid := JsonExtractAny(one, "hwid")
        
        ; Create unique key from discord ID and HWID
        uniqueKey := did "|" hwid
        
        ; Skip if we've already seen this combination
        if seen.Has(uniqueKey)
            continue
        
        seen[uniqueKey] := true
        lv.Add("", t, pc, did, role, hwid)
    }
    
    ; Auto-size columns to fit content
    Loop 5
        lv.ModifyCol(A_Index, "AutoHdr")
}

JsonExtractAny(json, key) {
    ; Handles "key":"value" OR "key":123 OR "key":true
    pat1 := '(?s)"' key '"\s*:\s*"((?:\\.|[^"\\])*)"'
    if RegExMatch(json, pat1, &m1) {
        v := m1[1]
        v := StrReplace(v, '\"', '"')
        v := StrReplace(v, "\\n", "`n")
        v := StrReplace(v, "\\r", "`r")
        v := StrReplace(v, "\\t", "`t")
        v := StrReplace(v, "\\", "\")
        return v
    }

    pat2 := '(?s)"' key '"\s*:\s*([^,\}\]]+)'
    if RegExMatch(json, pat2, &m2) {
        return Trim(m2[1], " `t`r`n")
    }

    return ""
}

WorkerPostPublic(endpoint, bodyJson) {
    global WORKER_URL

    url := RTrim(WORKER_URL, "/") "/" LTrim(endpoint, "/")

    req := ComObject("WinHttp.WinHttpRequest.5.1")
    
    ; DO NOT set req.Option[6] - it breaks TLS on many systems
    ; timeouts: resolve, connect, send, receive (ms)
    req.SetTimeouts(15000, 15000, 15000, 15000)

    req.Open("POST", url, false)
    req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
    req.SetRequestHeader("Accept", "application/json")
    req.SetRequestHeader("User-Agent", "AHK-Vault")

    req.Send(bodyJson)

    status := 0
    resp := ""
    try status := req.Status
    try resp := req.ResponseText

    if (status < 200 || status >= 300)
        throw Error("Worker error " status ": " resp)

    return resp
}

ReadDiscordId() {
    global DISCORD_ID_FILE
    try if FileExist(DISCORD_ID_FILE)
        return Trim(FileRead(DISCORD_ID_FILE, "UTF-8"))
    return ""
}