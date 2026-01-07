#Requires AutoHotkey v2.0
#SingleInstance Force

; ================= CONFIG =================
global APP_DIR      := A_AppData "\MacroLauncher"
global BASE_DIR     := APP_DIR "\macros"
global VERSION_FILE := APP_DIR "\version.txt"

global MANIFEST_URL := "https://raw.githubusercontent.com/lewiswr2/macro-launcher-updates/main/manifest.json"

global mainGui := 0
; =========================================

DirCreate APP_DIR
DirCreate BASE_DIR
CheckForLauncherUpdate()
CheckForUpdatesPrompt()
CreateMainGui()

; ================= UPDATE SYSTEM =================

CheckForUpdatesPrompt() {
    global MANIFEST_URL, VERSION_FILE, BASE_DIR, APP_DIR

    tmpManifest := A_Temp "\manifest.json"
    tmpZip := A_Temp "\macros.zip"
    extractDir := A_Temp "\macro_extract"

    if !SafeDownload(MANIFEST_URL, tmpManifest)
        return

    json := FileRead(tmpManifest, "UTF-8")
    latest := JsonGet(json, "version")
    zipUrl := JsonGet(json, "zip_url")
    changes := JsonGetArray(json, "changelog")

    if (!latest || !zipUrl)
        return

    current := FileExist(VERSION_FILE) ? Trim(FileRead(VERSION_FILE)) : "0"
    if VersionCompare(latest, current) <= 0
        return

    changelogText := ""
    for line in changes
        changelogText .= "• " line "`n"

    choice := MsgBox(
        "Update available!`n`n"
        "Current: " current "`n"
        "Latest:  " latest "`n`n"
        "What's new:`n"
        changelogText "`n"
        "Do you want to update now?",
        "AHK Vault Update",
        "YesNo Iconi"
    )

    if (choice = "No")
        return

    if !SafeDownload(zipUrl, tmpZip) {
        MsgBox "Failed to download update."
        return
    }

    if DirExist(extractDir)
        DirDelete extractDir, true
    DirCreate extractDir

    RunWait 'tar -xf "' tmpZip '" -C "' extractDir '"', , "Hide"

    hasDirs := false
    Loop Files, extractDir "\*", "D" {
        hasDirs := true
        break
    }

    if !hasDirs {
        MsgBox "Update failed: extraction produced no folders."
        return
    }

    ; 🔥 DELETE OLD MACROS
    if DirExist(BASE_DIR)
        DirDelete BASE_DIR, true
    DirCreate BASE_DIR

    Loop Files, extractDir "\*", "D"
        DirMove A_LoopFilePath, BASE_DIR "\" A_LoopFileName

    if FileExist(VERSION_FILE)
        FileDelete VERSION_FILE
    FileAppend latest, VERSION_FILE

    RunWait 'attrib +h +s "' APP_DIR '"', , "Hide"

    MsgBox(
        "Update complete!`n`n"
        "Version " latest " installed.`n`n"
        "Changes:`n" changelogText,
        "Update Finished",
        "Iconi"
    )
}


SafeDownload(url, out) {
    try {
        if FileExist(out)
            FileDelete out
        Download url, out
        return FileExist(out)
    } catch {
        return false
    }
}

VersionCompare(a, b) {
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

JsonGet(json, key) {
    if RegExMatch(json, '"' key '"\s*:\s*"([^"]+)"', &m)
        return m[1]
    return ""
}

; ================= MAIN GUI =================

CreateMainGui() {
    global mainGui

mainGui := Gui(, "Macro Launcher")
mainGui.SetFont("s14", "Segoe UI")
    mainGui.Add("Text", "x20 y20", "Select Category")
    ; ---- Helpful links (bottom) ----
yBottom := 360  ; adjust if you change window height

mainGui.Add("Text", "x20 y" yBottom " cBlue ", "Discord")
    .OnEvent("Click", (*) => Run("https://discord.gg/xVmSTVxQt9"))

mainGui.Add("Text", "x120 y" yBottom " cBlue ", "youtube")
    .OnEvent("Click", (*) => Run("https://www.youtube.com/@Reversals-ux9tg"))

mainGui.Add("Text", "x220 y" yBottom " cBlue ", "how-to")
    .OnEvent("Click", (*) => Run("https://docs.google.com/document/d/1Z3_9i0TE8WTX0J5o9iwnJ1ybOJ7LFtKeuhTpcumtHXk/edit?tab=t.0"))
btnLog := mainGui.Add("Button", "x470 y20 w120 h28", "Changelog")
btnLog.OnEvent("Click", ShowChangelog)

    categories := GetCategories()
    ddl := mainGui.Add("DDL", "x20 y60 w250", categories)
    ddl.OnEvent("Change", MainCategoryChanged)

    mainGui.Show("w600 h400 Center")
}

GetCategories() {
    global BASE_DIR
    list := []
    Loop Files, BASE_DIR "\*", "D"
        list.Push(A_LoopFileName)
    return list
}

MainCategoryChanged(ctrl, *) {
    global mainGui
    category := ctrl.Text
    if (category = "")
        return
    mainGui.Hide()
    ShowCategoryWindow(category)
}

; ================= CATEGORY WINDOW (Filter + ListView) =================

ShowCategoryWindow(category) {
    global mainGui

    win := Gui("+Resize", category " Macros")
    win.SetFont("s12")

    win.Add("Text", "x20 y15 w560 Center", category " Macros")

    win.Add("Text", "x20 y50", "Filter by creator:")
    creatorDDL := win.Add("DDL", "x160 y46 w220", ["All"])
    creatorDDL.OnEvent("Change", CategoryFilterChanged.Bind(win, category))

    runBtn := win.Add("Button", "x400 y44 w90 h30", "Run")
    linksBtn := win.Add("Button", "x495 y44 w85 h30", "Links")

    ; ListView (scrolls automatically)
    lv := win.Add("ListView", "x20 y85 w560 h260 -Multi", ["Title", "Creator", "Version"])
    lv.ModifyCol(1, 250)
    lv.ModifyCol(2, 170)
    lv.ModifyCol(3, 110)

    backBtn := win.Add("Button", "x20 y350 w560 h35", "Back")
    backBtn.OnEvent("Click", (*) => (win.Destroy(), mainGui.Show()))

    ; Store controls + macro data on the window object
    win.__lv := lv
    win.__creatorDDL := creatorDDL
    win.__data := [] ; array of {path, info}

    runBtn.OnEvent("Click", CategoryRunSelected.Bind(win))
    linksBtn.OnEvent("Click", CategoryLinksSelected.Bind(win))
    lv.OnEvent("DoubleClick", CategoryDoubleClick.Bind(win))

    ; Load data and populate filter + list
    win.__data := GetMacrosWithInfo(category)
    PopulateCreatorFilter(win)
    PopulateList(win, "All")

    win.Show("w600 h400 Center")
}

GetMacrosWithInfo(category) {
    global BASE_DIR
    out := []
    base := BASE_DIR "\" category
    if !DirExist(base)
        return out

    Loop Files, base "\Main.ahk", "R" {
        macroPath := A_LoopFilePath
        SplitPath macroPath, , &macroDir
        info := ReadMacroInfo(macroDir)
        out.Push({ path: macroPath, info: info })
    }
    return out
}

PopulateCreatorFilter(win) {
    creatorsMap := Map()
    for item in win.__data {
        c := Trim(item.info.Creator)
        if (c != "")
            creatorsMap[StrLower(c)] := c
    }

    list := ["All"]
    for _, v in creatorsMap
        list.Push(v)

    ; sort tail A-Z
    if (list.Length > 2) {
        tail := []
        Loop list.Length - 1
            tail.Push(list[A_Index + 1])
        tail.Sort()
        list := ["All"]
        for v in tail
            list.Push(v)
    }

    win.__creatorDDL.Delete()
    win.__creatorDDL.Add(list)
    win.__creatorDDL.Choose(1)
}

PopulateList(win, creatorFilter) {
    lv := win.__lv
    lv.Delete()

    ; reset row map each time
    lv.__rowMap := Map()

    for idx, item in win.__data {
        c := item.info.Creator
        if (creatorFilter != "All" && StrLower(c) != StrLower(creatorFilter))
            continue

        title := item.info.Title
        creator := item.info.Creator
        version := item.info.Version

        row := lv.Add(, title, creator, version)
        lv.__rowMap[row] := idx
    }
}


CategoryFilterChanged(win, category, ctrl, *) {
    PopulateList(win, ctrl.Text)
}

GetSelectedItem(win) {
    lv := win.__lv
    row := lv.GetNext(0, "F") ; focused/selected row
    if (!row)
        return 0
    if !IsObject(lv.__rowMap) || !lv.__rowMap.Has(row)
        return 0
    idx := lv.__rowMap[row]
    return win.__data[idx]
}

CategoryRunSelected(win, *) {
    item := GetSelectedItem(win)
    if !item {
        MsgBox "Select a macro first."
        return
    }
    RunMacro(item.path)
}

CategoryLinksSelected(win, *) {
    item := GetSelectedItem(win)
    if !item {
        MsgBox "Select a macro first."
        return
    }
    if (Trim(item.info.Links) = "") {
        MsgBox "No links set for this macro."
        return
    }
    OpenLinks(item.info.Links)
}

CategoryDoubleClick(win, lvCtrl, row, *) {
    ; double-click runs
    item := GetSelectedItem(win)
    if item
        RunMacro(item.path)
}

; ================= Macro metadata (bulletproof) =================

ReadMacroInfo(macroDir) {
    info := { Title: "", Creator: "", Version: "", Links: "" }
    ini := macroDir "\info.ini"

    if !FileExist(ini) {
        SplitPath macroDir, &folder
        info.Title := folder
        return info
    }

    ; Try IniRead [Macro] first
    info.Title   := IniRead(ini, "Macro", "Title", "")
    info.Creator := IniRead(ini, "Macro", "Creator", "")
    info.Version := IniRead(ini, "Macro", "Version", "")
    info.Links   := IniRead(ini, "Macro", "Links", "")

    if (info.Title != "" || info.Creator != "" || info.Version != "" || info.Links != "")
        return FinalizeInfo(info, macroDir)

    ; Fallback text parse (supports no section)
    txt := FileRead(ini, "UTF-8")
    inMacro := false
    sawAnySection := false

    for line in StrSplit(txt, "`n") {
        line := Trim(StrReplace(line, "`r"))
        if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
            continue

        if RegExMatch(line, "^\[(.+)\]$", &m) {
            sawAnySection := true
            inMacro := (StrLower(Trim(m[1])) = "macro")
            continue
        }

        if (sawAnySection && !inMacro)
            continue

        if !InStr(line, "=")
            continue

        parts := StrSplit(line, "=", , 2)
        k := StrLower(Trim(parts[1]))
        v := Trim(parts[2])

        if (k = "title")
            info.Title := v
        else if (k = "creator")
            info.Creator := v
        else if (k = "version")
            info.Version := v
        else if (k = "links")
            info.Links := v
    }

    return FinalizeInfo(info, macroDir)
}

FinalizeInfo(info, macroDir) {
    if (info.Title = "") {
        SplitPath macroDir, &folder
        info.Title := folder
    }
    if (info.Version = "")
        info.Version := "-"
    return info
}
JsonGetArray(json, key) {
    list := []

    ; s) = DOTALL so .*? can cross newlines
    pat := 's)"' key '"\s*:\s*\[(.*?)\]'
    if RegExMatch(json, pat, &m) {
        block := m[1]

        ; Extract each "string" item safely
        pos := 1
        while RegExMatch(block, 's)"((?:\\.|[^"\\])*)"', &mm, pos) {
            item := mm[1]
            ; unescape a few common sequences
            item := StrReplace(item, '\"', '"')
            item := StrReplace(item, "\\", "\")
            item := StrReplace(item, "\n", "`n")
            item := StrReplace(item, "\r", "`r")
            list.Push(item)
            pos := mm.Pos + mm.Len
        }
    }

    return list
}
; ================= Actions =================

RunMacro(path) {
    if !FileExist(path) {
        MsgBox "Macro not found:`n" path
        return
    }
    SplitPath path, , &dir
    Run '"' A_AhkPath '" "' path '"', dir
}

OpenLinks(links) {
    for url in StrSplit(links, "|") {
        url := Trim(url)
        if (url != "")
            Run url
    }
}
ShowChangelog(*) {
    global MANIFEST_URL

    tmpManifest := A_Temp "\manifest.json"
    if !SafeDownload(MANIFEST_URL, tmpManifest) {
        MsgBox "Couldn't download manifest.json (check internet / GitHub link)."
        return
    }

    json := FileRead(tmpManifest, "UTF-8")
    latest := JsonGet(json, "version")

    ; Prefer array changelog
    changes := JsonGetArray(json, "changelog")

    text := ""
    if (changes.Length > 0) {
        for line in changes
            text .= "• " line "`n"
    } else {
        ; Fallback: allow changelog to be a string
        s := JsonGet(json, "changelog")
        if (s != "")
            text := s
    }

    if (text = "")
        text := "(No changelog provided)"

    if (latest = "")
        latest := "?"

    MsgBox "Latest version: " latest "`n`nWhat's new:`n" text, "Changelog", "Iconi"
}
CheckForLauncherUpdate() {
    global MANIFEST_URL, LAUNCHER_VERSION

    tmpManifest := A_Temp "\manifest.json"
    if !SafeDownload(MANIFEST_URL, tmpManifest)
        return

    json := FileRead(tmpManifest, "UTF-8")
    latestVer := JsonGet(json, "launcher_version")
    latestUrl := JsonGet(json, "launcher_url")

    if (!latestVer || !latestUrl)
        return

    if VersionCompare(latestVer, LAUNCHER_VERSION) <= 0
        return

    ; Optional: prompt user
    msg := "A launcher update is available.`n`nCurrent: " LAUNCHER_VERSION "`nLatest: " latestVer "`n`nUpdate now?"
    if MsgBox(msg, "Launcher Update", "YesNo Iconi") = "No"
        return

    DoSelfUpdate(latestUrl, latestVer)
}

DoSelfUpdate(url, newVer) {
    ; Download new launcher script to temp
    tmpNew := A_Temp "\launcher_new.ahk"
    if !SafeDownload(url, tmpNew) {
        MsgBox "Failed to download launcher update."
        return
    }

    ; Current script path
    me := A_ScriptFullPath

    ; Build an updater .cmd that replaces the file after we exit
    cmdPath := A_Temp "\update_launcher.cmd"

    ; Note: timeout is available on most Windows. If not, ping fallback works too.
    cmd :=
    (
    '@echo off' "`r`n"
    'chcp 65001>nul' "`r`n"
    'timeout /t 1 /nobreak >nul' "`r`n"
    'copy /y "' tmpNew '" "' me '" >nul' "`r`n"
    'start "" "' A_AhkPath '" "' me '"' "`r`n"
    'del /q "' tmpNew '" >nul 2>nul' "`r`n"
    'del /q "%~f0" >nul 2>nul' "`r`n"
    )

    ; Write + run updater
    try FileDelete cmdPath
    FileAppend cmd, cmdPath, "UTF-8"

    Run '"' cmdPath '"', , "Hide"

    ; Exit current instance so file can be replaced
    ExitApp
}
