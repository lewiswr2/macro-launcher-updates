#Requires AutoHotkey v2.0
#SingleInstance Force
global LAUNCHER_VERSION := "2.0.0"

; ================= CONFIG =================
global APP_DIR      := A_AppData "\MacroLauncher"
global BASE_DIR     := APP_DIR "\Macros"
global VERSION_FILE := APP_DIR "\version.txt"
global ICON_DIR     := APP_DIR "\icons"

global MANIFEST_URL := "https://raw.githubusercontent.com/lewiswr2/macro-launcher-updates/main/manifest.json"

global mainGui := 0
global COLORS := {
    bg: "0x0d1117",
    card: "0x161b22",
    cardHover: "0x21262d",
    accent: "0x1f6feb",
    accentBright: "0x58a6ff",
    text: "0xc9d1d9",
    textDim: "0x8b949e",
    border: "0x30363d"
}
; =========================================

DirCreate APP_DIR
DirCreate BASE_DIR
DirCreate ICON_DIR
SetTaskbarIcon()
CheckForLauncherUpdate()
CheckForUpdatesPrompt()
CreateMainGui()

SetTaskbarIcon() {
    iconPath := ICON_DIR "\launcher.ico"
    if !FileExist(iconPath) {
        try TraySetIcon("shell32.dll", 3)
    } else {
        try TraySetIcon(iconPath)
    }
}

CheckForUpdatesPrompt() {
    global MANIFEST_URL, VERSION_FILE, BASE_DIR, APP_DIR

    tmpManifest := A_Temp "\manifest.json"
    tmpZip := A_Temp "\Macros.zip"
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

JsonGetArray(json, key) {
    list := []
    pat := 's)"' key '"\s*:\s*\[(.*?)\]'
    if RegExMatch(json, pat, &m) {
        block := m[1]
        pos := 1
        while RegExMatch(block, 's)"((?:\\.|[^"\\])*)"', &mm, pos) {
            item := mm[1]
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

CreateMainGui() {
    global mainGui, COLORS

    mainGui := Gui("+Resize", "AHK Vault")
    mainGui.BackColor := COLORS.bg
    mainGui.SetFont("s10", "Segoe UI")

    mainGui.Add("Text", "x0 y0 w500 h60 Background" COLORS.accent)
    mainGui.Add("Text", "x20 y15 w460 h100 c" COLORS.text " BackgroundTrans", "AHK Vault").SetFont("s18 bold")
    
    btnLog := mainGui.Add("Button", "x370 y18 w110 h28 Background" COLORS.accentBright, "Changelog")
    btnLog.SetFont("s9")
    btnLog.OnEvent("Click", ShowChangelog)

    mainGui.Add("Text", "x20 y75 w100 c" COLORS.text, "Games").SetFont("s11 bold")
    
    categories := GetCategories()
    
    yPos := 110
    xPos := 20
    cardWidth := 460
    cardHeight := 60

    for category in categories {
        CreateCategoryCard(mainGui, category, xPos, yPos, cardWidth, cardHeight)
        yPos += cardHeight + 10
    }

    bottomY := yPos + 10
    mainGui.Add("Text", "x0 y" bottomY " w500 h1 Background" COLORS.border)
    
    linkY := bottomY + 12
    CreateLink(mainGui, "Discord", "https://discord.gg/xVmSTVxQt9", 20, linkY)
    CreateLink(mainGui, "YouTube", "https://www.youtube.com/@Reversals-ux9tg", 100, linkY)
    CreateLink(mainGui, "Guide", "https://docs.google.com/document/d/1Z3_9i0TE8WTX0J5o9iwnJ1ybOJ7LFtKeuhTpcumtHXk/edit?tab=t.0", 190, linkY)

    mainGui.Show("w500 h" (bottomY + 50) " Center")
}

CreateCategoryCard(gui, category, x, y, w, h) {
    global COLORS
    
    card := gui.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)
    
    iconPath := GetGameIcon(category)
    iconX := x + 12
    iconY := y + 10
    
    if (iconPath && FileExist(iconPath)) {
        try {
            gui.Add("Picture", "x" iconX " y" iconY " w40 h40", iconPath)
        } catch {
            CreateCategoryBadge(gui, category, iconX, iconY)
        }
    } else {
        CreateCategoryBadge(gui, category, iconX, iconY)
    }
    
    gui.Add("Text", "x" (x + 65) " y" (y + 18) " w" (w - 75) " c" COLORS.text " BackgroundTrans", category).SetFont("s11 bold")
    
    card.OnEvent("Click", (*) => OpenCategory(category))
}

CreateCategoryBadge(gui, category, x, y) {
    global COLORS
    initial := SubStr(category, 1, 1)
    iconColor := GetCategoryColor(category)
    
    gui.Add("Text", "x" x " y" y " w40 h40 Background" iconColor " Center", initial).SetFont("s16 bold c" COLORS.text)
}

GetGameIcon(category) {
    global ICON_DIR
    extensions := ["ico", "png", "jpg", "jpeg"]
    for ext in extensions {
        iconPath := ICON_DIR "\" category "." ext
        if FileExist(iconPath)
            return iconPath
    }
    return ""
}

GetCategoryColor(category) {
    colors := ["0x238636", "0x1f6feb", "0x8957e5", "0xda3633", "0xbc4c00", "0x1a7f37"]
    hash := 0
    for char in StrSplit(category)
        hash += Ord(char)
    return colors[Mod(hash, colors.Length) + 1]
}

CreateLink(gui, text, url, x, y) {
    global COLORS
    link := gui.Add("Text", "x" x " y" y " c" COLORS.accentBright, text)
    link.SetFont("s9 underline")
    link.OnEvent("Click", (*) => Run(url))
    return link
}

GetCategories() {
    global BASE_DIR
    list := []
    Loop Files, BASE_DIR "\*", "D"
        list.Push(A_LoopFileName)
    return list
}

OpenCategory(category) {
    global mainGui
    mainGui.Hide()
    ShowCategoryWindow(category)
}

ShowCategoryWindow(category) {
    global mainGui, COLORS

    win := Gui("+Resize", category " - AHK Vault")
    win.BackColor := COLORS.bg
    win.SetFont("s9", "Segoe UI")

    win.Add("Text", "x0 y0 w600 h55 Background" COLORS.accent)
    win.Add("Text", "x20 y12 c" COLORS.text " BackgroundTrans", category).SetFont("s16 bold")
    win.Add("Text", "x20 y35 c" COLORS.textDim " BackgroundTrans", "Select a macro").SetFont("s8")

    win.Add("Text", "x20 y70 c" COLORS.text, "Filter:")
    creatorDDL := win.Add("DDL", "x65 y68 w150 Background" COLORS.card, ["All"])
    creatorDDL.OnEvent("Change", CategoryFilterChanged.Bind(win, category))

    searchBox := win.Add("Edit", "x235 y68 w180 Background" COLORS.card " c" COLORS.text, "")
    searchBox.OnEvent("Change", CategorySearchChanged.Bind(win))

    win.__data := GetMacrosWithInfo(category)
    win.__creatorDDL := creatorDDL
    win.__searchBox := searchBox
    win.__cards := []

    PopulateCreatorFilter(win)
    RenderMacroCards(win, "All", "")

    backBtn := win.Add("Button", "x20 y500 w560 h35 Background" COLORS.accentBright, "Back")
    backBtn.SetFont("s10 bold")
    backBtn.OnEvent("Click", (*) => (win.Destroy(), mainGui.Show()))

    win.Show("w600 h555 Center")
}

RenderMacroCards(win, creatorFilter, searchText) {
    global COLORS
    
    for card in win.__cards {
        try card.Destroy()
    }
    win.__cards := []

    yPos := 105
    xPos := 20
    cardWidth := 560
    cardHeight := 75

    searchLower := StrLower(searchText)
    count := 0

    for item in win.__data {
        c := item.info.Creator
        if (creatorFilter != "All" && StrLower(c) != StrLower(creatorFilter))
            continue

        if (searchText != "") {
            title := StrLower(item.info.Title)
            creator := StrLower(c)
            if (!InStr(title, searchLower) && !InStr(creator, searchLower))
                continue
        }

        count++
        CreateMacroCard(win, item, xPos, yPos, cardWidth, cardHeight)
        yPos += cardHeight + 10
    }

    if (count = 0) {
        noResults := win.Add("Text", "x20 y105 w560 h380 c" COLORS.textDim " Center", "No macros found")
        noResults.SetFont("s11")
        win.__cards.Push(noResults)
    }
}

CreateMacroCard(win, item, x, y, w, h) {
    global COLORS
    
    card := win.Add("Text", "x" x " y" y " w" w " h" h " Background" COLORS.card)
    win.__cards.Push(card)

    iconPath := GetMacroIcon(item.path)
    iconX := x + 10
    iconY := y + 10
    
    if (iconPath && FileExist(iconPath)) {
        try {
            pic := win.Add("Picture", "x" iconX " y" iconY " w35 h35", iconPath)
            win.__cards.Push(pic)
        } catch {
            CreateIconBadge(win, item.info.Title, iconX, iconY, 35)
        }
    } else {
        CreateIconBadge(win, item.info.Title, iconX, iconY, 35)
    }

    title := win.Add("Text", "x" (x + 55) " y" (y + 10) " w320 c" COLORS.text " BackgroundTrans", item.info.Title)
    title.SetFont("s10 bold")
    win.__cards.Push(title)

    creator := win.Add("Text", "x" (x + 55) " y" (y + 30) " w320 c" COLORS.textDim " BackgroundTrans", item.info.Creator)
    creator.SetFont("s8")
    win.__cards.Push(creator)

    version := win.Add("Text", "x" (x + 55) " y" (y + 48) " w45 h18 Background" COLORS.accent " c" COLORS.text " Center", item.info.Version)
    version.SetFont("s7")
    win.__cards.Push(version)

    runBtn := win.Add("Button", "x" (x + w - 100) " y" (y + 15) " w90 h25 Background" COLORS.accentBright, "Run")
    runBtn.SetFont("s9 bold")
    runBtn.OnEvent("Click", (*) => RunMacro(item.path))
    win.__cards.Push(runBtn)

    if (Trim(item.info.Links) != "") {
        linksBtn := win.Add("Button", "x" (x + w - 100) " y" (y + 45) " w90 h20 Background" COLORS.accent, "Links")
        linksBtn.SetFont("s8")
        linksBtn.OnEvent("Click", (*) => OpenLinks(item.info.Links))
        win.__cards.Push(linksBtn)
    }

    card.OnEvent("Click", (*) => RunMacro(item.path))
}

CreateIconBadge(win, title, x, y, size := 35) {
    global COLORS
    initial := SubStr(title, 1, 1)
    iconColor := GetCategoryColor(title)
    
    fontSize := size = 35 ? "s14" : "s16"
    badge := win.Add("Text", "x" x " y" y " w" size " h" size " Background" iconColor " Center", initial)
    badge.SetFont(fontSize " bold c" COLORS.text)
    win.__cards.Push(badge)
}

GetMacroIcon(macroPath) {
    SplitPath macroPath, , &macroDir
    
    extensions := ["ico", "png", "jpg", "jpeg"]
    for ext in extensions {
        iconPath := macroDir "\icon." ext
        if FileExist(iconPath)
            return iconPath
    }
    return ""
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

    if (list.Length > 2) {
        tail := []
        Loop list.Length - 1
            tail.Push(list[A_Index + 1])
        
        joined := ""
        for v in tail
            joined .= v "`n"
        sorted := Sort(joined)
        
        list := ["All"]
        for v in StrSplit(sorted, "`n") {
            if (Trim(v) != "")
                list.Push(v)
        }
    }

    win.__creatorDDL.Delete()
    win.__creatorDDL.Add(list)
    win.__creatorDDL.Choose(1)
}

CategoryFilterChanged(win, category, ctrl, *) {
    RenderMacroCards(win, ctrl.Text, win.__searchBox.Value)
}

CategorySearchChanged(win, ctrl, *) {
    RenderMacroCards(win, win.__creatorDDL.Text, ctrl.Value)
}

ReadMacroInfo(macroDir) {
    info := { Title: "", Creator: "", Version: "", Links: "" }
    ini := macroDir "\info.ini"

    SplitPath macroDir, &folder
    info.Title := folder

    if !FileExist(ini)
        return info

    txt := FileRead(ini, "UTF-8")
    
    for line in StrSplit(txt, "`n") {
        line := Trim(StrReplace(line, "`r"))
        if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
            continue

        if !InStr(line, "=")
            continue

        parts := StrSplit(line, "=", , 2)
        k := StrLower(Trim(parts[1]))
        v := Trim(parts[2])

        switch k {
            case "title": info.Title := v
            case "creator": info.Creator := v
            case "version": info.Version := v
            case "links": info.Links := v
        }
    }

    if (info.Version = "")
        info.Version := "1.0"

    return info
}

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
        MsgBox "Couldn't download manifest.json"
        return
    }

    json := FileRead(tmpManifest, "UTF-8")
    latest := JsonGet(json, "version")
    changes := JsonGetArray(json, "changelog")

    text := ""
    if (changes.Length > 0) {
        for line in changes
            text .= "• " line "`n"
    }

    if (text = "")
        text := "(No changelog)"

    MsgBox "Version: " latest "`n`n" text, "Changelog", "Iconi"
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

    msg := "Launcher update available.`n`nCurrent: " LAUNCHER_VERSION "`nLatest: " latestVer "`n`nUpdate?"
    if MsgBox(msg, "Update", "YesNo Iconi") = "No"
        return

    DoSelfUpdate(latestUrl, latestVer)
}

DoSelfUpdate(url, newVer) {
    tmpNew := A_Temp "\launcher_new.ahk"
    if !SafeDownload(url, tmpNew) {
        MsgBox "Download failed."
        return
    }

    me := A_ScriptFullPath
    cmdPath := A_Temp "\update_launcher.cmd"

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

    try FileDelete cmdPath
    FileAppend cmd, cmdPath, "UTF-8"

    Run '"' cmdPath '"', , "Hide"
    ExitApp
}
