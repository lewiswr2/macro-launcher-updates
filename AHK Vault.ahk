#Requires AutoHotkey v2.0
#SingleInstance Force

global LAUNCHER_VERSION := "2.0.3"

; ================= CONFIG =================
global APP_DIR := A_AppData "\MacroLauncher"
global BASE_DIR := APP_DIR "\Macros"
global VERSION_FILE := APP_DIR "\version.txt"
global ICON_DIR := APP_DIR "\icons"
global MANIFEST_URL := "https://raw.githubusercontent.com/lewiswr2/macro-launcher-updates/main/manifest.json"
global mainGui := 0

global COLORS := {
    bg: "0x0a0e14",
    bgLight: "0x13171d",
    card: "0x161b22",
    cardHover: "0x1c2128",
    accent: "0x238636",
    accentHover: "0x2ea043",
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

EnsureVersionFile()
SetTaskbarIcon()
CheckForLauncherUpdate()
CheckForUpdatesPrompt()
CreateMainGui()

EnsureVersionFile() {
    global VERSION_FILE
    if !FileExist(VERSION_FILE) {
        try {
            FileAppend "0", VERSION_FILE
        } catch {
            ; Silent fail - will default to "0" when read
        }
    }
}

SetTaskbarIcon() {
    global ICON_DIR
    iconPath := ICON_DIR "\Launcher.png"
    
    try {
        if FileExist(iconPath) {
            TraySetIcon(iconPath)
        } else {
            TraySetIcon("shell32.dll", 3)
        }
    } catch {
        ; Icon setting failed - not critical
    }
}

CheckForUpdatesPrompt() {
    global MANIFEST_URL, VERSION_FILE, BASE_DIR, APP_DIR
    
    tmpManifest := A_Temp "\manifest.json"
    tmpZip := A_Temp "\Macros.zip"
    extractDir := A_Temp "\macro_extract"
    backupDir := A_Temp "\macro_backup_" A_Now
    
    if !SafeDownload(MANIFEST_URL, tmpManifest) {
        ; Silent fail on startup - user can manually check via changelog button
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
    
    current := "0"
    try {
        if FileExist(VERSION_FILE) {
            current := Trim(FileRead(VERSION_FILE))
        }
    }
    
    if VersionCompare(manifest.version, current) <= 0 {
        return
    }
    
    changelogText := ""
    for line in manifest.changelog {
        changelogText .= "• " line "`n"
    }
    
    choice := MsgBox(
        "Update available!`n`n"
        "Current: " current "`n"
        "Latest: " manifest.version "`n`n"
        "What's new:`n" changelogText "`n"
        "Do you want to update now?",
        "AHK Vault Update",
        "YesNo Iconi"
    )
    
    if (choice = "No") {
        return
    }
    
    ; Download with retry
    downloadSuccess := false
    attempts := 0
    maxAttempts := 3
    
    while (!downloadSuccess && attempts < maxAttempts) {
        attempts++
        
        if SafeDownload(manifest.zip_url, tmpZip, 30000) {
            ; Validate download
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
            "Please check your internet connection and try again later.",
            "Download Failed",
            "Icon!"
        )
        return
    }
    
    ; Extract
    try {
        if DirExist(extractDir) {
            DirDelete extractDir, true
        }
        DirCreate extractDir
    } catch as err {
        MsgBox "Failed to create extraction directory: " err.Message, "Error", "Icon!"
        return
    }
    
    ; Try tar extraction
    extractSuccess := false
    try {
        RunWait 'tar -xf "' tmpZip '" -C "' extractDir '"', , "Hide"
        
        ; Verify extraction
        hasContent := false
        try {
            Loop Files, extractDir "\*", "D" {
                hasContent := true
                break
            }
        }
        extractSuccess := hasContent
    } catch {
        ; tar failed - try PowerShell as fallback
    }
    
    ; Fallback to PowerShell if tar failed
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
                "Both tar and PowerShell extraction methods failed.`n"
                "Please extract the update manually or reinstall the launcher.",
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
    
    ; Backup existing macros
    backupSuccess := false
    if DirExist(BASE_DIR) {
        try {
            DirCreate backupDir
            Loop Files, BASE_DIR "\*", "D" {
                DirMove A_LoopFilePath, backupDir "\" A_LoopFileName, 1
            }
            backupSuccess := true
        } catch {
            ; Backup failed but continue anyway
        }
    }
    
    ; Install update - Macros
    installSuccess := false
    try {
        if DirExist(BASE_DIR) {
            DirDelete BASE_DIR, true
        }
        DirCreate BASE_DIR
        
        Loop Files, extractDir "\Macros\*", "D" {
            DirMove A_LoopFilePath, BASE_DIR "\" A_LoopFileName, 1
        }
        installSuccess := true
    } catch as err {
        MsgBox "Failed to install macro update: " err.Message, "Error", "Icon!"
        
        ; Try to restore from backup
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
    
    ; Install update - Icons
    iconsUpdated := false
    iconBackupDir := A_Temp "\icon_backup_" A_Now
    iconBackupSuccess := false
    
    if DirExist(extractDir "\icons") {
        ; Backup existing icons
        try {
            if DirExist(ICON_DIR) {
                DirCreate iconBackupDir
                Loop Files, ICON_DIR "\*.*" {
                    FileCopy A_LoopFilePath, iconBackupDir "\" A_LoopFileName, 1
                }
                iconBackupSuccess := true
            }
        }
        
        ; Install new icons
        try {
            Loop Files, extractDir "\icons\*.*" {
                FileCopy A_LoopFilePath, ICON_DIR "\" A_LoopFileName, 1
            }
            iconsUpdated := true
            
            ; Cleanup icon backup if successful
            if iconBackupSuccess && DirExist(iconBackupDir) {
                try DirDelete iconBackupDir, true
            }
        } catch as err {
            ; Icon update failed - restore backup
            if iconBackupSuccess {
                try {
                    Loop Files, iconBackupDir "\*.*" {
                        FileCopy A_LoopFilePath, ICON_DIR "\" A_LoopFileName, 1
                    }
                }
            }
        }
    }
    
    ; Cleanup backup if install succeeded
    if installSuccess && backupSuccess {
        try {
            if DirExist(backupDir) {
                DirDelete backupDir, true
            }
        }
    }
    
    ; Update version file
    try {
        if FileExist(VERSION_FILE) {
            FileDelete VERSION_FILE
        }
        FileAppend manifest.version, VERSION_FILE
        RunWait 'attrib +h +s "' APP_DIR '"', , "Hide"
    }
    
    ; Cleanup temp files
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
    updateMsg .= "`nChanges:`n" changelogText
    
    MsgBox(updateMsg, "Update Finished", "Iconi")
}

SafeDownload(url, out, timeoutMs := 10000) {
    if !url || !out {
        return false
    }
    
    try {
        if FileExist(out) {
            FileDelete out
        }
        
        Download url, out
        
        ; Wait for file with timeout
        startTime := A_TickCount
        while !FileExist(out) {
            if (A_TickCount - startTime > timeoutMs) {
                return false
            }
            Sleep 100
        }
        
        return FileExist(out) ? true : false
    } catch {
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
        ; Extract version
        if RegExMatch(json, '"version"\s*:\s*"([^"]+)"', &m) {
            manifest.version := m[1]
        }
        
        ; Extract zip_url
        if RegExMatch(json, '"zip_url"\s*:\s*"([^"]+)"', &m) {
            manifest.zip_url := m[1]
        }
        
        ; Extract launcher_version
        if RegExMatch(json, '"launcher_version"\s*:\s*"([^"]+)"', &m) {
            manifest.launcher_version := m[1]
        }
        
        ; Extract launcher_url
        if RegExMatch(json, '"launcher_url"\s*:\s*"([^"]+)"', &m) {
            manifest.launcher_url := m[1]
        }
        
        ; Extract changelog array
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
    
    ; Validate required fields
    if (!manifest.version || !manifest.zip_url) {
        return false
    }
    
    return manifest
}

CreateMainGui() {
    global mainGui, COLORS, BASE_DIR, ICON_DIR
    
    mainGui := Gui("-Resize +Border", "AHK Vault")
    mainGui.BackColor := COLORS.bg
    mainGui.SetFont("s10", "Segoe UI")
    
    iconPath := ICON_DIR "\Launcher.png"
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
    
    titleText := mainGui.Add("Text", "x80 y20 w330 h100 c" COLORS.text " BackgroundTrans", "AHK Vault")
    titleText.SetFont("s24 bold")
    
    btnLog := mainGui.Add("Button", "x420 y25 w105 h35 Background" COLORS.accentHover, "Changelog")
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
    CreateLink(mainGui, "Discord", "https://discord.gg/xVmSTVxQt9", 25, linkY)
    CreateLink(mainGui, "YouTube", "https://www.youtube.com/@Reversals-ux9tg", 115, linkY)
    CreateLink(mainGui, "Guide", "https://docs.google.com/document/d/1Z3_9i0TE8WTX0J5o9iwnJ1ybOJ7LFtKeuhTpcumtHXk/edit?tab=t.0", 215, linkY)
    
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
        iconPath := BASE_DIR "\" category "." ext
        if FileExist(iconPath) {
            return iconPath
        }
    }
    
    for ext in extensions {
        iconPath := ICON_DIR "\" category "." ext
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
    
    ; Basic URL validation
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
    win.__currentSort := "Name (A-Z)"
    
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
    
    controlY := 110
    
    searchLabel := win.Add("Text", "x25 y" controlY " w60 c" COLORS.text, "Search:")
    searchLabel.SetFont("s9 bold")
    
    searchBox := win.Add("Edit", "x85 y" (controlY - 3) " w180 h28 Background" COLORS.card " c" COLORS.text)
    searchBox.SetFont("s10")
    win.__searchBox := searchBox
    searchBox.OnEvent("Change", (*) => CategorySearchChanged(win))
    
    sortLabel := win.Add("Text", "x285 y" controlY " w40 c" COLORS.text, "Sort:")
    sortLabel.SetFont("s9 bold")
    
    sortOptions := ["Name (A-Z)", "Name (Z-A)", "Creator (A-Z)", "Creator (Z-A)", "Version (High)", "Version (Low)"]
    sortDDL := win.Add("DropDownList", "x330 y" (controlY - 4) " w145 h200 Background" COLORS.card " c" COLORS.text, sortOptions)
    sortDDL.SetFont("s9")
    sortDDL.Choose(1)
    win.__sortDDL := sortDDL
    sortDDL.OnEvent("Change", (*) => SortChanged(win))
    
    filterLabel := win.Add("Text", "x495 y" controlY " w70 c" COLORS.text, "Creator:")
    filterLabel.SetFont("s9 bold")
    
    creatorDDL := win.Add("DropDownList", "x565 y" (controlY - 4) " w160 h200 Background" COLORS.card " c" COLORS.text, ["All"])
    creatorDDL.SetFont("s9")
    win.__creatorDDL := creatorDDL
    creatorDDL.OnEvent("Change", (*) => CategoryFilterChanged(win))
    
    PopulateCreatorFilter(win)
    
    win.__scrollY := 155
    RenderMacroCards(win, "All", "", "Name (A-Z)")
    
    win.Show("w750 Center")
}

SortChanged(win, *) {
    if !win.HasProp("__searchBox") || !win.HasProp("__creatorDDL") || !win.HasProp("__sortDDL") {
        return
    }
    
    win.__currentSort := win.__sortDDL.Text
    RenderMacroCards(win, win.__creatorDDL.Text, win.__searchBox.Value, win.__sortDDL.Text)
}

SortMacros(macros, sortBy) {
    if (macros.Length = 0) {
        return macros
    }
    
    ; Quick sort implementation for better performance
    return QuickSort(macros, sortBy, 1, macros.Length)
}

QuickSort(arr, sortBy, low, high) {
    if (low < high) {
        pi := Partition(arr, sortBy, low, high)
        QuickSort(arr, sortBy, low, pi - 1)
        QuickSort(arr, sortBy, pi + 1, high)
    }
    return arr
}

Partition(arr, sortBy, low, high) {
    pivot := arr[high]
    i := low - 1
    
    Loop high - low {
        j := low + A_Index - 1
        
        shouldSwap := false
        switch sortBy {
            case "Name (A-Z)":
                shouldSwap := StrCompare(StrLower(arr[j].info.Title), StrLower(pivot.info.Title)) <= 0
            case "Name (Z-A)":
                shouldSwap := StrCompare(StrLower(arr[j].info.Title), StrLower(pivot.info.Title)) >= 0
            case "Creator (A-Z)":
                shouldSwap := StrCompare(StrLower(arr[j].info.Creator), StrLower(pivot.info.Creator)) <= 0
            case "Creator (Z-A)":
                shouldSwap := StrCompare(StrLower(arr[j].info.Creator), StrLower(pivot.info.Creator)) >= 0
            case "Version (High)":
                shouldSwap := VersionCompare(arr[j].info.Version, pivot.info.Version) >= 0
            case "Version (Low)":
                shouldSwap := VersionCompare(arr[j].info.Version, pivot.info.Version) <= 0
        }
        
        if shouldSwap {
            i++
            temp := arr[i]
            arr[i] := arr[j]
            arr[j] := temp
        }
    }
    
    temp := arr[i + 1]
    arr[i + 1] := arr[high]
    arr[high] := temp
    
    return i + 1
}

RenderMacroCards(win, creator, search, sortBy := "Name (A-Z)") {
    global COLORS
    
    if !win.HasProp("__cards") {
        return
    }
    
    ; Cleanup old controls
    for ctrl in win.__cards {
        try ctrl.Destroy()
    }
    win.__cards := []
    
    ; Filter macros
    filtered := []
    for item in win.__data {
        passCreator := (creator = "All" || StrCompare(StrLower(Trim(item.info.Creator)), StrLower(Trim(creator))) = 0)
        passSearch := (search = "" || InStr(StrLower(item.info.Title), StrLower(search)))
        
        if (passCreator && passSearch) {
            filtered.Push(item)
        }
    }
    
    filtered := SortMacros(filtered, sortBy)
    
    yPos := win.__scrollY
    xPos := 25
    cardWidth := 700
    cardHeight := 85
    
    if (filtered.Length = 0) {
        noResults := win.Add("Text", "x25 y" yPos " w700 h100 c" COLORS.textDim " Center", 
            "No macros match your search or filter")
        noResults.SetFont("s11")
        win.__cards.Push(noResults)
        yPos += 120
    } else {
        for item in filtered {
            CreateMacroCard(win, item, xPos, yPos, cardWidth, cardHeight)
            yPos += cardHeight + 12
        }
    }
    
    bottomY := yPos + 15
    try {
        sep := win.Add("Text", "x0 y" bottomY " w750 h1 Background" COLORS.border)
        win.__cards.Push(sep)
    }
    
    ; Calculate appropriate window height
    contentHeight := bottomY + 20
    minHeight := 450
    maxHeight := Min(A_ScreenHeight - 100, 900)
    newHeight := Max(minHeight, Min(contentHeight, maxHeight))
    
    try win.Move(, , , newHeight)
}

CreateMacroCard(win, item, x, y, w, h) {
    global COLORS
    
    card := win.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)
    win.__cards.Push(card)
    
    iconPath := GetMacroIcon(item.path)
    iconX := x + 15
    iconY := y + 15
    iconSize := 55
    
    if (iconPath && FileExist(iconPath)) {
        try {
            pic := win.Add("Picture", "x" iconX " y" iconY " w" iconSize " h" iconSize " BackgroundTrans", iconPath)
            win.__cards.Push(pic)
        } catch {
            CreateIconBadge(win, item.info.Title, iconX, iconY, iconSize)
        }
    } else {
        CreateIconBadge(win, item.info.Title, iconX, iconY, iconSize)
    }
    
    title := win.Add("Text", "x" (x + 85) " y" (y + 15) " w440 c" COLORS.text " BackgroundTrans", item.info.Title)
    title.SetFont("s11 bold")
    win.__cards.Push(title)
    
    creator := win.Add("Text", "x" (x + 85) " y" (y + 38) " w440 c" COLORS.textDim " BackgroundTrans", 
        "by " item.info.Creator)
    creator.SetFont("s9")
    win.__cards.Push(creator)
    
    version := win.Add("Text", "x" (x + 85) " y" (y + 58) " w55 h20 Background" COLORS.accentAlt " c" COLORS.text " Center", 
        "v" item.info.Version)
    version.SetFont("s8 bold")
    win.__cards.Push(version)
    
    runBtn := win.Add("Button", "x" (x + w - 105) " y" (y + 15) " w90 h30 Background" COLORS.success, "▶ Run")
    runBtn.SetFont("s10 bold")
    runBtn.OnEvent("Click", (*) => RunMacro(item.path))
    win.__cards.Push(runBtn)
    
    if (Trim(item.info.Links) != "") {
        linksBtn := win.Add("Button", "x" (x + w - 105) " y" (y + 50) " w90 h25 Background" COLORS.accentAlt, "🔗 Links")
        linksBtn.SetFont("s9")
        linksBtn.OnEvent("Click", (*) => OpenLinks(item.info.Links))
        win.__cards.Push(linksBtn)
    }
}

CreateIconBadge(win, title, x, y, size := 55) {
    global COLORS
    
    initial := SubStr(title, 1, 1)
    iconColor := GetCategoryColor(title)
    fontSize := size = 55 ? "s20" : "s16"
    
    badge := win.Add("Text", "x" x " y" y " w" size " h" size " Background" iconColor " Center", initial)
    badge.SetFont(fontSize " bold c" COLORS.text)
    win.__cards.Push(badge)
    
    return badge
}

GetMacroIcon(macroPath) {
    global BASE_DIR
    
    try {
        SplitPath macroPath, , &macroDir
        
        extensions := ["png", "ico", "jpg", "jpeg"]
        
        for ext in extensions {
            iconPath := macroDir "\icon." ext
            if FileExist(iconPath) {
                return iconPath
            }
        }
        
        SplitPath macroDir, &folderName
        
        for ext in extensions {
            iconPath := BASE_DIR "\" folderName "." ext
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

PopulateCreatorFilter(win) {
    creatorsMap := Map()
    
    if !win.HasProp("__data") {
        return
    }
    
    for item in win.__data {
        c := Trim(item.info.Creator)
        if (c != "") {
            creatorsMap[StrLower(c)] := c
        }
    }
    
    list := ["All"]
    for _, v in creatorsMap {
        list.Push(v)
    }
    
    if (list.Length > 2) {
        tail := []
        Loop list.Length - 1 {
            tail.Push(list[A_Index + 1])
        }
        
        joined := ""
        for v in tail {
            joined .= v "`n"
        }
        
        sorted := Sort(joined)
        list := ["All"]
        
        for v in StrSplit(sorted, "`n") {
            if (Trim(v) != "") {
                list.Push(v)
            }
        }
    }
    
    try {
        win.__creatorDDL.Delete()
        win.__creatorDDL.Add(list)
        win.__creatorDDL.Choose(1)
    }
}

CategoryFilterChanged(win, *) {
    if !win.HasProp("__searchBox") || !win.HasProp("__currentSort") || !win.HasProp("__creatorDDL") {
        return
    }
    
    RenderMacroCards(win, win.__creatorDDL.Text, win.__searchBox.Value, win.__currentSort)
}

CategorySearchChanged(win, *) {
    if !win.HasProp("__creatorDDL") || !win.HasProp("__currentSort") || !win.HasProp("__searchBox") {
        return
    }
    
    RenderMacroCards(win, win.__creatorDDL.Text, win.__searchBox.Value, win.__currentSort)
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
    
    msg := "Launcher update available.`n`nCurrent: " LAUNCHER_VERSION "`nLatest: " manifest.launcher_version "`n`nUpdate?"
    
    if MsgBox(msg, "Launcher Update", "YesNo Iconi") = "No" {
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
        'echo Updating AHK Vault Launcher...' "`r`n"
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
