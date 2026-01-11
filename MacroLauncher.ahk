#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

global LAUNCHER_VERSION := "2.0.5"

; ================= CONFIG =================
global APP_DIR := A_AppData "\MacroLauncher"
global BASE_DIR := APP_DIR "\Macros"
global TRAY_DIR := BASE_DIR "\Icons"
global VERSION_FILE := APP_DIR "\version.txt"
global ICON_DIR := BASE_DIR "\Icons"
global MANIFEST_URL := "https://raw.githubusercontent.com/lewiswr2/macro-launcher-updates/main/manifest.json"
global mainGui := 0

global COLORS := {
    bg: "0x0a0e14",
    bgLight: "0x13171d",
    card: "0x161b22",
    cardHover: "0x1c2128",
    accent: "0x006eff",
    accentHover: "0x0011ff",
    accentAlt: "0x1f6feb",
    text: "0xe6edf3",
    textDim: "0x7d8590",
    border: "0x21262d",
    success: "0x238636",
    warning: "0xd29922",
    danger: "0xda3633"
}

; =========================================
try {
    DirCreate APP_DIR
    DirCreate BASE_DIR
    DirCreate ICON_DIR
} catch as err {
    MsgBox "Failed to create application directories: " err.Message "`n`nThe launcher may not work correctly.", "Initialization Error", "Icon!"
}

SetTrayIcon() {
    global TRAY_DIR
    trayIconPath := TRAY_DIR "\Launcher.png"

    ; Check if the file exists
    if !FileExist(trayIconPath) {
        MsgBox("Tray icon not found: " trayIconPath)
        return
    }

    ; Create or get the tray menu
    tray := Menu()
    tray.Icon := trayIconPath  ; <-- sets the tray icon
}

EnsureVersionFile()
SetTaskbarIcon()
CheckForLauncherUpdate()
CheckForUpdatesPrompt()
CreateMainGui()
SetTrayIcon()

EnsureVersionFile() {
    global VERSION_FILE
    if !FileExist(VERSION_FILE) {
        try {
            FileAppend "0", VERSION_FILE
        } catch {
        }
    }
}

SetTaskbarIcon() {
    global ICON_DIR
    iconPath := ICON_DIR "\launcher.png"
    
    try {
        if FileExist(iconPath) {
            TraySetIcon(iconPath)
        } else {
            TraySetIcon("shell32.dll", 3)
        }
    } catch {
    }
}

CheckForUpdatesPrompt() {
    global MANIFEST_URL, VERSION_FILE, BASE_DIR, APP_DIR, ICON_DIR

    tmpManifest := A_Temp "\manifest.json"
    tmpZip := A_Temp "\Macros.zip"
    extractDir := A_Temp "\macro_extract"
    backupDir := A_Temp "\macro_backup_" A_Now

    if !SafeDownload(MANIFEST_URL, tmpManifest) {
        return
    }

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
        "V1LN AHK Vault Update",
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

    backupSuccess := false
    if DirExist(BASE_DIR) {
        try {
            DirCreate backupDir
            Loop Files, BASE_DIR "\*", "D"
                TryDirMove(A_LoopFilePath, backupDir "\" A_LoopFileName, true)
            backupSuccess := true
        } catch as err {
            backupSuccess := false
        }
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
        try {
            if backupSuccess {
                if DirExist(BASE_DIR)
                    DirDelete BASE_DIR, true
                DirCreate BASE_DIR
                Loop Files, backupDir "\*", "D"
                    TryDirMove(A_LoopFilePath, BASE_DIR "\" A_LoopFileName, true)
            }
        } catch {
        }

        ShowUpdateFail(
            "Install / move folders",
            err,
            "BASE_DIR=`n" BASE_DIR "`n`nextractDir=`n" extractDir "`n`nTip: close MacroLauncher & disable Controlled Folder Access/AV if blocking AppData."
        )
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
        RunWait 'attrib +h +s "' APP_DIR '"', , "Hide"
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
        updateMsg .= "✓ Icons updated`n"
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
    global MANIFEST_URL, VERSION_FILE, BASE_DIR, APP_DIR, ICON_DIR
    
    choice := MsgBox(
        "Check for macro updates?`n`n"
        "This will download the latest macros from the repository.",
        "Check for Updates",
        "YesNo Iconi"
    )
    
    if (choice = "No") {
        return
    }
    
    ; 🔥 DELETE VERSION FILE BEFORE CHECKING
    try {
        if FileExist(VERSION_FILE)
            FileDelete VERSION_FILE
    } catch {
    }
    
    tmpManifest := A_Temp "\manifest.json"
    tmpZip := A_Temp "\Macros.zip"
    extractDir := A_Temp "\macro_extract"
    backupDir := A_Temp "\macro_backup_" A_Now
    
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
    
    if (choice = "No") {
        return
    }
    
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
                    if (attempts < maxAttempts) {
                        Sleep 1000
                    }
                }
            } catch {
                if (attempts < maxAttempts) {
                    Sleep 1000
                }
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
        if DirExist(extractDir) {
            DirDelete extractDir, true
        }
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
        if DirExist(extractDir "\Macros") {
            hasMacrosFolder := true
        }
        if DirExist(extractDir "\icons") {
            hasIconsFolder := true
        }
        
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
    
    backupSuccess := false
    if DirExist(BASE_DIR) {
        try {
            DirCreate backupDir
            Loop Files, BASE_DIR "\*", "D" {
                DirMove A_LoopFilePath, backupDir "\" A_LoopFileName, 1
            }
            backupSuccess := true
        } catch {
        }
    }
    
    installSuccess := false
    try {
        if DirExist(BASE_DIR) {
            DirDelete BASE_DIR, true
        }
        DirCreate BASE_DIR
        
        if useNestedStructure {
            Loop Files, extractDir "\Macros\*", "D" {
                DirMove A_LoopFilePath, BASE_DIR "\" A_LoopFileName, 1
            }
        } else {
            Loop Files, extractDir "\*", "D" {
                if (A_LoopFileName != "icons") {
                    DirMove A_LoopFilePath, BASE_DIR "\" A_LoopFileName, 1
                }
            }
        }
        installSuccess := true
    } catch as err {
        MsgBox "Failed to install macro update: " err.Message, "Error", "Icon!"
        
        if backupSuccess {
            try {
                if DirExist(BASE_DIR) {
                    DirDelete BASE_DIR, true
                }
                DirCreate BASE_DIR
                
                Loop Files, backupDir "\*", "D" {
                    DirMove A_LoopFilePath, BASE_DIR "\" A_LoopFileName, 1
                }
                MsgBox "Update failed but your macros were restored from backup.", "Restored", "Iconi"
            } catch {
                MsgBox(
                    "Critical error: Update failed and rollback failed.`n`n"
                    "Backup location:`n" backupDir,
                    "Critical Error",
                    "Icon!"
                )
            }
        }
        return
    }
    
    iconsUpdated := false
    iconBackupDir := A_Temp "\icon_backup_" A_Now
    iconBackupSuccess := false
    
    if DirExist(extractDir "\icons") {
        try {
            if DirExist(ICON_DIR) {
                DirCreate iconBackupDir
                Loop Files, ICON_DIR "\*.*" {
                    FileCopy A_LoopFilePath, iconBackupDir "\" A_LoopFileName, 1
                }
                iconBackupSuccess := true
            }
        }
        
        try {
            if !DirExist(ICON_DIR) {
                DirCreate ICON_DIR
            }
        }
        
        try {
            iconCount := 0
            Loop Files, extractDir "\icons\*.*" {
                FileCopy A_LoopFilePath, ICON_DIR "\" A_LoopFileName, 1
                iconCount++
            }
            
            if (iconCount > 0) {
                iconsUpdated := true
            }
            
            if iconBackupSuccess && DirExist(iconBackupDir) {
                try {
                    DirDelete iconBackupDir, true
                }
            }
        } catch as err {
            if iconBackupSuccess {
                try {
                    Loop Files, iconBackupDir "\*.*" {
                        FileCopy A_LoopFilePath, ICON_DIR "\" A_LoopFileName, 1
                    }
                }
            }
        }
    }
    
    if installSuccess && backupSuccess {
        try {
            if DirExist(backupDir) {
                DirDelete backupDir, true
            }
        }
    }
    
    try {
        if FileExist(VERSION_FILE) {
            FileDelete VERSION_FILE
        }
        FileAppend manifest.version, VERSION_FILE
        RunWait 'attrib +h +s "' APP_DIR '"', , "Hide"
    }
    
    try {
        if FileExist(tmpZip) {
            FileDelete tmpZip
        }
        if DirExist(extractDir) {
            DirDelete extractDir, true
        }
    }
    
    updateMsg := "Update complete!`n`nVersion " manifest.version " installed.`n`n"
    if iconsUpdated {
        updateMsg .= "✓ Icons updated`n"
    }
    updateMsg .= "`nChanges:`n" changelogText "`n`nRestart the launcher to see changes."
    
    MsgBox(updateMsg, "Update Finished", "Iconi")
    
    try {
        mainGui.Destroy()
        CreateMainGui()
    }
}

SafeDownload(url, out, timeoutMs := 10000) {
    if !url || !out {
        return false
    }
    
    try {
        if FileExist(out) {
            FileDelete out
        }
        
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
    if !json {
        return false
    }
    
    manifest := {
        version: "",
        zip_url: "",
        changelog: [],
        launcher_version: "",
        launcher_url: ""
    }
    
    try {
        if RegExMatch(json, '"version"\s*:\s*"([^"]+)"', &m) {
            manifest.version := m[1]
        }
        
        if RegExMatch(json, '"zip_url"\s*:\s*"([^"]+)"', &m) {
            manifest.zip_url := m[1]
        }
        
        if RegExMatch(json, '"launcher_version"\s*:\s*"([^"]+)"', &m) {
            manifest.launcher_version := m[1]
        }
        
        if RegExMatch(json, '"launcher_url"\s*:\s*"([^"]+)"', &m) {
            manifest.launcher_url := m[1]
        }
        
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
    
    if (!manifest.version || !manifest.zip_url) {
        return false
    }
    
    return manifest
}

CreateMainGui() {
    global mainGui, COLORS, BASE_DIR, ICON_DIR
    
    mainGui := Gui("-Resize +Border", " V1LN AHK Vault")
    mainGui.BackColor := COLORS.bg
    mainGui.SetFont("s10", "Segoe UI")
    
    iconPath := ICON_DIR "\1.png"
    if FileExist(iconPath) {
        try {
            mainGui.Show("Hide")
            mainGui.Opt("+Icon" iconPath)
        }
    }
    
    mainGui.Add("Text", "x0 y0 w550 h80 Background" COLORS.accent)
    
    ahkImage := ICON_DIR "\AHK.png"
    if FileExist(ahkImage) {
        try {
            mainGui.Add("Picture", "x20 y15 w50 h50 BackgroundTrans", ahkImage)
        }
    }
    
    titleText := mainGui.Add("Text", "x80 y20 w280 h100 c" COLORS.text " BackgroundTrans", " V1LN AHK Vault")
    titleText.SetFont("s24 bold")
    
    btnUpdate := mainGui.Add("Button", "x370 y25 w75 h35 Background" COLORS.success, "Update")
    btnUpdate.SetFont("s10")
    btnUpdate.OnEvent("Click", ManualUpdate)
    
    btnLog := mainGui.Add("Button", "x450 y25 w75 h35 Background" COLORS.accentHover, "Changelog")
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
            "No game categories found`n`nPlace game folders in:`n" BASE_DIR)
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
    CreateLink(mainGui, "Discord", "https://discord.gg/v1ln", 25, linkY)
    linkY := bottomY + 35
    CreateLink(mainGui, "The Creators Discord", "https://discord.gg/mgkwyAWvYK", 25, linkY)
    
    mainGui.Show("w550 h" (bottomY + 60) " Center")
}

GetCategories() {
    global BASE_DIR
    arr := []
    
    if !DirExist(BASE_DIR) {
        return arr
    }
    
    try {
        Loop Files, BASE_DIR "\*", "D" {
            if (StrLower(A_LoopFileName) = "icons") {
                continue
            }
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
        if FileExist(iconPath) {
            return iconPath
        }
    }
    
    for ext in extensions {
        iconPath := BASE_DIR "\" category "." ext
        if FileExist(iconPath) {
            return iconPath
        }
    }
    
    for ext in extensions {
        iconPath := BASE_DIR "\" category "\icon." ext
        if FileExist(iconPath) {
            return iconPath
        }
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

OpenCategory(category) {
    global COLORS, BASE_DIR
    
    macros := GetMacrosWithInfo(category)
    
    if (macros.Length = 0) {
        MsgBox(
            "No macros found in '" category "'`n`n"
            "To add macros:`n"
            "1. Create a 'Main.ahk' file in each subfolder`n"
            "2. Or run the update to download macros`n`n"
            "Folder location:`n" BASE_DIR "\" category,
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
    
    title := win.Add("Text", "x105 y20 w500 h100 c" COLORS.text " BackgroundTrans", category)
    title.SetFont("s22 bold")
    
    win.__scrollY := 110
    
    win.OnEvent("Close", (*) => win.Destroy())
    
    RenderCards(win)
    
    win.Show("w750 h640 Center")
}

RenderCards(win) {
    global COLORS
    
    if !win.HasProp("__data") {
        return
    }
    
    if win.HasProp("__cards") && win.__cards.Length > 0 {
        for ctrl in win.__cards {
            try {
                ctrl.Destroy()
            } catch {
            }
        }
    }
    win.__cards := []
    
    macros := win.__data
    scrollY := win.__scrollY
    
    if (macros.Length = 0) {
        noResult := win.Add("Text", "x25 y" scrollY " w700 h100 c" COLORS.textDim " Center", 
            "No macros found")
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
    
    ; Special case: only 1 macro = full width
    if (itemsToShow = 1) {
        item := macros[startIdx]
        CreateFullWidthCard(win, item, 25, scrollY, 700, 110)
    } else {
        ; Grid: 2 columns, 4 rows
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
    
    ; Pagination controls
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
    
    titleCtrl := win.Add("Text", "x" (x + 120) " y" (y + 20) " w420 h100 c" COLORS.text " BackgroundTrans", item.info.Title)
    titleCtrl.SetFont("s13 bold")
    win.__cards.Push(titleCtrl)
    
    creatorCtrl := win.Add("Text", "x" (x + 120) " y" (y + 50) " w420 c" COLORS.textDim " BackgroundTrans", "by " item.info.Creator)
    creatorCtrl.SetFont("s10")
    win.__cards.Push(creatorCtrl)
    
    versionCtrl := win.Add("Text", "x" (x + 120) " y" (y + 75) " w60 h22 Background" COLORS.accentAlt " c" COLORS.text " Center", "v" item.info.Version)
    versionCtrl.SetFont("s9 bold")
    win.__cards.Push(versionCtrl)
    
    currentPath := item.path
    runBtn := win.Add("Button", "x" (x + w - 110) " y" (y + 20) " w100 h35 Background" COLORS.success, "▶ Run")
    runBtn.SetFont("s11 bold")
    runBtn.OnEvent("Click", (*) => RunMacro(currentPath))
    win.__cards.Push(runBtn)
    
    if (Trim(item.info.Links) != "") {
        currentLinks := item.info.Links
        linksBtn := win.Add("Button", "x" (x + w - 110) " y" (y + 65) " w100 h30 Background" COLORS.accentAlt, "🔗 Links")
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
    
titleCtrl := win.Add(
    "Text"
  , "x" (x + 90)
  . " y" (y + 15)
  . " w" (w - 190)
  . " h" (h + 50)
  . " c" COLORS.text
  . " BackgroundTrans"
  , item.info.Title
)
titleCtrl.SetFont("s11 bold")
win.__cards.Push(titleCtrl)
    
    creatorCtrl := win.Add("Text", "x" (x + 90) " y" (y + 40) " w" (w - 190) " c" COLORS.textDim " BackgroundTrans", "by " item.info.Creator)
    creatorCtrl.SetFont("s9")
    win.__cards.Push(creatorCtrl)
    
    versionCtrl := win.Add("Text", "x" (x + 90) " y" (y + 65) " w50 h20 Background" COLORS.accentAlt " c" COLORS.text " Center", "v" item.info.Version)
    versionCtrl.SetFont("s8 bold")
    win.__cards.Push(versionCtrl)
    
    currentPath := item.path
    runBtn := win.Add("Button", "x" (x + w - 90) " y" (y + 15) " w80 h30 Background" COLORS.success, "▶ Run")
    runBtn.SetFont("s10 bold")
    runBtn.OnEvent("Click", (*) => RunMacro(currentPath))
    win.__cards.Push(runBtn)
    
    if (Trim(item.info.Links) != "") {
        currentLinks := item.info.Links
        linksBtn := win.Add("Button", "x" (x + w - 90) " y" (y + 55) " w80 h25 Background" COLORS.accentAlt, "🔗 Links")
        linksBtn.SetFont("s9")
        linksBtn.OnEvent("Click", (*) => OpenLinks(currentLinks))
        win.__cards.Push(linksBtn)
    }
}

ChangePage(win, direction) {
    win.__currentPage := win.__currentPage + direction
    
    totalPages := Ceil(win.__data.Length / win.__itemsPerPage)
    
    if (win.__currentPage < 1) {
        win.__currentPage := 1
    }
    if (win.__currentPage > totalPages) {
        win.__currentPage := totalPages
    }
    
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
            if FileExist(iconPath) {
                return iconPath
            }
        }
        
        for ext in extensions {
            iconPath := macroDir "\icon." ext
            if FileExist(iconPath) {
                return iconPath
            }
        }
        
        SplitPath macroDir, , &gameDir
        for ext in extensions {
            iconPath := gameDir "\" macroName "." ext
            if FileExist(iconPath) {
                return iconPath
            }
        }
    }
    
    return ""
}

GetMacrosWithInfo(category) {
    global BASE_DIR
    out := []
    base := BASE_DIR "\" category
    
    if !DirExist(base) {
        return out
    }
    
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
    
    return out
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
    }
    
    ini := macroDir "\info.ini"
    if !FileExist(ini) {
        return info
    }
    
    try {
        txt := FileRead(ini, "UTF-8")
    } catch {
        return info
    }
    
    for line in StrSplit(txt, "`n") {
        line := Trim(StrReplace(line, "`r"))
        
        if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#") {
            continue
        }
        
        if !InStr(line, "=") {
            continue
        }
        
        parts := StrSplit(line, "=", , 2)
        if (parts.Length < 2) {
            continue
        }
        
        k := StrLower(Trim(parts[1]))
        v := Trim(parts[2])
        
        switch k {
            case "title":
                info.Title := v
            case "creator":
                info.Creator := v
            case "version":
                info.Version := v
            case "links":
                info.Links := v
        }
    }
    
    if (info.Version = "") {
        info.Version := "1.0"
    }
    
    return info
}

RunMacro(path) {
    if !FileExist(path) {
        MsgBox "Macro not found:`n" path, "Error", "Icon!"
        return
    }
    
    try {
        SplitPath path, , &dir
        Run '"' A_AhkPath '" "' path '"', dir
    } catch as err {
        MsgBox "Failed to run macro: " err.Message, "Error", "Icon!"
    }
}

OpenLinks(links) {
    if !links || Trim(links) = "" {
        return
    }
    
    try {
        for url in StrSplit(links, "|") {
            url := Trim(url)
            if (url != "") {
                SafeOpenURL(url)
            }
        }
    } catch as err {
        MsgBox "Failed to open link: " err.Message, "Error", "Icon!"
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
    
    if (text = "") {
        text := "(No changelog available)"
    }
    
    MsgBox "Version: " manifest.version "`n`n" text, "Changelog", "Iconi"
}

CheckForLauncherUpdate() {
    global MANIFEST_URL, LAUNCHER_VERSION
    
    tmpManifest := A_Temp "\manifest.json"
    
    if !SafeDownload(MANIFEST_URL, tmpManifest) {
        return
    }
    
    json := ""
    try {
        json := FileRead(tmpManifest, "UTF-8")
    } catch {
        return
    }
    
    manifest := ParseManifest(json)
    if !manifest {
        return
    }
    
    if (!manifest.launcher_version || !manifest.launcher_url) {
        return
    }
    
    if VersionCompare(manifest.launcher_version, LAUNCHER_VERSION) <= 0 {
        return
    }
    
    DoSelfUpdate(manifest.launcher_url, manifest.launcher_version)
}

DoSelfUpdate(url, newVer) {
    tmpNew := A_Temp "\launcher_new.ahk"
    
    if !SafeDownload(url, tmpNew, 30000) {
        MsgBox "Download failed.`n`nCheck your internet connection.", "Error", "Icon!"
        return
    }
    
    try {
        content := FileRead(tmpNew, "UTF-8")
        
        if (!InStr(content, "#Requires AutoHotkey")) {
            MsgBox "Downloaded file doesn't appear to be a valid AHK script.", "Error", "Icon!"
            try FileDelete tmpNew
            return
        }
    } catch {
        MsgBox "Failed to validate downloaded update.", "Error", "Icon!"
        return
    }
    
    me := A_ScriptFullPath
    cmdPath := A_Temp "\update_launcher.cmd"
    
    cmd := (
        '@echo off' "`r`n"
        'chcp 65001>nul' "`r`n"
        'echo Updating V1LN AHK Vault Launcher...' "`r`n"
        'timeout /t 2 /nobreak >nul' "`r`n"
        'copy /y "' tmpNew '" "' me '" >nul' "`r`n"
        'if errorlevel 1 (' "`r`n"
        '    echo Update failed!' "`r`n"
        '    pause' "`r`n"
        '    goto :end' "`r`n"
        ')' "`r`n"
        'timeout /t 1 /nobreak >nul' "`r`n"
        'start "" "' A_AhkPath '" "' me '"' "`r`n"
        ':end' "`r`n"
        'del /q "' tmpNew '" >nul 2>nul' "`r`n"
        'del /q "%~f0" >nul 2>nul' "`r`n"
    )
    
    try {
        if FileExist(cmdPath) {
            FileDelete cmdPath
        }
        FileAppend cmd, cmdPath, "UTF-8"
        Run '"' cmdPath '"', , "Hide"
        Sleep 500
        ExitApp
    } catch as err {
        MsgBox "Update failed: " err.Message, "Error", "Icon!"
    }
}

ExtractZipShell(zipPath, destDir) {
    try {
        if DirExist(destDir)
            DirDelete destDir, true
        DirCreate destDir

        shell := ComObject("Shell.Application")
        zip := shell.NameSpace(zipPath)
        if !zip
            throw Error("Shell.NameSpace(zip) failed. Not a readable ZIP path.")

        dest := shell.NameSpace(destDir)
        if !dest
            throw Error("Shell.NameSpace(dest) failed.")

        ; 16 = Yes to all overwrite prompts
        dest.CopyHere(zip.Items(), 16)

        ; wait for extraction to finish (simple heuristic)
        t0 := A_TickCount
        Loop 60 {
            if HasAnyFileOrFolder(destDir)
                break
            Sleep 250
        }
        if !HasAnyFileOrFolder(destDir)
            throw Error("Extraction produced no files/folders (timeout).")

        return true
    } catch as err {
        MsgBox "❌ EXTRACTION FAILED:`n" err.Message, "Update", "Icon! 0x10"
        return false
    }
}

HasAnyFileOrFolder(dir) {
    try {
        Loop Files, dir "\*", "FD"
            return true
    }
    return false
}

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

FindTopFolder(extractDir) {
    ; If zip extracts as one top folder (common with GitHub zips), return it
    folders := []
    try {
        Loop Files, extractDir "\*", "D"
            folders.Push(A_LoopFilePath)
    }
    if (folders.Length = 1)
        return folders[1]
    return extractDir
}
ShowUpdateFail(context, err, extra := "") {
    msg := "❌ Failed to install macro updates`n`n"
        . "Step: " context "`n"
        . "Error: " err.Message "`n`n"
        . "Extra: " extra "`n`n"
        . "A_LastError: " A_LastError "`n"
        . "A_WorkingDir: " A_WorkingDir "`n"
        . "AppData: " A_AppData

    MsgBox msg, "V1LN AHK Vault - Update Failed", "Icon! 0x10"
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
