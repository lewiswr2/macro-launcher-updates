#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

global LAUNCHER_VERSION := "1.0.2"

global WORKER_URL := "https://tight-dust-10d2.lewisjenkins558.workers.dev/"
global DISCORD_URL := "https://discord.gg/V1ln"
global WEBHOOK_URL := ""
global APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content"
MACHINE_KEY := GetOrCreatePersistentKey()
dirHash := HashString(MACHINE_KEY . A_ComputerName)
APP_DIR_BASE := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content\{" SubStr(dirHash, 1, 8) "}"
SECURE_VAULT := APP_DIR_BASE "\{" SubStr(dirHash, 9, 8) "}"
global SESSION_TOKEN_FILE := SECURE_VAULT "\.session_token"
global VERSION_FILE := SECURE_VAULT "\ver"
global ICON_DIR := SECURE_VAULT "\res"
global MANIFEST_URL := DecryptManifestUrl()
global mainGui := 0
global MACHINE_KEY := ""
global DISCORD_ID_FILE := ""
global RATINGS_CACHE := Map()

; ================= NEW: ENHANCED FEATURES =================
global PROFILE_ENABLED := true
global ANALYTICS_ENABLED := true
global CATEGORIES_ENABLED := true
global USER_PROFILE := Map()
global USERNAME_FILE := ""

global COLORS := {
    bg: "0x0a0e14",
    bgLight: "0x13171d",
    card: "0x161b22",
    cardHover: "0x1c2128",
    accent: "0xd29922",
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

; =========================================
InitializeSecureVault()
SetTaskbarIcon()
LoadStats()
LoadFavorities()
CheckForUpdatesPrompt()
CreateMainGui()

; NEW: Load user profile on startup
try {
    LoadUserProfile()
} catch as err {
    ; Silent fail - profile loading is optional
}

CreateGUID() {
    guid := ""
    loop 32 {
        guid .= Format("{:X}", Random(0, 15))
        if (A_Index = 8 || A_Index = 12 || A_Index = 16 || A_Index = 20)
            guid .= "-"
    }
    return guid
}

SetTaskbarIcon() {
    global ICON_DIR
    iconPath := ICON_DIR "\Launcher.png"
    
    try {
        if FileExist(iconPath)
            TraySetIcon(iconPath)
        else
            TraySetIcon("shell32.dll", 3)
    } catch {
    }
}

; ========== INITIALIZATION ==========
InitializeSecureVault() {
    global APP_DIR, SECURE_VAULT, BASE_DIR, ICON_DIR, VERSION_FILE, MACHINE_KEY
    global STATS_FILE, FAVORITES_FILE, MANIFEST_URL, SESSION_TOKEN_FILE, DISCORD_ID_FILE
    
    MACHINE_KEY := GetOrCreatePersistentKey()
    dirHash := HashString(MACHINE_KEY . A_ComputerName)
    APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content\{" SubStr(dirHash, 1, 8) "}"
    SECURE_VAULT := APP_DIR "\{" SubStr(dirHash, 9, 8) "}"
    BASE_DIR := SECURE_VAULT "\dat"
    ICON_DIR := SECURE_VAULT "\res"
    VERSION_FILE := SECURE_VAULT "\~ver.tmp"
    STATS_FILE := SECURE_VAULT "\stats.json"
    FAVORITES_FILE := SECURE_VAULT "\favorites.json"
    DISCORD_ID_FILE := SECURE_VAULT "\discord_id.txt"
    SESSION_TOKEN_FILE := SECURE_VAULT "\.session_token"
    USERNAME_FILE := SECURE_VAULT "\username.txt"
    MANIFEST_URL := DecryptManifestUrl()
    LoadWebhookUrl()
    try {
        DirCreate APP_DIR
        DirCreate SECURE_VAULT
        DirCreate BASE_DIR
        DirCreate ICON_DIR
    } catch as err {
        MsgBox "Failed to create application directories: " err.Message, "Initialization Error", "Icon!"
    }

    SendLaunchNotification()
    EnsureVersionFile()
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

ReadUsername() {
       global USERNAME_FILE
       try {
           if FileExist(USERNAME_FILE)
               return Trim(FileRead(USERNAME_FILE, "UTF-8"))
       }
       return "Unknown User"
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

; ========== WEBHOOK FUNCTIONS ==========

LoadWebhookUrl() {
    global WEBHOOK_URL, MANIFEST_URL
    
    try {
        tmpManifest := A_Temp "\manifest_webhook.json"
        
        if SafeDownload(MANIFEST_URL, tmpManifest, 10000) {
            json := FileRead(tmpManifest, "UTF-8")
            
            if RegExMatch(json, '"webhook_url"\s*:\s*"([^"]+)"', &m) {
                WEBHOOK_URL := Trim(m[1])
            }
            
            try FileDelete tmpManifest
        }
    } catch {
        ; Silent fail - webhooks are optional
    }
}

SendWebhook(title, description, color := 3447003, fields := "") {
    global WEBHOOK_URL
    
    if (WEBHOOK_URL = "")
        return false
    
    try {
        timestamp := FormatTime(, "yyyy-MM-ddTHH:mm:ssZ")
        
        ; Build embed JSON
        embed := '{"embeds":[{"title":"' JsonEscape(title) '","description":"' JsonEscape(description) '","color":' color ',"timestamp":"' timestamp '"'
        
        ; Add fields if provided
        if (fields != "") {
            embed .= ',"fields":[' fields ']'
        }
        
        embed .= ',"footer":{"text":"AHK Vault Macro Launcher"}}]}'
        
        ; Send webhook
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(3000, 3000, 3000, 3000)
        req.Open("POST", WEBHOOK_URL, false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(embed)
        
        return true
    } catch {
        return false
    }
}

SendLaunchNotification() {
    computerName := A_ComputerName
    userName := A_UserName
    discordId := ReadDiscordId()
    hwid := GetHardwareId()
    
    fields := '{"name":"Computer","value":"' computerName '","inline":true},'
            . '{"name":"User","value":"' userName '","inline":true},'
            . '{"name":"Version","value":"' LAUNCHER_VERSION '","inline":true},'
            . '{"name":"Discord ID","value":"' discordId '","inline":true},'
            . '{"name":"HWID","value":"' hwid '","inline":true}'
    
    SendWebhook("🚀 Launcher Started", "AHK Vault macro launcher was opened", 3066993, fields)
}

ReadDiscordId() {
    global DISCORD_ID_FILE
    try {
        if FileExist(DISCORD_ID_FILE)
            return Trim(FileRead(DISCORD_ID_FILE, "UTF-8"))
    }
    return "Unknown"
}

GetHardwareId() {
    hwid := ""
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for proc in objWMI.ExecQuery("SELECT ProcessorId FROM Win32_Processor") {
            if (proc.ProcessorId != "" && proc.ProcessorId != "None") {
                hwid .= proc.ProcessorId
            }
            break
        }
    } catch {
    }
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for board in objWMI.ExecQuery("SELECT SerialNumber FROM Win32_BaseBoard") {
            if (board.SerialNumber != "" && board.SerialNumber != "None") {
                hwid .= board.SerialNumber
            }
            break
        }
    } catch {
    }
    
    if (hwid = "")
        hwid := A_ComputerName . A_UserName
    
    hash := 0
    loop parse hwid
        hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)
    
    return String(hash)
}

SendMacroRunNotification(macroName, macroPath) {
    computerName := A_ComputerName
    userName := A_UserName
    
    fields := '{"name":"Macro","value":"' JsonEscape(macroName) '","inline":false},'
            . '{"name":"Computer","value":"' computerName '","inline":true},'
            . '{"name":"User","value":"' userName '","inline":true}'
    
    SendWebhook("▶️ Macro Executed", "A macro was run", 5763719, fields)
}

SendUpdateNotification(oldVersion, newVersion) {
    computerName := A_ComputerName
    
    fields := '{"name":"Old Version","value":"' oldVersion '","inline":true},'
            . '{"name":"New Version","value":"' newVersion '","inline":true},'
            . '{"name":"Computer","value":"' computerName '","inline":true}'
    
    SendWebhook("📦 Update Installed", "Macros were updated", 15844367, fields)
}

SendUninstallNotification() {
    computerName := A_ComputerName
    userName := A_UserName
    
    fields := '{"name":"Computer","value":"' computerName '","inline":true},'
            . '{"name":"User","value":"' userName '","inline":true}'
    
    SendWebhook("🗑️ Uninstall", "AHK Vault was uninstalled", 15158332, fields)
}

DecryptManifestUrl() {
    encrypted := "68747470733A2F2F7261772E67697468756275736572636F6E74656E742E636F6D2F6C6577697377723"
               . "22F6175746F686F746B65792D73747566662D636861742F6D61696E2F6D616E69666573742E6A736F6E"
    
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
    ; Extract just the folder name, not the full path
    try {
        SplitPath macroPath, , &macroDir
        SplitPath macroDir, &folderName, &parentDir
        
        ; Get category name too
        SplitPath parentDir, &categoryName
        
        ; Create clean key: Category_MacroName
        key := categoryName "_" folderName
        
        ; Replace invalid characters
        key := StrReplace(key, " ", "_")
        key := StrReplace(key, "\", "_")
        key := StrReplace(key, ":", "")
        key := StrReplace(key, "/", "_")
        key := RegExReplace(key, "[^a-zA-Z0-9_-]", "")
        
        return key
    } catch {
        ; Fallback to simple replacement
        key := StrReplace(StrReplace(macroPath, "\", "_"), ":", "")
        return RegExReplace(key, "[^a-zA-Z0-9_-]", "")
    }
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
        "AHK vault Update",
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
    SendUpdateNotification(current, manifest.version)
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
    SendUpdateNotification("manual", manifest.version)
    MsgBox(updateMsg, "Update Finished", "Iconi")
    
    try {
        mainGui.Destroy()
        CreateMainGui()
    }
}

; ========== ADD THESE FUNCTIONS TO MacroLauncher.ahk ==========

; ========== PROFILE DROPDOWN UI ==========

CreateMainGuiWithProfile() {
    global mainGui, COLORS, BASE_DIR, ICON_DIR, USER_PROFILE
    
    mainGui := Gui("-Resize +Border", " AHK Vault")
    mainGui.BackColor := COLORS.bg
    mainGui.SetFont("s10", "Segoe UI")
    
    ; Header
    mainGui.Add("Text", "x0 y0 w550 h80 Background" COLORS.accent)
    
    ; Profile Picture Circle (Top Right)
    profilePicBtn := mainGui.Add("Button", "x480 y10 w60 h60 Background" COLORS.card, "")
    profilePicBtn.SetFont("s24")
    
    ; Show profile picture or initial
    if USER_PROFILE.Has("profile_picture") && USER_PROFILE["profile_picture"] != "" {
        try {
            ; If we have base64 image, decode and display
            ; For now, show username initial
            initial := SubStr(USER_PROFILE.Has("username") ? USER_PROFILE["username"] : "U", 1, 1)
            profilePicBtn.Text := initial
        } catch {
            initial := SubStr(USER_PROFILE.Has("username") ? USER_PROFILE["username"] : "U", 1, 1)
            profilePicBtn.Text := initial
        }
    } else {
        initial := SubStr(USER_PROFILE.Has("username") ? USER_PROFILE["username"] : "U", 1, 1)
        profilePicBtn.Text := initial
    }
    
    profilePicBtn.OnEvent("Click", (*) => ShowProfileDropdown())
    
    ; Rest of GUI creation...
    titleText := mainGui.Add("Text", "x20 y17 w280 h100 c" COLORS.text " BackgroundTrans", " AHK Vault")
    titleText.SetFont("s24 bold")
    
    ; Continue with rest of GUI...
}

ShowProfileDropdown() {
    global COLORS, USER_PROFILE
    
    dropdownGui := Gui("+AlwaysOnTop -Caption +Border", "Profile Menu")
    dropdownGui.BackColor := COLORS.card
    dropdownGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    ; Username display
    username := USER_PROFILE.Has("username") ? USER_PROFILE["username"] : "User"
    usernameText := dropdownGui.Add("Text", "x20 y15 w260 c" COLORS.text, username)
    usernameText.SetFont("s12 bold")
    
    ; Total macros run
    totalMacros := USER_PROFILE.Has("total_macros") ? USER_PROFILE["total_macros"] : "0"
    statsText := dropdownGui.Add("Text", "x20 y40 w260 c" COLORS.textDim, "Macros run: " totalMacros)
    statsText.SetFont("s9")
    
    dropdownGui.Add("Text", "x0 y65 w300 h1 Background" COLORS.border)
    
    ; Settings button
    settingsBtn := dropdownGui.Add("Button", "x10 y75 w280 h35 Background" COLORS.cardHover, "⚙️ Settings")
    settingsBtn.SetFont("s10")
    settingsBtn.OnEvent("Click", (*) => (dropdownGui.Destroy(), ShowSettingsGui()))
    
    ; View Profile button
    profileBtn := dropdownGui.Add("Button", "x10 y115 w280 h35 Background" COLORS.cardHover, "👤 View Profile")
    profileBtn.SetFont("s10")
    profileBtn.OnEvent("Click", (*) => (dropdownGui.Destroy(), ShowFullProfile()))
    
    ; Logout button
    logoutBtn := dropdownGui.Add("Button", "x10 y155 w280 h35 Background" COLORS.danger, "🚪 Logout")
    logoutBtn.SetFont("s10")
    logoutBtn.OnEvent("Click", (*) => (dropdownGui.Destroy(), LogoutUser()))
    
    dropdownGui.OnEvent("Escape", (*) => dropdownGui.Destroy())
    
    ; Position near profile button (top right)
    dropdownGui.Show("x" (A_ScreenWidth - 320) " y80 w300 h200")
}

ShowSettingsGui() {
    global COLORS, SESSION_TOKEN_FILE, WORKER_URL
    
    settingsGui := Gui("+Resize", "Settings")
    settingsGui.BackColor := COLORS.bg
    settingsGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    ; Header
    settingsGui.Add("Text", "x0 y0 w600 h70 Background" COLORS.accent)
    settingsGui.Add("Text", "x20 y20 w560 h30 c" COLORS.text " BackgroundTrans", "⚙️ Settings").SetFont("s16 bold")
    
    ; Tab control for settings categories
    tab := settingsGui.Add("Tab3", "x10 y80 w580 h500 Background" COLORS.bgLight,
        ["Account", "Privacy", "Notifications", "Appearance"])
    
    ; ===== ACCOUNT TAB =====
    tab.UseTab(1)
    
    settingsGui.Add("Text", "x30 y120 w540 c" COLORS.text, "Change Password").SetFont("s12 bold")
    settingsGui.Add("Text", "x30 y145 w540 h1 Background" COLORS.border)
    
    settingsGui.Add("Text", "x30 y160 w200 c" COLORS.text, "Current Password:")
    oldPassEdit := settingsGui.Add("Edit", "x30 y185 w540 h30 Password Background" COLORS.card " c" COLORS.text)
    
    settingsGui.Add("Text", "x30 y225 w200 c" COLORS.text, "New Password:")
    newPassEdit := settingsGui.Add("Edit", "x30 y250 w540 h30 Password Background" COLORS.card " c" COLORS.text)
    
    settingsGui.Add("Text", "x30 y290 w200 c" COLORS.text, "Confirm New Password:")
    confirmPassEdit := settingsGui.Add("Edit", "x30 y315 w540 h30 Password Background" COLORS.card " c" COLORS.text)
    
    changePassBtn := settingsGui.Add("Button", "x30 y360 w200 h40 Background" COLORS.success, "Change Password")
    changePassBtn.SetFont("s10 bold")
    changePassBtn.OnEvent("Click", (*) => ChangePassword(oldPassEdit, newPassEdit, confirmPassEdit))
    
    ; ===== PRIVACY TAB =====
    tab.UseTab(2)
    
    settingsGui.Add("Text", "x30 y120 w540 c" COLORS.text, "Privacy Settings").SetFont("s12 bold")
    settingsGui.Add("Text", "x30 y145 w540 h1 Background" COLORS.border)
    
    profileVisibleCheck := settingsGui.Add("Checkbox", "x30 y165 w540 c" COLORS.text, "Show profile in reviews")
    profileVisibleCheck.Value := 1
    
    showStatsCheck := settingsGui.Add("Checkbox", "x30 y200 w540 c" COLORS.text, "Show statistics publicly")
    showStatsCheck.Value := 1
    
    ; ===== NOTIFICATIONS TAB =====
    tab.UseTab(3)
    
    settingsGui.Add("Text", "x30 y120 w540 c" COLORS.text, "Notification Preferences").SetFont("s12 bold")
    settingsGui.Add("Text", "x30 y145 w540 h1 Background" COLORS.border)
    
    updateNotifCheck := settingsGui.Add("Checkbox", "x30 y165 w540 c" COLORS.text, "Notify about macro updates")
    updateNotifCheck.Value := 1
    
    reviewNotifCheck := settingsGui.Add("Checkbox", "x30 y200 w540 c" COLORS.text, "Notify about review replies")
    reviewNotifCheck.Value := 1
    
    ; ===== APPEARANCE TAB =====
    tab.UseTab(4)
    
    settingsGui.Add("Text", "x30 y120 w540 c" COLORS.text, "Appearance Settings").SetFont("s12 bold")
    settingsGui.Add("Text", "x30 y145 w540 h1 Background" COLORS.border)
    
    settingsGui.Add("Text", "x30 y165 w200 c" COLORS.text, "Theme:")
    themeDDL := settingsGui.Add("DropDownList", "x30 y190 w250 Background" COLORS.card " c" COLORS.text,
        ["Dark (Default)", "Light", "System"])
    themeDDL.Choose(1)
    
    settingsGui.Add("Text", "x30 y235 w200 c" COLORS.text, "Font Size:")
    fontDDL := settingsGui.Add("DropDownList", "x30 y260 w250 Background" COLORS.card " c" COLORS.text,
        ["Small", "Medium (Default)", "Large"])
    fontDDL.Choose(2)
    
    ; Save and Close buttons
    saveBtn := settingsGui.Add("Button", "x10 y590 w285 h40 Background" COLORS.success, "💾 Save Settings")
    saveBtn.SetFont("s11 bold")
    saveBtn.OnEvent("Click", (*) => SaveSettings(settingsGui))
    
    closeBtn := settingsGui.Add("Button", "x305 y590 w285 h40 Background" COLORS.danger, "❌ Close")
    closeBtn.SetFont("s11 bold")
    closeBtn.OnEvent("Click", (*) => settingsGui.Destroy())
    
    settingsGui.Show("w600 h640 Center")
}

ChangePassword(oldPassEdit, newPassEdit, confirmPassEdit) {
    global WORKER_URL, SESSION_TOKEN_FILE, COLORS
    
    oldPass := oldPassEdit.Value
    newPass := newPassEdit.Value
    confirmPass := confirmPassEdit.Value
    
    if (oldPass = "" || newPass = "" || confirmPass = "") {
        MsgBox "Please fill in all password fields!", "Error", "Icon!"
        return
    }
    
    if (newPass != confirmPass) {
        MsgBox "New passwords do not match!", "Error", "Icon!"
        return
    }
    
    if (StrLen(newPass) < 6) {
        MsgBox "Password must be at least 6 characters!", "Error", "Icon!"
        return
    }
    
    if !FileExist(SESSION_TOKEN_FILE) {
        MsgBox "Not logged in!", "Error", "Icon!"
        return
    }
    
    try {
        sessionToken := Trim(FileRead(SESSION_TOKEN_FILE))
        
        oldPassHash := HashPassword(oldPass)
        newPassHash := HashPassword(newPass)
        
        body := '{"session_token":"' JsonEscape(sessionToken) '",'
              . '"old_password_hash":"' oldPassHash '",'
              . '"new_password_hash":"' newPassHash '"}'
        
        ToolTip "Changing password..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("POST", WORKER_URL "/auth/change-password", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
        
        ToolTip
        
        if (req.Status = 200) {
            MsgBox "✅ Password changed successfully!", "Success", "Iconi T2"
            oldPassEdit.Value := ""
            newPassEdit.Value := ""
            confirmPassEdit.Value := ""
        } else {
            resp := req.ResponseText
            MsgBox "❌ Failed to change password: " resp, "Error", "Icon!"
        }
        
    } catch as err {
        ToolTip
        MsgBox "Error changing password: " err.Message, "Error", "Icon!"
    }
}

SaveSettings(gui) {
    ; TODO: Implement settings save to server
    MsgBox "✅ Settings saved!", "Success", "Iconi T2"
}

ShowFullProfile() {
    global COLORS, USER_PROFILE, SESSION_TOKEN_FILE, WORKER_URL
    
    profileGui := Gui("+Resize", "My Profile")
    profileGui.BackColor := COLORS.bg
    profileGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    ; Header
    profileGui.Add("Text", "x0 y0 w700 h120 Background" COLORS.accent)
    
    ; Profile picture circle
    profilePic := profileGui.Add("Text", "x30 y20 w80 h80 Background" COLORS.success " Center", 
        SubStr(USER_PROFILE.Has("username") ? USER_PROFILE["username"] : "U", 1, 1))
    profilePic.SetFont("s32 bold c" COLORS.text)
    
    ; Username
    username := USER_PROFILE.Has("username") ? USER_PROFILE["username"] : "User"
    profileGui.Add("Text", "x130 y35 w550 c" COLORS.text " BackgroundTrans", username).SetFont("s18 bold")
    
    ; Member since
    created := USER_PROFILE.Has("created") ? USER_PROFILE["created"] : 0
    memberSince := FormatTimestampUtil(created)
    profileGui.Add("Text", "x130 y70 w550 c" COLORS.textDim " BackgroundTrans", "Member since: " memberSince)
    
    ; Stats cards
    yPos := 140
    
    ; Load full stats
    try {
        stats := GetUserStatsFromServer()
        
        CreateStatCard(profileGui, 30, yPos, "📊 Macros Run", String(stats.total_macros_run))
        CreateStatCard(profileGui, 240, yPos, "👍 Likes Given", String(stats.likes_given))
        CreateStatCard(profileGui, 450, yPos, "👎 Dislikes Given", String(stats.dislikes_given))
        
        yPos += 100
        
        CreateStatCard(profileGui, 30, yPos, "💬 Reviews", String(stats.ratings_given))
        CreateStatCard(profileGui, 240, yPos, "⭐ Favorites", String(stats.favorites_count))
        CreateStatCard(profileGui, 450, yPos, "📝 Comments", String(stats.reviews_with_comments))
        
        yPos += 100  ; Add height increment after the stat cards
        
    } catch {
        profileGui.Add("Text", "x30 y" yPos " w640 h500 c" COLORS.textDim, "Failed to load statistics")
        yPos += 30  ; Add height for error message
    }
    
    ; Edit Profile button
    editBtn := profileGui.Add("Button", "x30 y" yPos " w200 h40 Background" COLORS.accentAlt, "✏️ Edit Profile")
    editBtn.SetFont("s10 bold")
    editBtn.OnEvent("Click", (*) => ShowProfileEditor())
    
    ; Close button
    closeBtn := profileGui.Add("Button", "x470 y" yPos " w200 h40 Background" COLORS.danger, "Close")
    closeBtn.SetFont("s10 bold")
    closeBtn.OnEvent("Click", (*) => profileGui.Destroy())
    
    profileGui.Show("w700 h" (yPos + 60) " Center")
}

CreateStatCard(gui, x, y, label, value) {
    global COLORS
    
    gui.Add("Text", "x" x " y" y " w190 h80 Background" COLORS.card)
    gui.Add("Text", "x" (x + 10) " y" (y + 10) " w170 c" COLORS.textDim " BackgroundTrans", label).SetFont("s9")
    gui.Add("Text", "x" (x + 10) " y" (y + 35) " w170 c" COLORS.text " BackgroundTrans", value).SetFont("s20 bold")
}

GetUserStatsFromServer() {
    global WORKER_URL, SESSION_TOKEN_FILE
    
    if !FileExist(SESSION_TOKEN_FILE)
        return {}
    
    try {
        sessionToken := Trim(FileRead(SESSION_TOKEN_FILE))
        
        body := '{"session_token":"' JsonEscape(sessionToken) '"}'
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("POST", WORKER_URL "/profile/stats", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
        
        if (req.Status = 200) {
            resp := req.ResponseText
            
            stats := {}
            if RegExMatch(resp, '"total_macros_run"\s*:\s*(\d+)', &m)
                stats.total_macros_run := m[1]
            if RegExMatch(resp, '"ratings_given"\s*:\s*(\d+)', &m)
                stats.ratings_given := m[1]
            if RegExMatch(resp, '"likes_given"\s*:\s*(\d+)', &m)
                stats.likes_given := m[1]
            if RegExMatch(resp, '"dislikes_given"\s*:\s*(\d+)', &m)
                stats.dislikes_given := m[1]
            if RegExMatch(resp, '"favorites_count"\s*:\s*(\d+)', &m)
                stats.favorites_count := m[1]
            if RegExMatch(resp, '"reviews_with_comments"\s*:\s*(\d+)', &m)
                stats.reviews_with_comments := m[1]
            
            return stats
        }
    } catch {
    }
    
    return { total_macros_run: 0, ratings_given: 0, likes_given: 0, dislikes_given: 0, favorites_count: 0, reviews_with_comments: 0 }
}

LogoutUser() {
    global SESSION_TOKEN_FILE
    
    choice := MsgBox("Are you sure you want to logout?", "Logout", "YesNo Iconi")
    
    if (choice = "No")
        return
    
    try {
        if FileExist(SESSION_TOKEN_FILE)
            FileDelete SESSION_TOKEN_FILE
    } catch {
    }
    
    MsgBox "✅ Logged out successfully!`n`nThe launcher will now close.", "Logout", "Iconi T2"
    ExitApp
}

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

GetMacroRatings(macroPath) {
    global WORKER_URL, RATINGS_CACHE
    
    macroId := GetMacroKey(macroPath)
    
    ; Check cache first (30 second TTL for faster updates)
    if RATINGS_CACHE.Has(macroId) {
        cached := RATINGS_CACHE[macroId]
        if (A_TickCount - cached.time < 30000) { ; 30 seconds
            return cached.data
        }
    }
    
    try {
        url := WORKER_URL "/ratings/" macroId
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", url, false)
        req.Send()
        
        if (req.Status = 200) {
            resp := req.ResponseText
            
            ; Parse the response
            ratings := ParseRatingsResponse(resp)
            
            ; Cache it
            RATINGS_CACHE[macroId] := {
                data: ratings,
                time: A_TickCount
            }
            
            return ratings
        }
    } catch as err {
        ; Silent fail - return empty ratings on error
    }
    
    ; Return empty ratings if request failed
    return { likes: 0, dislikes: 0, total: 0, ratio: 0, reviews: [] }
}

ParseRatingsResponse(json) {
    result := { likes: 0, dislikes: 0, total: 0, ratio: 0, reviews: [] }
    
    try {
        ; First check if there's a stats object
        if RegExMatch(json, '(?s)"stats"\s*:\s*\{([^}]+)\}', &statsMatch) {
            statsBlock := statsMatch[1]
            
            if RegExMatch(statsBlock, '"likes"\s*:\s*(\d+)', &m)
                result.likes := Integer(m[1])
            
            if RegExMatch(statsBlock, '"dislikes"\s*:\s*(\d+)', &m)
                result.dislikes := Integer(m[1])
            
            if RegExMatch(statsBlock, '"total"\s*:\s*(\d+)', &m)
                result.total := Integer(m[1])
            
            if RegExMatch(statsBlock, '"ratio"\s*:\s*(\d+)', &m)
                result.ratio := Integer(m[1])
        }
        
        ; If no stats object, calculate from ratings array
        if (result.total = 0) {
            if RegExMatch(json, '"likes"\s*:\s*(\d+)', &m)
                result.likes := Integer(m[1])
            
            if RegExMatch(json, '"dislikes"\s*:\s*(\d+)', &m)
                result.dislikes := Integer(m[1])
            
            if RegExMatch(json, '"total"\s*:\s*(\d+)', &m)
                result.total := Integer(m[1])
            
            if RegExMatch(json, '"ratio"\s*:\s*(\d+)', &m)
                result.ratio := Integer(m[1])
        }
        
        ; Extract reviews array
        if RegExMatch(json, '(?s)"ratings"\s*:\s*\[(.*?)\]', &m) {
            reviewsBlock := m[1]
            pos := 1
            
            while (p := RegExMatch(reviewsBlock, '(?s)\{.*?\}', &mm, pos)) {
                reviewJson := mm[0]
                pos := p + StrLen(reviewJson)
                
                review := {}
                
                if RegExMatch(reviewJson, '"username"\s*:\s*"([^"]+)"', &u)
                    review.username := u[1]
                
                if RegExMatch(reviewJson, '"vote"\s*:\s*"([^"]+)"', &v)
                    review.vote := v[1]
                
                if RegExMatch(reviewJson, '"comment"\s*:\s*"([^"]*)"', &c) {
                    comment := c[1]
                    comment := StrReplace(comment, '\n', "`n")
                    comment := StrReplace(comment, '\"', '"')
                    review.comment := comment
                }
                
                if RegExMatch(reviewJson, '"timestamp"\s*:\s*(\d+)', &t)
                    review.timestamp := Integer(t[1])
                
                if RegExMatch(reviewJson, '"discord_id"\s*:\s*"([^"]+)"', &d)
                    review.discord_id := d[1]
                
                result.reviews.Push(review)
            }
        }
    } catch as err {
        ; Return empty stats on error
    }
    
    return result
}

FormatLikeRatio(likes, dislikes) {
    total := likes + dislikes
    if (total = 0)
        return "No votes yet"
    
    return "👍 " likes " | 👎 " dislikes " (" Round((likes / total) * 100) "% positive)"
}

ShowRatingsDialog(macroPath, macroInfo) {
    global COLORS, SESSION_TOKEN_FILE
    
    macroId := GetMacroKey(macroPath)
    ratings := GetMacroRatings(macroPath)
    
    ratingsGui := Gui("+Resize", macroInfo.Title " - Reviews")
    ratingsGui.BackColor := COLORS.bg
    ratingsGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    ; Header with scrollable content
    ratingsGui.Add("Text", "x0 y0 w700 h140 Background" COLORS.card)
    
    ; Like/Dislike stats
    ratingsGui.Add("Text", "x20 y20 w200 h80 Background" COLORS.success)
    likeIcon := ratingsGui.Add("Text", "x20 y25 w200 h40 Center c" COLORS.text " BackgroundTrans", "👍")
    likeIcon.SetFont("s28 bold")
    likeCount := ratingsGui.Add("Text", "x20 y70 w200 h30 Center c" COLORS.text " BackgroundTrans", ratings.likes " Likes")
    likeCount.SetFont("s16 bold")
    
    ratingsGui.Add("Text", "x240 y20 w200 h80 Background" COLORS.danger)
    dislikeIcon := ratingsGui.Add("Text", "x240 y25 w200 h40 Center c" COLORS.text " BackgroundTrans", "👎")
    dislikeIcon.SetFont("s28 bold")
    dislikeCount := ratingsGui.Add("Text", "x240 y70 w200 h30 Center c" COLORS.text " BackgroundTrans", ratings.dislikes " Dislikes")
    dislikeCount.SetFont("s16 bold")
    
    ; Ratio
    if (ratings.total > 0) {
        ratioText := ratingsGui.Add("Text", "x20 y110 w420 Center c" COLORS.text " BackgroundTrans",
            ratings.ratio "% positive • " ratings.total " total votes")
        ratioText.SetFont("s11 bold")
    } else {
        ratioText := ratingsGui.Add("Text", "x20 y110 w420 Center c" COLORS.textDim " BackgroundTrans",
            "No votes yet - be the first!")
        ratioText.SetFont("s11")
    }
    
    ; Vote buttons
    likeBtn := ratingsGui.Add("Button", "x480 y30 w100 h45 Background" COLORS.success, "👍 Like")
    likeBtn.SetFont("s11 bold")
    likeBtn.OnEvent("Click", (*) => SubmitVote(macroId, "like", ratingsGui))
    
    dislikeBtn := ratingsGui.Add("Button", "x590 y30 w100 h45 Background" COLORS.danger, "👎 Dislike")
    dislikeBtn.SetFont("s11 bold")
    dislikeBtn.OnEvent("Click", (*) => SubmitVote(macroId, "dislike", ratingsGui))
    
    ; Reviews section title
    ratingsGui.Add("Text", "x20 y150 w660 c" COLORS.text, "Recent Reviews").SetFont("s12 bold")
    
    ; ========== SCROLLABLE REVIEWS SECTION ==========
    ; Create a ListView for scrollable reviews
    reviewsLV := ratingsGui.Add("ListView", "x20 y180 w660 h350 -Hdr Background" COLORS.card " c" COLORS.text, ["Review"])
    reviewsLV.ModifyCol(1, 640)
    
    if (ratings.reviews.Length = 0) {
        reviewsLV.Add(, "No reviews yet. Be the first to leave feedback!")
    } else {
        maxReviews := Min(50, ratings.reviews.Length)  ; Show up to 50 reviews
        
        Loop maxReviews {
            review := ratings.reviews[A_Index]
            
            ; Build review text
            voteIcon := review.vote = "like" ? "👍" : "👎"
            username := review.username ? review.username : "Anonymous"
            dateStr := FormatTimestamp(review.timestamp)
            
            reviewText := voteIcon " " username " • " dateStr
            
            if (review.comment && review.comment != "") {
                reviewText .= "`n" review.comment
            }
            
            reviewsLV.Add(, reviewText)
        }
        
        if (ratings.reviews.Length > 50) {
            reviewsLV.Add(, "`n--- Showing 50 of " ratings.reviews.Length " reviews ---")
        }
    }
    
    ; Close button
    closeBtn := ratingsGui.Add("Button", "x275 y545 w150 h40 Background" COLORS.danger, "Close")
    closeBtn.SetFont("s10 bold")
    closeBtn.OnEvent("Click", (*) => ratingsGui.Destroy())
    
    ratingsGui.OnEvent("Close", (*) => ratingsGui.Destroy())
    ratingsGui.Show("w700 h600 Center")
}

ShowUserProfilePopup(discord_id) {
    global COLORS, WORKER_URL
    
    if (!discord_id || discord_id = "") {
        return  ; Silent fail - don't show error
    }
    
    try {
        ToolTip "Loading profile..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 5000, 5000)
        req.Open("GET", WORKER_URL "/profile/public/" discord_id, false)
        req.Send()
        
        ToolTip
        
        if (req.Status != 200) {
            ; Silent fail - profile might not exist yet
            return
        }
        
        resp := req.ResponseText
        
        ; Parse profile data
        username := JsonExtractAny(resp, "username")
        bio := JsonExtractAny(resp, "bio")
        totalMacros := JsonExtractAny(resp, "total_macros_run")
        memberSince := JsonExtractAny(resp, "member_since")
        
        ; If no username found, don't show popup
        if (!username || username = "") {
            return
        }
        
        ; Create profile popup
        profileGui := Gui("+AlwaysOnTop", username "'s Profile")
        profileGui.BackColor := COLORS.bg
        profileGui.SetFont("s10 c" COLORS.text, "Segoe UI")
        
        ; Header
        profileGui.Add("Text", "x0 y0 w400 h90 Background" COLORS.accent)
        
        ; Profile picture (use initial letter)
        initial := SubStr(username, 1, 1)
        profilePic := profileGui.Add("Text", "x20 y15 w60 h60 Background" COLORS.success " Center", initial)
        profilePic.SetFont("s24 bold c" COLORS.text)
        
        ; Username
        profileGui.Add("Text", "x95 y25 w285 c" COLORS.text " BackgroundTrans", username).SetFont("s14 bold")
        
        ; Member since
        memberStr := memberSince ? FormatTimestampUtil(memberSince) : "Recently"
        profileGui.Add("Text", "x95 y55 w285 c" COLORS.textDim " BackgroundTrans", "Member since: " memberStr).SetFont("s8")
        
        ; Bio section
        profileGui.Add("Text", "x20 y100 w360 c" COLORS.text, "Bio:").SetFont("s10 bold")
        
        bioText := (bio && bio != "") ? bio : "No bio yet"
        bioDisplay := profileGui.Add("Text", "x20 y125 w360 h80 Background" COLORS.card, " " bioText)
        bioDisplay.SetFont("s9")
        
        ; Stats
        profileGui.Add("Text", "x20 y220 w360 c" COLORS.text, "Statistics:").SetFont("s10 bold")
        
        profileGui.Add("Text", "x20 y245 w360 h60 Background" COLORS.card)
        profileGui.Add("Text", "x30 y255 w340 c" COLORS.text " BackgroundTrans", "📊 Total Macros Run:").SetFont("s9")
        
        macroCount := totalMacros ? totalMacros : "0"
        profileGui.Add("Text", "x30 y280 w340 c" COLORS.accent " BackgroundTrans", macroCount).SetFont("s14 bold")
        
        ; Close button
        closeBtn := profileGui.Add("Button", "x125 y320 w150 h40 Background" COLORS.danger, "Close")
        closeBtn.SetFont("s10 bold")
        closeBtn.OnEvent("Click", (*) => profileGui.Destroy())
        
        profileGui.OnEvent("Close", (*) => profileGui.Destroy())
        profileGui.Show("w400 h380 Center")
        
    } catch as err {
        ToolTip
        ; Silent fail - don't annoy users with error messages
    }
}

SubmitVote(macroId, voteType, parentGui := 0) {
    global COLORS
    
    ; Show comment dialog
    commentGui := Gui("+AlwaysOnTop", "Add Comment (Optional)")
    commentGui.BackColor := COLORS.bg
    commentGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    ; Header
    commentGui.Add("Text", "x0 y0 w500 h60 Background" COLORS.accent)
    voteEmoji := voteType = "like" ? "👍" : "👎"
    commentGui.Add("Text", "x20 y15 w460 c" COLORS.text " BackgroundTrans", 
        voteEmoji " " (voteType = "like" ? "Like" : "Dislike") " this macro").SetFont("s14 bold")
    
    ; Comment box
    commentGui.Add("Text", "x20 y80 w460 c" COLORS.text, "Leave a comment (optional):")
    commentEdit := commentGui.Add("Edit", "x20 y110 w460 h100 Background" COLORS.bgLight " c" COLORS.text " Multi")
    
    commentGui.Add("Text", "x20 y220 w460 c" COLORS.textDim, "Maximum 500 characters").SetFont("s8")
    
    ; Status text
    statusText := commentGui.Add("Text", "x20 y245 w460 Center c" COLORS.danger, "")
    
    ; Buttons
    submitBtn := commentGui.Add("Button", "x20 y275 w220 h40 Background" COLORS.success, "Submit Vote")
    submitBtn.SetFont("s10 bold")
    
    skipBtn := commentGui.Add("Button", "x260 y275 w220 h40 Background" COLORS.warning, "Skip Comment")
    skipBtn.SetFont("s10 bold")
    
    submitBtn.OnEvent("Click", (*) => SubmitVoteWithComment(
        macroId, 
        voteType, 
        commentEdit.Value, 
        statusText, 
        commentGui, 
        parentGui
    ))
    
    skipBtn.OnEvent("Click", (*) => SubmitVoteWithComment(
        macroId, 
        voteType, 
        "", 
        statusText, 
        commentGui, 
        parentGui
    ))
    
    commentGui.OnEvent("Close", (*) => commentGui.Destroy())
    commentGui.Show("w500 h335 Center")
}

SubmitVoteWithComment(macroId, voteType, comment, statusControl, commentGui, parentGui) {
    global WORKER_URL, SESSION_TOKEN_FILE, RATINGS_CACHE
    
    if !FileExist(SESSION_TOKEN_FILE) {
        statusControl.Value := "❌ Not logged in - session file not found"
        SoundBeep(500, 200)
        return
    }
    
    sessionToken := ""
    try {
        sessionToken := Trim(FileRead(SESSION_TOKEN_FILE))
    } catch {
        statusControl.Value := "❌ Cannot read session file"
        SoundBeep(500, 200)
        return
    }
    
    if (sessionToken = "") {
        statusControl.Value := "❌ Session token is empty - please re-login"
        SoundBeep(500, 200)
        return
    }
    
    statusControl.Value := "Submitting..."
    
    try {
        body := '{"session_token":"' JsonEscape(sessionToken) '","macro_id":"' JsonEscape(macroId) '","vote":"' voteType '","comment":"' JsonEscape(comment) '"}'
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(15000, 15000, 15000, 15000)
        req.Open("POST", WORKER_URL "/ratings/submit", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
        
        if (req.Status = 200) {
            ; Clear cache for this macro
            if RATINGS_CACHE.Has(macroId)
                RATINGS_CACHE.Delete(macroId)
            
            statusControl.Value := "✅ Vote submitted!"
            SoundBeep(1000, 100)
            
            SetTimer(() => (
                commentGui.Destroy(),
                parentGui ? parentGui.Destroy() : 0
            ), -1500)
        } else if (req.Status = 401) {
            statusControl.Value := "❌ Session expired - please re-login"
            SoundBeep(500, 200)
        } else {
            resp := ""
            try resp := req.ResponseText
            statusControl.Value := "❌ Failed: " req.Status
            SoundBeep(500, 200)
        }
    } catch as err {
        statusControl.Value := "❌ Error: " err.Message
        SoundBeep(500, 200)
    }
}

FormatTimestamp(timestamp) {
    ; Convert timestamp to readable date
    try {
        ; timestamp is milliseconds since epoch
        seconds := timestamp / 1000
        
        ; Get current time in seconds
        nowSeconds := DateDiff(A_Now, "19700101000000", "Seconds")
        
        diff := nowSeconds - seconds
        
        if (diff < 60)
            return "Just now"
        else if (diff < 3600)
            return Floor(diff / 60) " minutes ago"
        else if (diff < 86400)
            return Floor(diff / 3600) " hours ago"
        else if (diff < 604800)
            return Floor(diff / 86400) " days ago"
        else
            return Floor(diff / 604800) " weeks ago"
    } catch {
        return "Recently"
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
    global mainGui, COLORS, BASE_DIR, ICON_DIR, USER_PROFILE, SECURE_VAULT
    
    mainGui := Gui("-Resize +Border", " AHK Vault")
    mainGui.BackColor := COLORS.bg
    mainGui.SetFont("s10", "Segoe UI")
    
    ; Set window icon
    iconPath := ICON_DIR "\TrayIcon.png"
    if FileExist(iconPath) {
        try {
            mainGui.Show("Hide")
            mainGui.Opt("+Icon" iconPath)
        }
    }
    
    ; Header
    mainGui.Add("Text", "x0 y0 w550 h80 Background" COLORS.accent)
    
    ; Launcher logo
    launcherImage := ICON_DIR "\Launcher.png"
    if FileExist(launcherImage) {
        try {
            mainGui.Add("Picture", "x5 y0 w75 h75 BackgroundTrans", launcherImage)
        }
    }
    
    titleText := mainGui.Add("Text", "x85 y17 w180 h100 c" COLORS.text " BackgroundTrans", " AHK Vault")
    titleText.SetFont("s24 bold")

    ; Header buttons - Left side (Uninstall, Update, Changelog)
    btnNuke := mainGui.Add("Button", "x270 y10 w75 h28 Background" COLORS.danger, "Uninstall")
    btnNuke.SetFont("s9")
    btnNuke.OnEvent("Click", CompleteUninstall)

    btnUpdate := mainGui.Add("Button", "x270 y42 w75 h28 Background" COLORS.accentHover, "Update")
    btnUpdate.SetFont("s9")
    btnUpdate.OnEvent("Click", ManualUpdate)
    
    btnLog := mainGui.Add("Button", "x350 y10 w75 h28 Background" COLORS.accentAlt, "Changelog")
    btnLog.SetFont("s9")
    btnLog.OnEvent("Click", ShowChangelog)
    
    ; Logout button
    btnLogout := mainGui.Add("Button", "x350 y42 w75 h28 Background" COLORS.warning, "Log Out")
    btnLogout.SetFont("s9")
    btnLogout.OnEvent("Click", (*) => LogoutUser())
    
    ; Profile Picture Circle (Top Right)
    profilePicPath := SECURE_VAULT "\profile_picture.png"
    hasProfilePic := false
    
    ; Check if profile picture exists
    if FileExist(profilePicPath) {
        try {
            ; Use Picture control for actual image
            picCtrl := mainGui.Add("Picture", "x475 y10 w60 h60 BackgroundTrans Border", profilePicPath)
            picCtrl.OnEvent("Click", (*) => ShowProfileDropdown())
            hasProfilePic := true
        } catch {
            ; Fall back to button with initial
        }
    }
    
    ; If no picture, show button with initial letter
    if (!hasProfilePic) {
        username := ReadUsername()
        initial := SubStr(username, 1, 1)
        
        profilePicBtn := mainGui.Add("Button", "x475 y10 w60 h60 Background" COLORS.card " Border", initial)
        profilePicBtn.SetFont("s24 bold c" COLORS.text)
        profilePicBtn.OnEvent("Click", (*) => ShowProfileDropdown())
    }

    ; NEW: Add menu bar for enhanced features
    try {
        menuBar := Menu()
        menuBar.Add("👤 Edit Profile", (*) => ShowProfileEditor())
        menuBar.Add("📊 My History", (*) => ShowUserHistory())
        menuBar.Add("🏆 Popular Macros", (*) => ShowPopularMacros())
        mainGui.MenuBar := menuBar
    } catch {
        ; Silent fail if menu creation fails
    }

    mainGui.Add("Text", "x25 y100 w500 c" COLORS.text, "Utilities").SetFont("s12 bold")
    mainGui.Add("Text", "x25 y125 w500 h1 Background" COLORS.border)

    yPos := 145

    utilButtons := GetUtilityButtons()

    if (utilButtons.Length > 0) {
        rowsNeeded := Ceil(utilButtons.Length / 4)
        CreateUtilityButtonsGrid(mainGui, utilButtons, 25, yPos)
        yPos += (rowsNeeded * 100) + 20
    } else {
        noUtilText := mainGui.Add("Text", 
            "x25 y" yPos " w500 h60 c" COLORS.textDim " Center", 
            "No utility buttons found`n`nCreate subfolders in: " BASE_DIR "\Buttons\`nEach with Main.ahk and icon.png")
        noUtilText.SetFont("s9")
        yPos += 80
    }
    
    ; Games Section
    mainGui.Add("Text", "x25 y" yPos " w500 c" COLORS.text, "Games").SetFont("s12 bold")
    mainGui.Add("Text", "x25 y" (yPos + 25) " w500 h1 Background" COLORS.border)
    
    categories := GetCategories()
    yPos += 45
    xPos := 25
    cardWidth := 500
    cardHeight := 70
    
    if (categories.Length = 0) {
        noGameText := mainGui.Add("Text", "x25 y" yPos " w500 h120 c" COLORS.textDim " Center", 
            "No game categories found`n`nPlace game folders in the secure vault")
        noGameText.SetFont("s10")
        yPos += 120
    } else {
        for category in categories {
            CreateCategoryCard(mainGui, category, xPos, yPos, cardWidth, cardHeight)
            yPos += cardHeight + 12
        }
    }
    
    mainGui.Show("w550 h" (yPos + 20) " Center")
}

ShowProfileEditor() {
    global WORKER_URL, SESSION_TOKEN_FILE, DISCORD_ID_FILE, COLORS, USER_PROFILE, SECURE_VAULT
    
    discordId := ReadDiscordId()
    if (discordId = "" || discordId = "Unknown") {
        MsgBox "Discord ID not found!", "Error"
        return
    }
    
    LoadUserProfile()
    
    profileGui := Gui(, "Edit Profile")
    profileGui.BackColor := COLORS.bg
    profileGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    profileGui.Add("Text", "x0 y0 w500 h60 Background" COLORS.accent)
    profileGui.Add("Text", "x20 y15 w460 h30 c" COLORS.text " BackgroundTrans", "👤 Your Profile").SetFont("s16 bold")
    
    profileGui.Add("Text", "x20 y80 w460 c" COLORS.text, "Username:")
    currentUsername := USER_PROFILE.Has("username") ? USER_PROFILE["username"] : ReadUsername()
    usernameEdit := profileGui.Add("Edit", "x20 y105 w460 h30 Background" COLORS.card " c" COLORS.text, currentUsername)
    
    profileGui.Add("Text", "x20 y150 w460 c" COLORS.text, "Bio (max 500 characters):")
    currentBio := USER_PROFILE.Has("bio") ? USER_PROFILE["bio"] : ""
    bioEdit := profileGui.Add("Edit", "x20 y175 w460 h100 Multi Background" COLORS.card " c" COLORS.text, currentBio)
    
    profileGui.Add("Text", "x20 y290 w460 c" COLORS.text, "Profile Picture:")
    
    ; Show current profile picture if it exists
    localPicPath := SECURE_VAULT "\profile_picture.png"
    if FileExist(localPicPath) {
        try {
            profileGui.Add("Picture", "x20 y315 w80 h80 BackgroundTrans Border", localPicPath)
            profileGui.Add("Text", "x110 y330 w370 c" COLORS.success, "✅ Profile picture set")
        } catch {
            profileGui.Add("Text", "x20 y315 w460 c" COLORS.textDim, "No profile picture set")
        }
    } else {
        profileGui.Add("Text", "x20 y315 w460 c" COLORS.textDim, "No profile picture set")
    }
    
    uploadBtn := profileGui.Add("Button", "x20 y405 w200 h35 Background" COLORS.accentAlt, "📷 Choose Picture")
    uploadBtn.SetFont("s10")
    uploadBtn.OnEvent("Click", (*) => ChooseProfilePicture())
    
    profileGui.Add("Text", "x20 y455 w460 c" COLORS.textDim, "Statistics:")
    totalMacros := USER_PROFILE.Has("total_macros") ? USER_PROFILE["total_macros"] : "0"
    profileGui.Add("Text", "x20 y480 w460 c" COLORS.text, "Total Macros Run: " totalMacros)
    
    saveBtn := profileGui.Add("Button", "x20 y520 w220 h40 Background" COLORS.success, "💾 Save Changes")
    saveBtn.SetFont("s11 bold")
    cancelBtn := profileGui.Add("Button", "x260 y520 w220 h40 Background" COLORS.danger, "❌ Cancel")
    cancelBtn.SetFont("s11 bold")
    
    saveBtn.OnEvent("Click", (*) => SaveProfile())
    cancelBtn.OnEvent("Click", (*) => profileGui.Destroy())
    
    profileGui.Show("w500 h580")
    
    SaveProfile() {
        username := usernameEdit.Value
        bio := bioEdit.Value
        
        if (username = "") {
            MsgBox "Username cannot be empty!", "Error"
            return
        }
        
        if !FileExist(SESSION_TOKEN_FILE) {
            MsgBox "Not logged in!", "Error"
            return
        }
        
        try {
            sessionToken := Trim(FileRead(SESSION_TOKEN_FILE))
            
            body := '{"session_token":"' JsonEscape(sessionToken) '",'
                  . '"username":"' JsonEscape(username) '",'
                  . '"bio":"' JsonEscape(bio) '"}'
            
            ToolTip "Saving profile..."
            
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.SetTimeouts(10000, 10000, 10000, 10000)
            req.Open("POST", WORKER_URL "/profile/update", false)
            req.SetRequestHeader("Content-Type", "application/json")
            req.Send(body)
            
            ToolTip
            
            if (req.Status = 200) {
                MsgBox "✅ Profile updated successfully!", "Success", "Iconi T2"
                LoadUserProfile()
                profileGui.Destroy()
            } else {
                MsgBox "Failed to update profile: " req.Status, "Error"
            }
        } catch as err {
            ToolTip
            MsgBox "Error: " err.Message, "Error"
        }
    }
    
    ChooseProfilePicture() {
        selectedFile := FileSelect(, , "Select Profile Picture", "Images (*.png; *.jpg; *.jpeg; *.gif)")
        if (selectedFile = "")
            return
        
        fileSize := 0
        Loop Files, selectedFile
            fileSize := A_LoopFileSize
        
        if (fileSize > 500000) {
            MsgBox "Image too large! Please use an image under 500KB.", "Error"
            return
        }
        
        UploadProfilePicture(selectedFile)
    }
}

UploadProfilePicture(imagePath) {
    global WORKER_URL, SESSION_TOKEN_FILE, SECURE_VAULT
    
    if !FileExist(imagePath) {
        MsgBox "Image file not found!", "Error"
        return false
    }
    
    if !FileExist(SESSION_TOKEN_FILE) {
        MsgBox "Not logged in!", "Error"
        return false
    }
    
    try {
        ; Save profile picture locally FIRST
        localPicPath := SECURE_VAULT "\profile_picture.png"
        
        ToolTip "Saving profile picture locally..."
        
        ; Copy the selected image to local storage
        try {
            FileCopy imagePath, localPicPath, 1
        } catch as err {
            ToolTip
            MsgBox "Failed to save picture locally: " err.Message, "Error"
            return false
        }
        
        ; Now upload to server
        ToolTip "Converting image to base64..."
        base64 := FileToBase64(imagePath)
        ToolTip
        
        if (StrLen(base64) > 700000) {
            MsgBox "Image too large! Please use a smaller image (max ~500KB)", "Error"
            return false
        }
        
        sessionToken := Trim(FileRead(SESSION_TOKEN_FILE))
        
        SplitPath imagePath, , , &ext
        mimeType := "image/" (ext = "jpg" ? "jpeg" : ext)
        
        body := '{"session_token":"' JsonEscape(sessionToken) '",'
              . '"image_data":"data:' mimeType ';base64,' base64 '"}'
        
        ToolTip "Uploading profile picture to server..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(30000, 30000, 30000, 30000)
        req.Open("POST", WORKER_URL "/profile/picture", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
        
        ToolTip
        
        if (req.Status = 200) {
            MsgBox "✅ Profile picture uploaded successfully!`n`nRestart the launcher to see changes.", "Success", "Iconi T2"
            return true
        } else {
            resp := req.ResponseText
            MsgBox "Failed to upload to server: " resp "`n`nBut picture was saved locally!", "Partial Success", "Icon!"
            return true  ; Still return true since local save worked
        }
    } catch as err {
        ToolTip
        MsgBox "Error uploading picture: " err.Message, "Error"
    }
    
    return false
}

GetCategories() {
    global BASE_DIR
    arr := []
    
    if !DirExist(BASE_DIR)
        return arr
    
    try {
        Loop Files, BASE_DIR "\*", "D" {
            folderName := A_LoopFileName
            ; ✅ V1LN VERSION: ONLY include Pet Simulator 99 folder
            if (folderName = "Pet Simulator 99")
                arr.Push(folderName)
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
    
    ; First check ICON_DIR
    for ext in extensions {
        iconPath := ICON_DIR "\" category "." ext
        if FileExist(iconPath)
            return iconPath
    }
    
    ; Then check category folder root
    for ext in extensions {
        iconPath := BASE_DIR "\" category "\icon." ext
        if FileExist(iconPath)
            return iconPath
    }
    
    ; Check for category name as filename
    for ext in extensions {
        iconPath := BASE_DIR "\" category "\" category "." ext
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

OpenCategory(category, sortBy := "favorites", page := 1) {
    global COLORS, BASE_DIR
    
    macros := GetMacrosWithInfo(category, sortBy)
    
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
    win.__currentPage := page
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
    OpenCategory(category, sortBy, 1)  ; Reset to page 1 when sorting
}

ChangePage(win, direction) {
    category := win.__category
    sortBy := win.__sortBy
    newPage := win.__currentPage + direction
    
    totalPages := Ceil(win.__data.Length / win.__itemsPerPage)
    
    ; Validate page number
    if (newPage < 1)
        newPage := 1
    if (newPage > totalPages)
        newPage := totalPages
    
    ; Close current window and reopen with new page
    win.Destroy()
    Sleep 100
    OpenCategory(category, sortBy, newPage)
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
    
    ratings := GetMacroRatings(item.path)
    
    if (ratings.total > 0) {
        ; Show like/dislike ratio with better formatting
        ratingDisplay := "👍 " ratings.likes " | 👎 " ratings.dislikes " (" ratings.ratio "% positive)"
        ratingCtrl := win.Add("Text", "x" (x + 120) " y" (y + 95) " w300 c" COLORS.warning " BackgroundTrans", ratingDisplay)
        ratingCtrl.SetFont("s10 bold")
        win.__cards.Push(ratingCtrl)
    } else {
        ; Show "No ratings yet" message
        noRatingCtrl := win.Add("Text", "x" (x + 120) " y" (y + 95) " w250 c" COLORS.textDim " BackgroundTrans", "No ratings yet")
        noRatingCtrl.SetFont("s9")
        win.__cards.Push(noRatingCtrl)
    }
    
    ; Reviews button
    reviewsBtn := win.Add("Button", "x" (x + w - 210) " y" (y + 65) " w100 h30 Background" COLORS.accentAlt, "💬 Reviews")
    reviewsBtn.SetFont("s9")
    currentPath := item.path
    currentInfo := item.info
    reviewsBtn.OnEvent("Click", (*) => ShowRatingsDialog(currentPath, currentInfo))
    win.__cards.Push(reviewsBtn)
    
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
        " y" (y + 20)
        " w35 h35 Center Background" (isFav ? COLORS.favorite : COLORS.cardHover),
        isFav ? "★" : "✰"
    )
    favBtn.SetFont("s18", "Segoe UI Symbol")
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
    
    ; Show ratings on grid cards
    ratings := GetMacroRatings(item.path)
    if (ratings.total > 0) {
        ratingDisplay := "👍 " ratings.likes " 👎 " ratings.dislikes
        ratingCtrl := win.Add("Text", "x" (x + 90) " y" (y + 85) " w150 c" COLORS.warning " BackgroundTrans", ratingDisplay)
        ratingCtrl.SetFont("s8 bold")
        win.__cards.Push(ratingCtrl)
    }
    
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
        " y" (y + 20)
        " w20 h20 Center Background" (isFav ? COLORS.favorite : COLORS.cardHover),
        isFav ? "★" : "✰"
    )
    favBtn.SetFont("s11", "Segoe UI Symbol")
    favBtn.OnEvent("Click", (*) => ToggleFavoriteAndRefresh(win, currentPath))
    win.__cards.Push(favBtn)
    
    runBtn := win.Add("Button", "x" (x + w - 90) " y" (y + 15) " w80 h30 Background" COLORS.success, "▶ Run")
    runBtn.SetFont("s10 bold")
    runBtn.OnEvent("Click", (*) => RunMacro(currentPath))
    win.__cards.Push(runBtn)
    
    ; Reviews button for grid cards
    reviewsBtn := win.Add("Button", "x" (x + w - 90) " y" (y + 50) " w80 h22 Background" COLORS.accentAlt, "💬 Reviews")
    reviewsBtn.SetFont("s8")
    reviewsBtn.OnEvent("Click", (*) => ShowRatingsDialog(currentPath, item.info))
    win.__cards.Push(reviewsBtn)
    
    if (Trim(item.info.Links) != "") {
        currentLinks := item.info.Links
        linksBtn := win.Add("Button", "x" (x + w - 90) " y" (y + 77) " w80 h22 Background" COLORS.card, "🔗 Links")
        linksBtn.SetFont("s8")
        linksBtn.OnEvent("Click", (*) => OpenLinks(currentLinks))
        win.__cards.Push(linksBtn)
    }
}

ToggleFavoriteAndRefresh(win, macroPath) {
    ToggleFavorite(macroPath)
    
    ; Get current state
    category := win.__category
    sortBy := win.__sortBy
    currentPage := win.__currentPage
    
    ; Close and reopen with same settings
    win.Destroy()
    Sleep 100
    OpenCategory(category, sortBy, currentPage)
}

GetMacroIcon(macroPath) {
    global BASE_DIR, ICON_DIR
    
    try {
        SplitPath macroPath, , &macroDir
        SplitPath macroDir, &macroName
        
        extensions := ["png", "ico", "jpg", "jpeg"]
        
        ; Check ICON_DIR first
        for ext in extensions {
            iconPath := ICON_DIR "\" macroName "." ext
            if FileExist(iconPath)
                return iconPath
        }
        
        ; Check macro folder for icon.png
        for ext in extensions {
            iconPath := macroDir "\icon." ext
            if FileExist(iconPath)
                return iconPath
        }
        
        ; Check for macro name as filename
        for ext in extensions {
            iconPath := macroDir "\" macroName "." ext
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
                    ; ✅ FILTER: Only add macro if Released is not "No"
                    if (StrLower(info.Released) != "no") {
                        out.Push({
                            path: mainFile,
                            info: info
                        })
                    }
                }
            }
        }
    }
    
    if (out.Length = 0) {
        mainFile := base "\Main.ahk"
        if FileExist(mainFile) {
            try {
                info := ReadMacroInfo(base)
                ; ✅ FILTER: Only add macro if Released is not "No"
                if (StrLower(info.Released) != "no") {
                    out.Push({
                        path: mainFile,
                        info: info
                    })
                }
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
        Links: "",
        Released: "Yes"  ; Default to Yes if not specified
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
            case "released":
                info.Released := v
        }
    }
    
    if (info.Version = "")
        info.Version := "1.0"
    if (info.Creator = "")
        info.Creator := "Unknown"
    
    return info
}

RunMacro(path) {
    if !FileExist(path) {
        MsgBox "Macro not found:`n" path, "Error", "Icon!"
        return
    }
    
    IncrementRunCount(path)
    
    ; NEW: Track macro execution with analytics
    startTime := A_TickCount
    
    try {
        SplitPath path, , &dir
        SplitPath dir, &macroName
        
        ; Determine category from path
        category := "Uncategorized"
        pathParts := StrSplit(path, "\")
        if (pathParts.Length >= 3) {
            ; Try to get category from path (e.g., BASE_DIR\CategoryName\MacroName)
            category := pathParts[pathParts.Length - 1]
        }
        
        SendMacroRunNotification(macroName, path)
        
        ; NEW: Track analytics after a short delay
        macroId := category "_" macroName
        SetTimer () => TrackAfterRun(macroId, macroName, category, startTime), -2000
    }
    
    try {
        SplitPath path, , &dir
        Run '"' A_AhkPath '" "' path '"', dir
    } catch as err {
        MsgBox "Failed to run macro: " err.Message, "Error", "Icon!"
    }
}

; NEW: Helper function to track macro after it runs
TrackAfterRun(macroId, macroName, category, startTime) {
    duration := A_TickCount - startTime
    try {
        TrackMacroUsage(macroId, macroName, category, duration)
    } catch {
        ; Silent fail - don't interrupt user
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
    global APP_DIR, SECURE_VAULT, BASE_DIR, ICON_DIR, VERSION_FILE
    
    choice := MsgBox(
        "⚠️ WARNING ⚠️`n`n"
        . "This will permanently delete:`n"
        . "• All downloaded macros`n"
        . "• All icons and resources`n"
        . "• All stats and favorites`n"
        . "• Version information`n`n"
        . "This action CANNOT be undone!`n`n"
        . "Are you sure you want to uninstall?",
        "Uninstall AHK Vault",
        "YesNo Icon! Default2"
    )
    
    if (choice = "No")
        return
    
    try {
        if FileExist(VERSION_FILE) {
            try FileDelete VERSION_FILE
        }
        
        if DirExist(BASE_DIR) {
            try DirDelete BASE_DIR, true
        }
        
        if DirExist(ICON_DIR) {
            try DirDelete ICON_DIR, true
        }
        
        if DirExist(SECURE_VAULT) {
            try DirDelete SECURE_VAULT, true
        }
        
        if DirExist(APP_DIR) {
            try DirDelete APP_DIR, true
        }
        
        regPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo"
        try RegDelete regPath, "MachineGUID"
        
        MsgBox(
            "✅ Uninstall successful!`n`n"
            . "Removed:`n"
            . "• All macros and data`n"
            . "• All icons and resources`n"
            . "• Registry keys`n`n"
            . "The launcher will now close.",
            "Uninstall Complete",
            "Iconi"
        )
        SendUninstallNotification()
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
    ; FIX: Ensure destination parent directory exists
    try {
        SplitPath dst, , &parentDir
        if (parentDir != "" && !DirExist(parentDir)) {
            DirCreate parentDir
        }
    } catch {
        ; If we can't create parent, DirMove will fail anyway
    }
    
    ; If destination exists and we want to overwrite, delete it first
    if (DirExist(dst) && overwrite) {
        try {
            DirDelete dst, true
        } catch {
            ; Ignore deletion errors
        }
    }
    
    loop retries {
        try {
            DirMove src, dst, overwrite ? 2 : 0
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
    ; FIX: Ensure destination parent directory exists
    try {
        SplitPath dst, , &parentDir
        if (parentDir != "" && !DirExist(parentDir)) {
            DirCreate parentDir
        }
    } catch {
        ; If we can't create parent, FileCopy will fail anyway
    }
    
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

    MsgBox msg, "AHK vault - Update Failed", "Icon! 0x10"
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
    global WORKER_URL

    url := RTrim(WORKER_URL, "/") "/" LTrim(endpoint, "/")
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.SetTimeouts(15000, 15000, 15000, 15000)
    req.Open("POST", url, false)
    req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
    req.SetRequestHeader("Accept", "application/json")
    req.SetRequestHeader("User-Agent", "v1ln-clan")
    req.Send(bodyJson)

    status := 0
    resp := ""
    try status := req.Status
    try resp := req.ResponseText

    if (status < 200 || status >= 300)
        throw Error("Worker error " status ": " resp)
    return resp
}

MakeUtilityClickHandler(path, name) {
    return (*) => RunUtilityButton(path, name)
}

GetUtilityButtons() {
    global BASE_DIR
    arr := []
    buttonsDir := BASE_DIR "\Buttons"
    
    if !DirExist(buttonsDir)
        return arr
    
    try {
        Loop Files, buttonsDir "\*", "D" {
            folderPath := A_LoopFilePath
            folderName := A_LoopFileName
            
            mainFile := folderPath "\Main.ahk"
            
            if FileExist(mainFile) {
                iconFile := ""
                for ext in ["png", "ico", "jpg", "jpeg"] {
                    testPath := folderPath "\icon." ext
                    if FileExist(testPath) {
                        iconFile := testPath
                        break
                    }
                }
                
                arr.Push({
                    name: folderName,
                    path: mainFile,
                    icon: iconFile
                })
            }
        }
    }
    
    return arr
}

CreateUtilityButtonsGrid(gui, buttons, x, y) {
    global COLORS
    
    if (buttons.Length = 0)
        return
    
    buttonWidth := 115
    buttonHeight := 90
    spacing := 10
    
    xPos := x
    yPos := y
    col := 0
    
    for index, btn in buttons {
        btnPath := btn.path
        btnName := btn.name
        btnIcon := btn.icon
        
        card := gui.Add("Text", 
            "x" xPos " y" yPos " w" buttonWidth " h" buttonHeight 
            " Background" COLORS.card " Border")
        
        iconY := yPos + 12
        iconX := xPos + (buttonWidth - 48) // 2
        
        hasIcon := false
        if (btnIcon != "" && FileExist(btnIcon)) {
            try {
                pic := gui.Add("Picture", 
                    "x" iconX " y" iconY 
                    " w48 h48 BackgroundTrans", 
                    btnIcon)
                hasIcon := true
            }
        }
        
        if (!hasIcon) {
            initial := SubStr(btnName, 1, 1)
            colorOptions := ["0x1f6feb", "0x238636", "0x8957e5", "0xd29922", "0xbc4c00"]
            randColor := colorOptions[Mod(index, colorOptions.Length) + 1]
            
            badge := gui.Add("Text", 
                "x" iconX " y" iconY 
                " w48 h48 Background" randColor " Center", 
                initial)
            badge.SetFont("s20 bold c" COLORS.text)
        }
        
        displayName := FormatUtilityName(btnName)
        labelY := yPos + 65
        
        label := gui.Add("Text", 
            "x" xPos " y" labelY 
            " w" buttonWidth " h22 c" COLORS.text 
            " BackgroundTrans Center", 
            displayName)
        label.SetFont("s8 bold")
        
        clickBtn := gui.Add("Button", 
            "x" xPos " y" yPos 
            " w" buttonWidth " h" buttonHeight, 
            "")
        clickBtn.Opt("Background" COLORS.card)
        clickBtn.Opt("+0x4000000")
        
        clickBtn.OnEvent("Click", MakeUtilityClickHandler(btnPath, btnName))
        
        col++
        xPos += buttonWidth + spacing
        
        if (col >= 4) {
            col := 0
            xPos := x
            yPos += buttonHeight + spacing
        }
    }
}

CreateUtilityBadge(gui, name, x, y, size := 40) {
    global COLORS
    
    initial := SubStr(name, 1, 1)
    iconColor := GetCategoryColor(name)
    
    badge := gui.Add("Text", 
        "x" x " y" y " w" size " h" size 
        " Background" iconColor " Center", 
        initial)
    badge.SetFont("s18 bold c" COLORS.text)
    
    return badge
}

FormatUtilityName(name) {
    result := RegExReplace(name, "([a-z])([A-Z])", "$1 $2")
    
    result := StrReplace(result, "Ahk", "AHK")
    result := StrReplace(result, "Gui", "GUI")
    
    if (StrLen(result) > 15)
        result := SubStr(result, 1, 12) "..."
    
    return result
}

RunUtilityButton(path, name) {
    if !FileExist(path) {
        MsgBox "Utility not found:`n" path, "Error", "Icon!"
        return
    }
    
    try {
        SplitPath path, , &dir
        
        ToolTip "▶ Running: " name
        
        Run '"' A_AhkPath '" "' path '"', dir
        
    } catch as err {

    }
}


; ========== ENHANCED FEATURES: PROFILE MANAGEMENT (NEW!) ==========

LoadUserProfile() {
    global WORKER_URL, DISCORD_ID_FILE, USER_PROFILE, PROFILE_ENABLED
    
    if !PROFILE_ENABLED
        return false
    
    discordId := ReadDiscordId()
    if (discordId = "" || discordId = "Unknown")
        return false
    
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 5000, 5000)
        req.Open("GET", WORKER_URL "/profile/" discordId, false)
        req.Send()
        
        if (req.Status = 200) {
            resp := req.ResponseText
            
            if RegExMatch(resp, '"username"\s*:\s*"([^"]+)"', &m)
                USER_PROFILE["username"] := m[1]
            if RegExMatch(resp, '"bio"\s*:\s*"([^"]+)"', &m)
                USER_PROFILE["bio"] := m[1]
            if RegExMatch(resp, '"total_macros_run"\s*:\s*(\d+)', &m)
                USER_PROFILE["total_macros"] := m[1]
            if RegExMatch(resp, '"profile_picture"\s*:\s*"([^"]+)"', &m)
                USER_PROFILE["picture"] := m[1]
            
            return true
        }
    } catch {
        return false
    }
    
    return false
}

ShowUserHistory() {
    global WORKER_URL, DISCORD_ID_FILE, COLORS
    
    discordId := ReadDiscordId()
    if (discordId = "" || discordId = "Unknown") {
        MsgBox "Discord ID not found!", "Error"
        return
    }
    
    try {
        ToolTip "Loading history..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/profile/history/" discordId, false)
        req.Send()
        
        ToolTip
        
        if (req.Status != 200) {
            MsgBox "Failed to load history!", "Error"
            return
        }
        
        resp := req.ResponseText
        
        total := 0
        if RegExMatch(resp, '"total"\s*:\s*(\d+)', &m)
            total := m[1]
        
        historyGui := Gui(, "My Macro History")
        historyGui.BackColor := COLORS.bg
        historyGui.SetFont("s10 c" COLORS.text, "Segoe UI")
        
        historyGui.Add("Text", "x0 y0 w700 h60 Background" COLORS.accent)
        historyGui.Add("Text", "x20 y15 w660 h30 c" COLORS.text " BackgroundTrans", "📊 My Macro History").SetFont("s16 bold")
        
        historyGui.Add("Text", "x20 y70 w660 c" COLORS.text, "Total Macros Run: " total)
        
        lv := historyGui.Add("ListView", "x20 y100 w660 h400 Background" COLORS.card " c" COLORS.text,
            ["Macro Name", "Category", "Date", "Duration"])
        lv.ModifyCol(1, 250)
        lv.ModifyCol(2, 150)
        lv.ModifyCol(3, 150)
        lv.ModifyCol(4, 100)
        
        pos := 1
        while (pos := RegExMatch(resp, '\{[^}]*"macro_name"[^}]*\}', &match, pos)) {
            eventObj := match[0]
            
            macroName := ""
            category := ""
            timestamp := ""
            duration := ""
            
            if RegExMatch(eventObj, '"macro_name"\s*:\s*"([^"]+)"', &m)
                macroName := m[1]
            if RegExMatch(eventObj, '"category"\s*:\s*"([^"]+)"', &m)
                category := m[1]
            if RegExMatch(eventObj, '"timestamp"\s*:\s*(\d+)', &m)
                timestamp := m[1]
            if RegExMatch(eventObj, '"duration"\s*:\s*(\d+)', &m)
                duration := m[1]
            
            dateStr := FormatTimestampUtil(timestamp)
            durationStr := FormatDurationUtil(duration)
            
            lv.Add(, macroName, category, dateStr, durationStr)
            
            pos += StrLen(match[0]) + match.Pos
        }
        
        lv.ModifyCol()
        
        closeBtn := historyGui.Add("Button", "x20 y510 w660 h40 Background" COLORS.accent, "Close")
        closeBtn.SetFont("s11 bold")
        closeBtn.OnEvent("Click", (*) => historyGui.Destroy())
        
        historyGui.Show("w700 h570")
        
    } catch as err {
        ToolTip
        MsgBox "Error loading history: " err.Message, "Error"
    }
}

ShowPopularMacros() {
    global WORKER_URL, COLORS
    
    try {
        ToolTip "Loading popular macros..."
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", WORKER_URL "/analytics/popular?timeframe=week&limit=20", false)
        req.Send()
        
        ToolTip
        
        if (req.Status != 200) {
            MsgBox "Failed to load popular macros!", "Error"
            return
        }
        
        resp := req.ResponseText
        
        popGui := Gui(, "Popular Macros This Week")
        popGui.BackColor := COLORS.bg
        popGui.SetFont("s10 c" COLORS.text, "Segoe UI")
        
        popGui.Add("Text", "x0 y0 w600 h60 Background" COLORS.accent)
        popGui.Add("Text", "x20 y15 w560 h30 c" COLORS.text " BackgroundTrans", "🏆 Popular Macros").SetFont("s16 bold")
        
        lv := popGui.Add("ListView", "x20 y70 w560 h400 Background" COLORS.card " c" COLORS.text,
            ["Rank", "Macro ID", "Usage Count"])
        lv.ModifyCol(1, 80)
        lv.ModifyCol(2, 350)
        lv.ModifyCol(3, 120)
        
        rank := 1
        pos := 1
        while (pos := RegExMatch(resp, '"macro_id"\s*:\s*"([^"]+)"[^}]*"count"\s*:\s*(\d+)', &m, pos)) {
            lv.Add(, rank, m[1], m[2])
            rank++
            pos += StrLen(m[0])
        }
        
        lv.ModifyCol()
        
        closeBtn := popGui.Add("Button", "x20 y480 w560 h40 Background" COLORS.accent, "Close")
        closeBtn.SetFont("s11 bold")
        closeBtn.OnEvent("Click", (*) => popGui.Destroy())
        
        popGui.Show("w600 h540")
        
    } catch as err {
        ToolTip
        MsgBox "Error loading popular macros: " err.Message, "Error"
    }
}

; ========== ANALYTICS TRACKING (NEW!) ==========

TrackMacroUsage(macroId, macroName, category := "Uncategorized", duration := 0) {
    global WORKER_URL, SESSION_TOKEN_FILE, ANALYTICS_ENABLED
    
    if !ANALYTICS_ENABLED
        return false
    
    if !FileExist(SESSION_TOKEN_FILE)
        return false
    
    try {
        sessionToken := Trim(FileRead(SESSION_TOKEN_FILE))
        
        body := '{"session_token":"' JsonEscape(sessionToken) '",'
              . '"macro_id":"' JsonEscape(macroId) '",'
              . '"macro_name":"' JsonEscape(macroName) '",'
              . '"category":"' JsonEscape(category) '",'
              . '"duration":' duration '}'
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 5000, 5000)
        req.Open("POST", WORKER_URL "/analytics/track", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
        
        return (req.Status = 200)
    } catch {
        return false
    }
}

; ========== UTILITY FUNCTIONS (NEW!) ==========

FileToBase64(filepath) {
    f := FileOpen(filepath, "r")
    f.RawRead(data := Buffer(f.Length))
    f.Close()
    
    return BinaryToBase64(data, f.Length)
}

BinaryToBase64(data, size) {
    static CRYPT_STRING_BASE64 := 0x1
    static CRYPT_STRING_NOCRLF := 0x40000000
    
    DllCall("Crypt32\CryptBinaryToString", "Ptr", data, "UInt", size, 
            "UInt", CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, 
            "Ptr", 0, "UInt*", &chars := 0)
    
    base64 := Buffer(chars * 2)
    DllCall("Crypt32\CryptBinaryToString", "Ptr", data, "UInt", size,
            "UInt", CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF,
            "Ptr", base64, "UInt*", &chars)
    
    return StrGet(base64, "UTF-16")
}

FormatTimestampUtil(timestamp) {
    if (timestamp = 0 || timestamp = "")
        return "Unknown"
    
    try {
        seconds := Integer(timestamp) / 1000
        nowSeconds := DateDiff(A_Now, "19700101000000", "Seconds")
        diff := nowSeconds - seconds
        
        if (diff < 3600)
            return Floor(diff / 60) " minutes ago"
        else if (diff < 86400)
            return Floor(diff / 3600) " hours ago"
        else if (diff < 604800)
            return Floor(diff / 86400) " days ago"
        else
            return Floor(diff / 604800) " weeks ago"
    } catch {
        return "Recently"
    }
}

FormatDurationUtil(ms) {
    if (ms < 1000)
        return ms " ms"
    else if (ms < 60000)
        return Floor(ms / 1000) " sec"
    else if (ms < 3600000)
        return Floor(ms / 60000) " min"
    else
        return Floor(ms / 3600000) " hr"
}

JsonExtractAny(jsonStr, key) {
    if RegExMatch(jsonStr, '"' key '"\s*:\s*"([^"]*)"', &m)
        return m[1]
    if RegExMatch(jsonStr, '"' key '"\s*:\s*(\d+)', &m)
        return m[1]
    return ""
}

NoCacheUrl(url) {
    separator := InStr(url, "?") ? "&" : "?"
    return url . separator . "nocache=" . A_TickCount
}