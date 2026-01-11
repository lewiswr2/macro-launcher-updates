#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
Persistent
MsgBox "NEW LAUNCHER LOADED", "DEBUG", "Iconi"

; =======================
;   V1LN MacroLauncher
; =======================

global LAUNCHER_VERSION := "2.0.5"

; --- Where the launcher should LIVE ---
global APP_LAUNCHER_DIR  := A_LocalAppData "\V1LNClan"
global APP_LAUNCHER_PATH := APP_LAUNCHER_DIR "\MacroLauncher.ahk"

; --- Macros storage ---
global APP_DIR     := APP_LAUNCHER_DIR
global BASE_DIR    := APP_DIR "\Macros"
global ICON_DIR    := BASE_DIR "\Icons"
global VERSION_FILE := APP_DIR "\version.txt"

; --- Manifest ---
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

; =======================
;   AUTO-EXECUTE
; =======================

try DirCreate(APP_LAUNCHER_DIR)
catch as err {
    MsgBox "Failed to create app folder:`n" err.Message, "Init Error", "Icon!"
    ExitApp
}

; If user ran the file from somewhere else, copy to LocalAppData and run from there
ML_EnsureRunningFromAppData()

; Ensure folders exist
ML_EnsureDirs()

; Ensure version file exists
ML_EnsureVersionFile()

; Set taskbar/tray icon (best effort)
ML_SetTaskbarIcon()

; Check launcher self-update FIRST (so GUI you see is newest)
ML_CheckForLauncherUpdate()

; Then check macros updates prompt (optional)
ML_CheckForUpdatesPrompt()

; GUI
ML_CreateMainGui()

return

; =======================
;  BOOTSTRAP / LOCATION
; =======================

ML_EnsureRunningFromAppData() {
    global APP_LAUNCHER_PATH, APP_LAUNCHER_DIR

    ; If already running from the desired path, do nothing
    if (StrLower(A_ScriptFullPath) = StrLower(APP_LAUNCHER_PATH))
        return

    try DirCreate(APP_LAUNCHER_DIR)
    catch as err {
        MsgBox "Cannot create LocalAppData launcher dir:`n" err.Message, "Error", "Icon!"
        return
    }

    ; Copy current file into AppData and run it
    try {
        FileCopy A_ScriptFullPath, APP_LAUNCHER_PATH, 1
        Run '"' A_AhkPath '" "' APP_LAUNCHER_PATH '"'
        ExitApp
    } catch as err {
        MsgBox "Failed to move launcher into AppData:`n" err.Message, "Error", "Icon!"
        ; If we fail, just continue from current location
    }
}

ML_EnsureDirs() {
    global APP_DIR, BASE_DIR, ICON_DIR
    try DirCreate(APP_DIR)
    catch as err {
        MsgBox "Failed to create APP_DIR:`n" err.Message, "Init Error", "Icon!"
    }
    try DirCreate(BASE_DIR)
    catch {
    }
    try DirCreate(ICON_DIR)
    catch {
    }
}

ML_EnsureVersionFile() {
    global VERSION_FILE
    if FileExist(VERSION_FILE)
        return
    try FileAppend "0", VERSION_FILE, "UTF-8"
    catch {
    }
}

; =======================
;   ICONS
; =======================

ML_SetTaskbarIcon() {
    global ICON_DIR
    iconPath := ICON_DIR "\launcher.png"
    try {
        if FileExist(iconPath)
            TraySetIcon(iconPath)
        else
            TraySetIcon("shell32.dll", 3)
    } catch {
    }
}

; =======================
;   NETWORK HELPERS
; =======================

ML_SafeDownload(url, out, timeoutMs := 20000) {
    if (!url || !out)
        return false

    ; Add cache-buster so GitHub raw/CDNs don't serve stale
    bust := (InStr(url, "?") ? "&" : "?") "t=" A_TickCount
    url2 := url bust

    try {
        if FileExist(out)
            FileDelete out
    } catch {
    }

    ok := false
    try {
        Download url2, out
        ok := true
    } catch {
        ok := false
    }

    if !ok
        return false

    ; Wait for file to appear + have some size
    t0 := A_TickCount
    while (A_TickCount - t0 < timeoutMs) {
        if FileExist(out) {
            try {
                if (FileGetSize(out) > 20)
                    return true
            } catch {
            }
        }
        Sleep 100
    }
    return false
}

ML_ReadTextUtf8(path, fallback := "") {
    try {
        return FileRead(path, "UTF-8")
    } catch {
        return fallback
    }
}

ML_IsProbablyHtmlOrError(text) {
    t := Trim(text)
    if (t = "")
        return true
    if InStr(t, "<!DOCTYPE html")
        return true
    if InStr(t, "<html")
        return true
    if InStr(t, "Not Found")
        return true
    if InStr(t, "404")
        return true
    return false
}

; =======================
;   VERSION / MANIFEST
; =======================

ML_VersionCompare(a, b) {
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

ML_ParseManifest(json) {
    if !json
        return false

    manifest := {
        version: "",
        zip_url: "",
        changelog: [],
        launcher_version: "",
        launcher_url: ""
    }

    try {
        if RegExMatch(json, '"version"\s*:\s*"([^"]+)"', &m)
            manifest.version := m[1]

        if RegExMatch(json, '"zip_url"\s*:\s*"([^"]+)"', &m)
            manifest.zip_url := m[1]

        if RegExMatch(json, '"launcher_version"\s*:\s*"([^"]+)"', &m)
            manifest.launcher_version := m[1]

        if RegExMatch(json, '"launcher_url"\s*:\s*"([^"]+)"', &m)
            manifest.launcher_url := m[1]

        pat := 's)"changelog"\s*:\s*\[(.*?)\]'
        if RegExMatch(json, pat, &m2) {
            block := m2[1]
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

; =======================
;   SELF UPDATE (LAUNCHER)
; =======================

ML_CheckForLauncherUpdate() {
    global MANIFEST_URL, LAUNCHER_VERSION

    tmpManifest := A_Temp "\v1ln_manifest.json"
    if !ML_SafeDownload(MANIFEST_URL, tmpManifest)
        return

    json := ML_ReadTextUtf8(tmpManifest, "")
    if (json = "")
        return

    manifest := ML_ParseManifest(json)
    if !manifest
        return

    if (!manifest.launcher_version || !manifest.launcher_url)
        return

    if (ML_VersionCompare(manifest.launcher_version, LAUNCHER_VERSION) <= 0)
        return

    ; Do update
    ML_DoSelfUpdate(manifest.launcher_url, manifest.launcher_version)
}

ML_DoSelfUpdate(url, newVer) {
    global APP_LAUNCHER_PATH

    tmpNew := A_Temp "\MacroLauncher_new.ahk"
    if !ML_SafeDownload(url, tmpNew, 30000) {
        MsgBox "Launcher update download failed.", "Update", "Icon!"
        return
    }

    content := ML_ReadTextUtf8(tmpNew, "")
    if ML_IsProbablyHtmlOrError(content) || !InStr(content, "#Requires AutoHotkey v2") {
        MsgBox "Downloaded launcher doesn't look valid (HTML/404/etc).`n`nURL:`n" url, "Update", "Icon!"
        try FileDelete tmpNew
        catch {
        }
        return
    }

    cmdPath := A_Temp "\v1ln_launcher_updater.cmd"
    q := Chr(34)

    lines := []
    lines.Push("@echo off")
    lines.Push("setlocal")
    lines.Push("chcp 65001>nul")
    lines.Push("rem wait a moment for AHK to exit")
    lines.Push("ping 127.0.0.1 -n 3 >nul")
    lines.Push("attrib -h -s -r " . q . APP_LAUNCHER_PATH . q . " >nul 2>&1")
    lines.Push("copy /y " . q . tmpNew . q . " " . q . APP_LAUNCHER_PATH . q . " >nul 2>&1")
    lines.Push("if errorlevel 1 goto fail")
    lines.Push("start " . q . q . " " . q . A_AhkPath . q . " " . q . APP_LAUNCHER_PATH . q)
    lines.Push("del /q " . q . tmpNew . q . " >nul 2>&1")
    lines.Push("del /q " . q . "%~f0" . q . " >nul 2>&1")
    lines.Push("exit /b 0")
    lines.Push(":fail")
    lines.Push("rem if replace fails, run the downloaded copy so user isn't stuck")
    lines.Push("start " . q . q . " " . q . A_AhkPath . q . " " . q . tmpNew . q)
    lines.Push("del /q " . q . "%~f0" . q . " >nul 2>&1")
    lines.Push("exit /b 1")

    try {
        if FileExist(cmdPath)
            FileDelete cmdPath
        for _, line in lines
            FileAppend line "`r`n", cmdPath, "UTF-8"
    } catch as err {
        MsgBox "Failed to write updater CMD:`n" err.Message, "Update", "Icon!"
        return
    }

    try Run q . cmdPath . q, , "Hide"
    catch as err {
        MsgBox "Failed to run updater CMD:`n" err.Message, "Update", "Icon!"
        return
    }

    ExitApp
}


; =======================
;   MACRO UPDATES (ZIP)
; =======================

ML_CheckForUpdatesPrompt() {
    global MANIFEST_URL, VERSION_FILE, BASE_DIR, APP_DIR, ICON_DIR

    tmpManifest := A_Temp "\v1ln_manifest.json"
    tmpZip := A_Temp "\v1ln_macros.zip"
    extractDir := A_Temp "\v1ln_macro_extract"
    backupDir := A_Temp "\v1ln_macro_backup_" A_Now

    if !ML_SafeDownload(MANIFEST_URL, tmpManifest)
        return

    json := ML_ReadTextUtf8(tmpManifest, "")
    if (json = "")
        return

    manifest := ML_ParseManifest(json)
    if !manifest
        return

    current := "0"
    try {
        if FileExist(VERSION_FILE)
            current := Trim(FileRead(VERSION_FILE, "UTF-8"))
    } catch {
        current := "0"
    }

    if (ML_VersionCompare(manifest.version, current) <= 0)
        return

    changelogText := ""
    for _, line in manifest.changelog
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

    ; Download ZIP (retry)
    downloadSuccess := false
    attempts := 0
    maxAttempts := 3
    while (!downloadSuccess && attempts < maxAttempts) {
        attempts++
        if (ML_SafeDownload(manifest.zip_url, tmpZip, 30000) && ML_IsValidZip(tmpZip)) {
            downloadSuccess := true
        } else {
            try if FileExist(tmpZip)
                FileDelete tmpZip
            catch {
            }
            if (attempts < maxAttempts)
                Sleep 1000
        }
    }

    if !downloadSuccess {
        MsgBox "Failed to download a valid ZIP.`n`nURL:`n" manifest.zip_url, "Download Failed", "Icon!"
        return
    }

    ; Extract
    if !ML_ExtractZipShell(tmpZip, extractDir)
        return

    ; GitHub zips often contain a top folder
    top := ML_FindTopFolder(extractDir)

    ; Determine structure
    hasMacrosFolder := DirExist(top "\Macros")
    hasIconsFolder := DirExist(top "\icons")
    hasLooseFolders := ML_HasAnyFolders(top)

    useNestedStructure := hasMacrosFolder
    if (!hasMacrosFolder && !hasLooseFolders) {
        MsgBox "Update failed: No valid content found in zip.", "Error", "Icon!"
        return
    }

    ; Backup old
    backupSuccess := false
    if DirExist(BASE_DIR) {
        try {
            DirCreate backupDir
            Loop Files, BASE_DIR "\*", "D"
                ML_TryDirMove(A_LoopFilePath, backupDir "\" A_LoopFileName, true)
            backupSuccess := true
        } catch {
            backupSuccess := false
        }
    }

    ; Install new
    try {
        if DirExist(BASE_DIR)
            DirDelete BASE_DIR, true
        DirCreate BASE_DIR

        if useNestedStructure {
            Loop Files, top "\Macros\*", "D"
                ML_TryDirMove(A_LoopFilePath, BASE_DIR "\" A_LoopFileName, true)
        } else {
            Loop Files, top "\*", "D" {
                if (A_LoopFileName != "icons")
                    ML_TryDirMove(A_LoopFilePath, BASE_DIR "\" A_LoopFileName, true)
            }
        }
    } catch as err {
        ; rollback
        try {
            if backupSuccess {
                if DirExist(BASE_DIR)
                    DirDelete BASE_DIR, true
                DirCreate BASE_DIR
                Loop Files, backupDir "\*", "D"
                    ML_TryDirMove(A_LoopFilePath, BASE_DIR "\" A_LoopFileName, true)
            }
        } catch {
        }
        ML_ShowUpdateFail("Install / move folders", err, "BASE_DIR=`n" BASE_DIR "`n`nTip: close MacroLauncher & check AV/Controlled Folder Access.")
        return
    }

    ; Icons
    iconsUpdated := false
    if hasIconsFolder {
        try {
            if !DirExist(ICON_DIR)
                DirCreate ICON_DIR
            Loop Files, top "\icons\*.*", "F" {
                ML_TryFileCopy(A_LoopFilePath, ICON_DIR "\" A_LoopFileName, true)
                iconsUpdated := true
            }
        } catch as err {
            ML_ShowUpdateFail("Copy icons", err, "ICON_DIR=`n" ICON_DIR)
        }
    }

    ; Write version
    try {
        if FileExist(VERSION_FILE)
            FileDelete VERSION_FILE
        FileAppend manifest.version, VERSION_FILE, "UTF-8"
        try RunWait 'attrib +h +s "' APP_DIR '"', , "Hide"
        catch {
        }
    } catch as err {
        ML_ShowUpdateFail("Write version file", err, "VERSION_FILE=`n" VERSION_FILE)
    }

    ; Cleanup
    try if FileExist(tmpZip)
        FileDelete tmpZip
    catch {
    }
    try if DirExist(extractDir)
        DirDelete extractDir, true
    catch {
    }

    updateMsg := "Update complete!`n`nVersion " manifest.version " installed.`n`n"
    if iconsUpdated
        updateMsg .= "✓ Icons updated`n"
    updateMsg .= "`nChanges:`n" changelogText

    MsgBox updateMsg, "Update Finished", "Iconi"
}

; =======================
;   ZIP / FILE HELPERS
; =======================

ML_IsValidZip(path) {
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

ML_ExtractZipShell(zipPath, destDir) {
    try {
        if DirExist(destDir)
            DirDelete destDir, true
        DirCreate destDir

        shell := ComObject("Shell.Application")
        zip := shell.NameSpace(zipPath)
        if !zip
            throw Error("Shell.NameSpace(zip) failed.")

        dest := shell.NameSpace(destDir)
        if !dest
            throw Error("Shell.NameSpace(dest) failed.")

        ; 16 = overwrite without prompts
        dest.CopyHere(zip.Items(), 16)

        t0 := A_TickCount
        Loop 80 {
            if ML_HasAnyFileOrFolder(destDir)
                return true
            Sleep 250
        }
        throw Error("Extraction produced no files/folders (timeout).")
    } catch as err {
        MsgBox "❌ EXTRACTION FAILED:`n" err.Message, "Update", "Icon! 0x10"
        return false
    }
}

ML_HasAnyFileOrFolder(dir) {
    try {
        Loop Files, dir "\*", "FD"
            return true
    } catch {
    }
    return false
}

ML_HasAnyFolders(dir) {
    try {
        Loop Files, dir "\*", "D"
            return true
    } catch {
    }
    return false
}

ML_FindTopFolder(extractDir) {
    folders := []
    try {
        Loop Files, extractDir "\*", "D"
            folders.Push(A_LoopFilePath)
    } catch {
    }
    if (folders.Length = 1)
        return folders[1]
    return extractDir
}

ML_TryDirMove(src, dst, overwrite := true, retries := 10) {
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

ML_TryFileCopy(src, dst, overwrite := true, retries := 10) {
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

ML_ShowUpdateFail(context, err, extra := "") {
    global APP_DIR
    msg := "❌ Failed to install macro updates`n`n"
        . "Step: " context "`n"
        . "Error: " err.Message "`n`n"
        . "Extra: " extra "`n`n"
        . "A_LastError: " A_LastError "`n"
        . "A_WorkingDir: " A_WorkingDir "`n"
        . "AppDir: " APP_DIR

    MsgBox msg, "V1LN AHK Vault - Update Failed", "Icon! 0x10"
}

; =======================
;   GUI (YOUR STYLE)
; =======================

ML_CreateMainGui() {
    global mainGui, COLORS, BASE_DIR, ICON_DIR

    mainGui := Gui("-Resize +Border", "V1LN AHK Vault")
    mainGui.BackColor := COLORS.bg
    mainGui.SetFont("s10", "Segoe UI")

    iconPath := ICON_DIR "\1.png"
    if FileExist(iconPath) {
        try {
            mainGui.Show("Hide")
            mainGui.Opt("+Icon" iconPath)
        } catch {
        }
    }

    mainGui.Add("Text", "x0 y0 w550 h80 Background" COLORS.accent)

    ahkImage := ICON_DIR "\AHK.png"
    if FileExist(ahkImage) {
        try mainGui.Add("Picture", "x20 y15 w50 h50 BackgroundTrans", ahkImage)
        catch {
        }
    }

    titleText := mainGui.Add("Text", "x80 y20 w280 h100 c" COLORS.text " BackgroundTrans", "V1LN AHK Vault")
    titleText.SetFont("s24 bold")

    btnUpdate := mainGui.Add("Button", "x370 y25 w75 h35 Background" COLORS.success, "Update")
    btnUpdate.SetFont("s10")
    btnUpdate.OnEvent("Click", ML_ManualUpdate)

    btnLog := mainGui.Add("Button", "x450 y25 w75 h35 Background" COLORS.accentHover, "Changelog")
    btnLog.SetFont("s10")
    btnLog.OnEvent("Click", ML_ShowChangelog)

    mainGui.Add("Text", "x25 y100 w500 c" COLORS.text, "Games").SetFont("s12 bold")
    mainGui.Add("Text", "x25 y125 w500 h1 Background" COLORS.border)

    categories := ML_GetCategories()
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
        for _, category in categories {
            ML_CreateCategoryCard(mainGui, category, xPos, yPos, cardWidth, cardHeight)
            yPos += cardHeight + 12
        }
    }

    bottomY := yPos + 15
    mainGui.Add("Text", "x0 y" bottomY " w550 h1 Background" COLORS.border)

    linkY := bottomY + 15
    ML_CreateLink(mainGui, "Discord", "https://discord.gg/v1ln", 25, linkY)
    linkY := bottomY + 35
    ML_CreateLink(mainGui, "The Creators Discord", "https://discord.gg/mgkwyAWvYK", 25, linkY)

    mainGui.Show("w550 h" (bottomY + 60) " Center")
}

ML_GetCategories() {
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
    } catch {
    }
    return arr
}

ML_CreateCategoryCard(gui, category, x, y, w, h) {
    global COLORS

    card := gui.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)

    iconPath := ML_GetGameIcon(category)
    iconX := x + 15
    iconY := y + 15
    iconSize := 40

    if (iconPath && FileExist(iconPath)) {
        try {
            gui.Add("Picture", "x" iconX " y" iconY " w" iconSize " h" iconSize " BackgroundTrans", iconPath)
        } catch {
            ML_CreateCategoryBadge(gui, category, iconX, iconY, iconSize)
        }
    } else {
        ML_CreateCategoryBadge(gui, category, iconX, iconY, iconSize)
    }

    titleText := gui.Add("Text", "x" (x + 70) " y" (y + 22) " w" (w - 150) " c" COLORS.text " BackgroundTrans", category)
    titleText.SetFont("s11 bold")

    openBtn := gui.Add("Button", "x" (x + w - 95) " y" (y + 18) " w80 h34 Background" COLORS.accent, "Open →")
    openBtn.SetFont("s9 bold")
    openBtn.OnEvent("Click", (*) => ML_OpenCategory(category))
}

ML_CreateCategoryBadge(gui, category, x, y, size := 40) {
    global COLORS
    initial := SubStr(category, 1, 1)
    iconColor := ML_GetCategoryColor(category)

    badge := gui.Add("Text", "x" x " y" y " w" size " h" size " Background" iconColor " Center", initial)
    badge.SetFont("s18 bold c" COLORS.text)
    return badge
}

ML_GetGameIcon(category) {
    global ICON_DIR, BASE_DIR
    extensions := ["png", "ico", "jpg", "jpeg"]

    for _, ext in extensions {
        iconPath := ICON_DIR "\" category "." ext
        if FileExist(iconPath)
            return iconPath
    }

    for _, ext in extensions {
        iconPath := BASE_DIR "\" category "." ext
        if FileExist(iconPath)
            return iconPath
    }

    for _, ext in extensions {
        iconPath := BASE_DIR "\" category "\icon." ext
        if FileExist(iconPath)
            return iconPath
    }
    return ""
}

ML_GetCategoryColor(category) {
    colors := ["0x238636", "0x1f6feb", "0x8957e5", "0xda3633", "0xbc4c00", "0x1a7f37", "0xd29922"]
    hash := 0
    for _, ch in StrSplit(category)
        hash += Ord(ch)
    return colors[Mod(hash, colors.Length) + 1]
}

ML_CreateLink(gui, label, url, x, y) {
    global COLORS
    link := gui.Add("Text", "x" x " y" y " c" COLORS.accent " BackgroundTrans", label)
    link.SetFont("s9 underline")
    link.OnEvent("Click", (*) => ML_SafeOpenURL(url))
}

ML_SafeOpenURL(url) {
    url := Trim(url)
    if (!InStr(url, "http://") && !InStr(url, "https://")) {
        MsgBox "Invalid URL:`n" url, "Error", "Icon!"
        return
    }
    try {
        Run url
    } catch as err {
        MsgBox "Failed to open URL:`n" err.Message, "Error", "Icon!"
    }
}

; =======================
;   MACROS UI (OPEN)
; =======================

ML_OpenCategory(category) {
    global COLORS, BASE_DIR

    macros := ML_GetMacrosWithInfo(category)
    if (macros.Length = 0) {
        MsgBox(
            "No macros found in '" category "'`n`n"
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
    win.__scrollY := 110

    win.Add("Text", "x0 y0 w750 h90 Background" COLORS.accent)

    backBtn := win.Add("Button", "x20 y25 w70 h35 Background" COLORS.accentHover, "← Back")
    backBtn.SetFont("s10")
    backBtn.OnEvent("Click", (*) => win.Destroy())

    title := win.Add("Text", "x105 y20 w500 h100 c" COLORS.text " BackgroundTrans", category)
    title.SetFont("s22 bold")

    win.OnEvent("Close", (*) => win.Destroy())

    ML_RenderCards(win)

    win.Show("w750 h640 Center")
}

ML_RenderCards(win) {
    global COLORS

    ; Clear old controls
    if win.HasProp("__cards") && (win.__cards.Length > 0) {
        for _, ctrl in win.__cards {
            try ctrl.Destroy()
            catch {
            }
        }
    }
    win.__cards := []

    macros := win.__data
    scrollY := win.__scrollY

    itemsPerPage := win.__itemsPerPage
    currentPage := win.__currentPage
    totalPages := Ceil(macros.Length / itemsPerPage)
    if (currentPage < 1)
        currentPage := 1
    if (currentPage > totalPages)
        currentPage := totalPages
    win.__currentPage := currentPage

    startIdx := ((currentPage - 1) * itemsPerPage) + 1
    endIdx := Min(currentPage * itemsPerPage, macros.Length)
    itemsToShow := endIdx - startIdx + 1

    if (itemsToShow = 1) {
        item := macros[startIdx]
        ML_CreateFullWidthCard(win, item, 25, scrollY, 700, 110)
    } else {
        cardWidth := 340
        cardHeight := 110
        spacing := 10

        Loop itemsToShow {
            idx := startIdx + A_Index - 1
            item := macros[idx]

            col := Mod(A_Index - 1, 2)
            row := Floor((A_Index - 1) / 2)

            xPos := 25 + (col * (cardWidth + spacing))
            yPos := scrollY + (row * (cardHeight + spacing))

            ML_CreateGridCard(win, item, xPos, yPos, cardWidth, cardHeight)
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
            prevBtn.OnEvent("Click", (*) => ML_ChangePage(win, -1))
            win.__cards.Push(prevBtn)
        }

        if (currentPage < totalPages) {
            nextBtn := win.Add("Button", "x635 y" (paginationY - 5) " w90 h35 Background" COLORS.accentHover, "Next →")
            nextBtn.SetFont("s9")
            nextBtn.OnEvent("Click", (*) => ML_ChangePage(win, 1))
            win.__cards.Push(nextBtn)
        }
    }
}

ML_CreateFullWidthCard(win, item, x, y, w, h) {
    global COLORS

    card := win.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)
    win.__cards.Push(card)

    titleCtrl := win.Add("Text", "x" (x + 20) " y" (y + 20) " w520 c" COLORS.text " BackgroundTrans", item.info.Title)
    titleCtrl.SetFont("s13 bold")
    win.__cards.Push(titleCtrl)

    creatorCtrl := win.Add("Text", "x" (x + 20) " y" (y + 50) " w520 c" COLORS.textDim " BackgroundTrans", "by " item.info.Creator)
    creatorCtrl.SetFont("s10")
    win.__cards.Push(creatorCtrl)

    versionCtrl := win.Add("Text", "x" (x + 20) " y" (y + 75) " w60 h22 Background" COLORS.accentAlt " c" COLORS.text " Center", "v" item.info.Version)
    versionCtrl.SetFont("s9 bold")
    win.__cards.Push(versionCtrl)

    currentPath := item.path
    runBtn := win.Add("Button", "x" (x + w - 110) " y" (y + 20) " w100 h35 Background" COLORS.success, "▶ Run")
    runBtn.SetFont("s11 bold")
    runBtn.OnEvent("Click", (*) => ML_RunMacro(currentPath))
    win.__cards.Push(runBtn)

    if (Trim(item.info.Links) != "") {
        currentLinks := item.info.Links
        linksBtn := win.Add("Button", "x" (x + w - 110) " y" (y + 65) " w100 h30 Background" COLORS.accentAlt, "🔗 Links")
        linksBtn.SetFont("s10")
        linksBtn.OnEvent("Click", (*) => ML_OpenLinks(currentLinks))
        win.__cards.Push(linksBtn)
    }
}

ML_CreateGridCard(win, item, x, y, w, h) {
    global COLORS

    card := win.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)
    win.__cards.Push(card)

    titleCtrl := win.Add("Text", "x" (x + 15) " y" (y + 15) " w" (w - 110) " c" COLORS.text " BackgroundTrans", item.info.Title)
    titleCtrl.SetFont("s11 bold")
    win.__cards.Push(titleCtrl)

    creatorCtrl := win.Add("Text", "x" (x + 15) " y" (y + 40) " w" (w - 110) " c" COLORS.textDim " BackgroundTrans", "by " item.info.Creator)
    creatorCtrl.SetFont("s9")
    win.__cards.Push(creatorCtrl)

    versionCtrl := win.Add("Text", "x" (x + 15) " y" (y + 65) " w50 h20 Background" COLORS.accentAlt " c" COLORS.text " Center", "v" item.info.Version)
    versionCtrl.SetFont("s8 bold")
    win.__cards.Push(versionCtrl)

    currentPath := item.path
    runBtn := win.Add("Button", "x" (x + w - 90) " y" (y + 15) " w80 h30 Background" COLORS.success, "▶ Run")
    runBtn.SetFont("s10 bold")
    runBtn.OnEvent("Click", (*) => ML_RunMacro(currentPath))
    win.__cards.Push(runBtn)

    if (Trim(item.info.Links) != "") {
        currentLinks := item.info.Links
        linksBtn := win.Add("Button", "x" (x + w - 90) " y" (y + 55) " w80 h25 Background" COLORS.accentAlt, "🔗 Links")
        linksBtn.SetFont("s9")
        linksBtn.OnEvent("Click", (*) => ML_OpenLinks(currentLinks))
        win.__cards.Push(linksBtn)
    }
}

ML_ChangePage(win, direction) {
    win.__currentPage := win.__currentPage + direction
    totalPages := Ceil(win.__data.Length / win.__itemsPerPage)
    if (win.__currentPage < 1)
        win.__currentPage := 1
    if (win.__currentPage > totalPages)
        win.__currentPage := totalPages
    ML_RenderCards(win)
}

ML_GetMacrosWithInfo(category) {
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
                info := ML_ReadMacroInfo(subFolder)
                out.Push({ path: mainFile, info: info })
            }
        }
    } catch {
    }

    if (out.Length = 0) {
        mainFile := base "\Main.ahk"
        if FileExist(mainFile) {
            info := ML_ReadMacroInfo(base)
            out.Push({ path: mainFile, info: info })
        }
    }

    return out
}

ML_ReadMacroInfo(macroDir) {
    info := { Title: "", Creator: "", Version: "", Links: "" }

    try {
        SplitPath macroDir, &folder
        info.Title := folder
    } catch {
    }

    ini := macroDir "\info.ini"
    if !FileExist(ini) {
        if (info.Version = "")
            info.Version := "1.0"
        return info
    }

    txt := ML_ReadTextUtf8(ini, "")
    if (txt = "") {
        if (info.Version = "")
            info.Version := "1.0"
        return info
    }

    for _, line in StrSplit(txt, "`n") {
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
            case "title":   info.Title := v
            case "creator": info.Creator := v
            case "version": info.Version := v
            case "links":   info.Links := v
        }
    }

    if (info.Version = "")
        info.Version := "1.0"

    return info
}

ML_RunMacro(path) {
    if !FileExist(path) {
        MsgBox "Macro not found:`n" path, "Error", "Icon!"
        return
    }
    try {
        SplitPath path, , &dir
        Run '"' A_AhkPath '" "' path '"', dir
    } catch as err {
        MsgBox "Failed to run macro:`n" err.Message, "Error", "Icon!"
    }
}

ML_OpenLinks(links) {
    if (!links || Trim(links) = "")
        return
    try {
        for _, url in StrSplit(links, "|") {
            url := Trim(url)
            if (url != "")
                ML_SafeOpenURL(url)
        }
    } catch as err {
        MsgBox "Failed to open link:`n" err.Message, "Error", "Icon!"
    }
}

ML_ShowChangelog(*) {
    global MANIFEST_URL

    tmpManifest := A_Temp "\v1ln_manifest.json"
    if !ML_SafeDownload(MANIFEST_URL, tmpManifest) {
        MsgBox "Couldn't download manifest.json", "Error", "Icon!"
        return
    }

    json := ML_ReadTextUtf8(tmpManifest, "")
    if (json = "") {
        MsgBox "Failed to read manifest.", "Error", "Icon!"
        return
    }

    manifest := ML_ParseManifest(json)
    if !manifest {
        MsgBox "Failed to parse manifest.", "Error", "Icon!"
        return
    }

    text := ""
    if (manifest.changelog.Length > 0) {
        for _, line in manifest.changelog
            text .= "• " line "`n"
    }

    if (text = "")
        text := "(No changelog available)"

    MsgBox "Version: " manifest.version "`n`n" text, "Changelog", "Iconi"
}

ML_ManualUpdate(*) {
    ; Force show update prompt by deleting version file then calling update prompt
    global VERSION_FILE
    try if FileExist(VERSION_FILE)
        FileDelete VERSION_FILE
    catch {
    }
    ML_CheckForUpdatesPrompt()
}

