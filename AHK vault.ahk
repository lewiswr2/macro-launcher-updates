#Requires AutoHotkey v2.0
#SingleInstance Force


; ================= GLOBAL CONFIG =================
global MANIFEST_URL := "https://tight-dust-10d2.lewisjenkins558.workers.dev/manifest"
global WORKER_URL   := "https://tight-dust-10d2.lewisjenkins558.workers.dev"

global APP_DIR  := A_AppData "\MacroLauncher"
global BASE_DIR := APP_DIR "\Macros"
global ICON_DIR := BASE_DIR "\Icons"
global LAUNCHER_PATH := APP_DIR "\MacroLauncher.ahk"

; files (stored under APP_DIR for simplicity)
global CRED_DIR := APP_DIR
global CRED_FILE := CRED_DIR "\.sysauth"
global LAST_CRED_HASH_FILE := CRED_DIR "\.last_cred_hash"
global SESSION_FILE := CRED_DIR "\.session"

global MASTER_KEY_FILE := CRED_DIR "\.master_key"
global MASTER_KEY := "SDFJNSDFJKBSJFBSDKFSDBJFKSDFB"

global DISCORD_ID_FILE := APP_DIR "\discord_id.txt"
global DISCORD_BAN_FILE := APP_DIR "\banned_discord_ids.txt"
global ADMIN_DISCORD_FILE := APP_DIR "\admin_discord_ids.txt"

global SESSION_LOG_FILE := APP_DIR "\sessions.log"

global DEFAULT_USER := "V1LnClan@discord"
global MASTER_USER := "master"
global ADMIN_PASS := "ADMIN123"

global MAX_ATTEMPTS := 3
global LOCKOUT_FILE := A_Temp "\.lockout"
global LAST_SEEN_CRED_HASH_FILE := CRED_DIR "\.cred_hash_seen"


global DISCORD_WEBHOOK := "https://discord.com/api/webhooks/1459301039651164424/5vZ7DokPWu9V-qIreXKXQFdsqXaUaDTMd_zGHp19idUyvZUshczKGlvVVM7sVSC6vOkW"

; ================= THEME (black + gold) =================
global COLORS := {
    bg: "0x0a0e14",
    bgLight: "0x13171d",
    card: "0x161b22",
    border: "0x21262d",
    accent: "0xD4AF37",
    accentAlt: "0x238636",
    text: "0xe6edf3",
    textDim: "0x7d8590",
    danger: "0xda3633",
    gold: "0xD4AF37"
}

global gLoginGui := 0

; ================= HOTKEY =================
#HotIf
^!p:: AdminPanel()
#HotIf

; ================= STARTUP =================
InitDirs()
SetupTray()
LoadMasterKey()

; ✅ Always sync global lists/creds FIRST
RefreshManifestAndLauncherBeforeLogin()
SetTimer(CheckCredHashTicker, 60000) ; every 60s

CheckLockout()
EnsureDiscordId()

; ✅ Now bans are accurate
if IsDiscordBanned() {
    MsgBox "🚫 This Discord ID is permanently banned.`n`nDiscord ID: " ReadDiscordId(), "v1ln clan - Banned", "Icon! 0x10"
    ExitApp
}

; ✅ Don’t let saved sessions bypass a ban
if CheckSession() {
    RefreshManifestAndLauncherBeforeLogin()
    if IsDiscordBanned()
        ExitApp
    LaunchMainProgram()
    return
}

CreateLoginGui()
return



; ================= TRAY =================
SetupTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Open Admin Panel (Ctrl+Alt+P)", (*) => AdminPanel())
    A_TrayMenu.Add("Open MacroLauncher", (*) => LaunchMainProgram())
    A_TrayMenu.Add("Copy My Discord ID", (*) => (A_Clipboard := ReadDiscordId(), MsgBox("Copied Discord ID ✅", "v1ln clan", "Iconi")))
    A_TrayMenu.Add("Clear Saved Session", (*) => ClearSession())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
}

; ================= DIRS =================
InitDirs() {
    global APP_DIR, BASE_DIR, ICON_DIR, CRED_DIR
    try {
        DirCreate APP_DIR
        DirCreate BASE_DIR
        DirCreate ICON_DIR

        if !DirExist(CRED_DIR) {
            DirCreate CRED_DIR
            Run 'attrib +h "' CRED_DIR '"', , "Hide"
        }
    } catch as err {
        MsgBox "Failed to init folders:`n" err.Message, "v1ln clan - Init Error", "Icon!"
        ExitApp
    }
}

; ================= MASTER KEY PERSIST =================
LoadMasterKey() {
    global MASTER_KEY_FILE, MASTER_KEY
    try {
        if FileExist(MASTER_KEY_FILE) {
            k := Trim(FileRead(MASTER_KEY_FILE, "UTF-8"))
            if (k != "")
                MASTER_KEY := k
        }
    } catch {
    }
}

SaveMasterKey(newKey) {
    global MASTER_KEY_FILE, MASTER_KEY
    newKey := Trim(newKey)
    if (newKey = "")
        return false

    try {
        if FileExist(MASTER_KEY_FILE)
            FileDelete MASTER_KEY_FILE
        FileAppend newKey, MASTER_KEY_FILE
        Run 'attrib +h "' MASTER_KEY_FILE '"', , "Hide"
        MASTER_KEY := newKey
        return true
    } catch {
        return false
    }
}

; ================= HASH =================
HashPassword(password) {
    salt := "V1LN_CLAN_2026"
    combined := salt . password . salt

    hash := 0
    loop parse combined
        hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)

    hash2 := hash
    loop 1000
        hash2 := Mod(hash2 * 37 + hash + A_Index, 2147483647)

    return hash2
}

; ================= MANIFEST PARSERS =================
ParseManifestForCredsAndLauncher(json) {
    obj := { cred_user: "", cred_hash: "", launcher_url: "" }
    try {
        if RegExMatch(json, '"cred_user"\s*:\s*"([^"]+)"', &m1)
            obj.cred_user := m1[1]
        if RegExMatch(json, '"cred_hash"\s*:\s*"([^"]+)"', &m2)
            obj.cred_hash := m2[1]
        if RegExMatch(json, '"launcher_url"\s*:\s*"([^"]+)"', &m3)
            obj.launcher_url := m3[1]
    } catch {
        return false
    }
    return obj
}

ParseManifestLists(json) {
    obj := { banned: [], admins: [] }

    ; (?s) makes . match newlines (DOTALL), so multi-line arrays work
    if RegExMatch(json, '(?s)"banned_discord_ids"\s*:\s*\[(.*?)\]', &m1) {
        inner := m1[1]
        pos := 1
        while (pos := RegExMatch(inner, '"(\d{6,30})"', &mItem, pos)) {
            obj.banned.Push(mItem[1])
            pos += StrLen(mItem[0])
        }
    }

    if RegExMatch(json, '(?s)"admin_discord_ids"\s*:\s*\[(.*?)\]', &m2) {
        inner := m2[1]
        pos := 1
        while (pos := RegExMatch(inner, '"(\d{6,30})"', &mItem2, pos)) {
            obj.admins.Push(mItem2[1])
            pos += StrLen(mItem2[0])
        }
    }

    return obj
}

OverwriteListFile(filePath, arr) {
    try {
        ; If list is empty → remove the file completely (stealth)
        if (arr.Length = 0) {
            if FileExist(filePath)
                FileDelete filePath
            return
        }

        ; Otherwise write the list normally
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




; ================= MANIFEST REFRESH (runs when login opens) =================
RefreshManifestAndLauncherBeforeLogin() {
    global MANIFEST_URL, CRED_FILE, SESSION_FILE, LAST_CRED_HASH_FILE
    global LAUNCHER_PATH, DISCORD_BAN_FILE, ADMIN_DISCORD_FILE

    tmp := A_Temp "\manifest.json"
    if !SafeDownload(MANIFEST_URL, tmp, 30000)
        return false

    json := ""
    try json := FileRead(tmp, "UTF-8")
    catch {
        return false
    }

    ; Sync global ban/admin lists from manifest
    lists := ParseManifestLists(json)
    if IsObject(lists) {
        OverwriteListFile(DISCORD_BAN_FILE, lists.banned)
        OverwriteListFile(ADMIN_DISCORD_FILE, lists.admins)
    }

    mf := ParseManifestForCredsAndLauncher(json)
    if !IsObject(mf)
        return false

    user := Trim(mf.cred_user)
    hash := Trim(mf.cred_hash)
    lurl := Trim(mf.launcher_url)

    if (user = "" || hash = "")
        return false

    last := ""
    try {
        if FileExist(LAST_CRED_HASH_FILE)
            last := Trim(FileRead(LAST_CRED_HASH_FILE, "UTF-8"))
    } catch {
        last := ""
    }

    ; Write creds
    try {
        if FileExist(CRED_FILE)
            FileDelete CRED_FILE
        FileAppend user "|" hash, CRED_FILE
        Run 'attrib +h "' CRED_FILE '"', , "Hide"
    } catch {
    }

    ; If creds changed, force re-login
    if (last != "" && last != hash) {
        try FileDelete SESSION_FILE
    }

    ; Save last hash
    try {
        if FileExist(LAST_CRED_HASH_FILE)
            FileDelete LAST_CRED_HASH_FILE
        FileAppend hash, LAST_CRED_HASH_FILE
        Run 'attrib +h "' LAST_CRED_HASH_FILE '"', , "Hide"
    } catch {
    }

    ; Download MacroLauncher.ahk
    if (lurl != "") {
        SafeDownload(lurl, LAUNCHER_PATH, 30000)
    }

    return true
}

; ================= DOWNLOAD =================
SafeDownload(url, dest, timeout := 30000) {
    try {
        SplitPath dest, , &dir
        if (dir != "" && !DirExist(dir))
            DirCreate dir

        tmpDest := dest ".tmp"
        if FileExist(tmpDest)
            FileDelete tmpDest

        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Option[6] := 1
        req.SetTimeouts(timeout, timeout, timeout, timeout)
        req.Open("GET", url, false)
        req.SetRequestHeader("User-Agent", "v1ln-clan")
        req.Send()

        if (req.Status != 200)
            return false

        stream := ComObject("ADODB.Stream")
        stream.Type := 1
        stream.Open()
        stream.Write(req.ResponseBody)
        stream.SaveToFile(tmpDest, 2)
        stream.Close()

        if !FileExist(tmpDest) || (FileGetSize(tmpDest) < 10)
            return false

        if FileExist(dest)
            FileDelete dest
        FileMove tmpDest, dest, 1
        return true
    } catch {
        return false
    }
}

; ================= DISCORD ID =================
EnsureDiscordId() {
    global DISCORD_ID_FILE
    try {
        if FileExist(DISCORD_ID_FILE) {
            id := Trim(FileRead(DISCORD_ID_FILE, "UTF-8"))
            if RegExMatch(id, "^\d{6,30}$")
                return
        }
    } catch {
    }

    id := PromptDiscordIdGui()
    if (id = "") {
        MsgBox "Discord ID is required.", "v1ln clan - Required", "Icon! 0x10"
        ExitApp
    }
}

PromptDiscordIdGui() {
    global DISCORD_ID_FILE, COLORS

    didGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "v1ln clan - Discord ID Required")
    didGui.BackColor := COLORS.bg
    didGui.SetFont("s9 c" COLORS.text, "Segoe UI")

    didGui.Add("Text", "x12 y10 w520 c" COLORS.text, "Enter your Discord User ID (numbers only).")
    didGui.Add("Text", "x12 y34 w520 c" COLORS.textDim, "Discord → Developer Mode → Right-click profile → Copy ID")

    didEdit := didGui.Add("Edit", "x12 y60 w520 h28 Background" COLORS.bgLight " c" COLORS.text)
    copyBtn := didGui.Add("Button", "x12 y98 w110 h30", "Copy")
    saveBtn := didGui.Add("Button", "x422 y98 w110 h30", "Save")
    cancelBtn := didGui.Add("Button", "x302 y98 w110 h30", "Cancel")
    status := didGui.Add("Text", "x12 y135 w520 c" COLORS.textDim, "")

    resultId := ""

    copyBtn.OnEvent("Click", (*) => (
        A_Clipboard := Trim(didEdit.Value),
        status.Value := (Trim(didEdit.Value) = "" ? "Nothing to copy yet." : "Copied ✅")
    ))

    saveBtn.OnEvent("Click", (*) => (
        did := Trim(didEdit.Value),
        (!RegExMatch(did, "^\d{6,30}$")
            ? (status.Value := "Invalid ID. Numbers only.", SoundBeep(700, 120))
            : (resultId := did, didGui.Destroy())
        )
    ))

    cancelBtn.OnEvent("Click", (*) => (resultId := "", didGui.Destroy()))
    didGui.OnEvent("Close", (*) => (resultId := "", didGui.Destroy()))

    didGui.Show("w550 h175")
    WinWaitClose(didGui.Hwnd)

    if (resultId = "")
        return ""

    try {
        if FileExist(DISCORD_ID_FILE)
            FileDelete DISCORD_ID_FILE
        FileAppend resultId, DISCORD_ID_FILE
    } catch {
    }

    return resultId
}

ReadDiscordId() {
    global DISCORD_ID_FILE
    try if FileExist(DISCORD_ID_FILE)
        return Trim(FileRead(DISCORD_ID_FILE, "UTF-8"))
    return ""
}

; ================= LOCAL LIST HELPERS =================
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

IsDiscordBanned() {
    global DISCORD_BAN_FILE

    if !FileExist(DISCORD_BAN_FILE)
        return false

    did := ReadDiscordId()
    if (did = "")
        return false

    try {
        txt := FileRead(DISCORD_BAN_FILE, "UTF-8")
    } catch {
        return false
    }

    for line in StrSplit(txt, "`n") {
        if (Trim(line) = did)
            return true
    }

    return false
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

IsAdminDiscordId() {
    global ADMIN_DISCORD_FILE
    did := StrLower(Trim(ReadDiscordId()))
    if (did = "")
        return false
    for x in GetLinesFromFile(ADMIN_DISCORD_FILE) {
        if (StrLower(Trim(x)) = did)
            return true
    }
    return false
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
        lblCtrl.Value := "Admin Discord IDs: (none)   (ADMIN_PASS required)"
        return
    }
    s := "Admin Discord IDs: "
    for id in ids
        s .= id ", "
    lblCtrl.Value := RTrim(s, ", ") "   (ADMIN_PASS required)"
}

; ================= LOCKOUT =================
CheckLockout() {
    global LOCKOUT_FILE, MASTER_KEY
    if !FileExist(LOCKOUT_FILE)
        return

    try {
        lockTime := Trim(FileRead(LOCKOUT_FILE))
        diff := DateDiff(A_Now, lockTime, "Minutes")
        if (diff >= 30) {
            try FileDelete LOCKOUT_FILE
            return
        }

        remaining := 30 - diff
        choice := MsgBox(
            "🔒 ACCOUNT LOCKED`n`nRemaining: " remaining " minutes`n`nYES = Master unlock, NO = exit",
            "v1ln clan - Lockout",
            "YesNo Icon! 0x10"
        )

        if (choice = "Yes") {
            ib := InputBox("Enter MASTER KEY to remove lockout:", "v1ln clan - Unlock", "Password w460 h170")
            if (ib.Result = "OK" && Trim(ib.Value) = MASTER_KEY) {
                try FileDelete LOCKOUT_FILE
                MsgBox "✅ Lockout removed.", "v1ln clan", "Iconi"
                return
            }
        }
        ExitApp
    } catch {
        try FileDelete LOCKOUT_FILE
    }
}

; ================= SESSION =================
GetMachineHash() {
    machineInfo := A_ComputerName A_UserName
    hash := 0
    loop parse machineInfo
        hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)
    return hash
}

CreateSession(loginUser := "", role := "user") {
    global SESSION_FILE, SESSION_LOG_FILE
    try {
        t := A_Now
        mh := GetMachineHash()
        pc := A_ComputerName
        did := ReadDiscordId()

        if FileExist(SESSION_FILE)
            FileDelete SESSION_FILE

        FileAppend t "|" mh "|" loginUser "|" role, SESSION_FILE
        Run 'attrib +h "' SESSION_FILE '"', , "Hide"

        FileAppend t "|" pc "|" did "|" role "|" mh "`n", SESSION_LOG_FILE
    } catch {
    }
}
CheckSession() {
    global SESSION_FILE, CRED_FILE, LAST_SEEN_CRED_HASH_FILE

    if !FileExist(SESSION_FILE)
        return false

    ; read session
    try {
        data := FileRead(SESSION_FILE, "UTF-8")
        parts := StrSplit(data, "|")
        if (parts.Length < 2)
            return false

        t := parts[1]
        mh := parts[2]

        ; basic session rules
        if (DateDiff(A_Now, t, "Hours") > 24)
            return false
        if (mh != GetMachineHash())
            return false
        if IsDiscordBanned()
            return false
    } catch {
        return false
    }

    ; NEW: force logout if cred_hash changed since last time on THIS PC
    currentHash := ""
    try {
        if FileExist(CRED_FILE) {
            credData := FileRead(CRED_FILE, "UTF-8")
            credParts := StrSplit(credData, "|")
            if (credParts.Length >= 2)
                currentHash := Trim(credParts[2])
        }
    } catch {
        currentHash := ""
    }

    if (currentHash != "") {
        seen := ""
        try {
            if FileExist(LAST_SEEN_CRED_HASH_FILE)
                seen := Trim(FileRead(LAST_SEEN_CRED_HASH_FILE, "UTF-8"))
        } catch {
            seen := ""
        }

        ; first run: record hash
        if (seen = "") {
            try {
                if FileExist(LAST_SEEN_CRED_HASH_FILE)
                    FileDelete LAST_SEEN_CRED_HASH_FILE
                FileAppend currentHash, LAST_SEEN_CRED_HASH_FILE
                Run 'attrib +h "' LAST_SEEN_CRED_HASH_FILE '"', , "Hide"
            } catch {
            }
        } else if (seen != currentHash) {
            ; hash changed -> log out
            try FileDelete SESSION_FILE
            try {
                if FileExist(LAST_SEEN_CRED_HASH_FILE)
                    FileDelete LAST_SEEN_CRED_HASH_FILE
                FileAppend currentHash, LAST_SEEN_CRED_HASH_FILE
                Run 'attrib +h "' LAST_SEEN_CRED_HASH_FILE '"', , "Hide"
            } catch {
            }
            return false
        }
    }

    return true
}


ClearSession() {
    global SESSION_FILE
    if FileExist(SESSION_FILE) {
        try FileDelete SESSION_FILE
        MsgBox "✅ Session cleared.", "v1ln clan", "Iconi"
    } else {
        MsgBox "ℹ️ No session found.", "v1ln clan", "Iconi"
    }
}

; ================= WEBHOOK LOGGING =================
SendDiscordLogin(role, loginUser) {
    global DISCORD_WEBHOOK
    if (DISCORD_WEBHOOK = "")
        return

    did := ReadDiscordId()
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")

    msg := "Login detected"
        . "`nRole: " role
        . "`nDiscord ID: " did
        . "`nPC Name: " A_ComputerName
        . "`nWindows User: " A_UserName
        . "`nLogin Username: " loginUser
        . "`nTime: " ts

    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

DiscordWebhookPost(webhookUrl, content) {
    try {
        json := '{"content":"' JsonEscape(content) '"}'
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Option[6] := 1
        req.SetTimeouts(15000, 15000, 15000, 15000)
        req.Open("POST", webhookUrl, false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.SetRequestHeader("User-Agent", "v1ln-clan")
        req.Send(json)
    } catch {
    }
}

JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

; ================= WORKER POST =================
WorkerPost(endpoint, bodyJson) {
    global WORKER_URL, MASTER_KEY

    url := RTrim(WORKER_URL, "/") "/" LTrim(endpoint, "/")

    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Option[6] := 1
    req.SetTimeouts(15000, 15000, 15000, 15000)
    req.Open("POST", url, false)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetRequestHeader("X-Master-Key", MASTER_KEY)
    req.SetRequestHeader("User-Agent", "v1ln-clan")
    req.Send(bodyJson)

    status := req.Status
    resp := ""
    try resp := req.ResponseText

    if (status < 200 || status >= 300) {
        throw Error("Worker error " status ": " resp)
    }
    return resp
}

; ================= LOGIN GUI =================
CreateLoginGui() {
    global COLORS, gLoginGui

    RefreshManifestAndLauncherBeforeLogin()

    if IsDiscordBanned() {
        MsgBox "🚫 This Discord ID is permanently banned.`n`nDiscord ID: " ReadDiscordId(), "v1ln clan - Banned", "Icon! 0x10"
        ExitApp
    }

    gLoginGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "v1ln clan - Login")
    loginGui := gLoginGui

    loginGui.BackColor := COLORS.bg
    loginGui.SetFont("s10 c" COLORS.text, "Segoe UI")

    loginGui.Add("Text", "x0 y0 w450 h85 Center Background" COLORS.bgLight, "")
    crown := loginGui.Add("Text", "x0 y18 w450 h30 Center c" COLORS.gold, "👑")
    crown.SetFont("s20")
    title := loginGui.Add("Text", "x0 y48 w450 h30 Center c" COLORS.gold, "v1ln clan")
    title.SetFont("s16 bold")

    loginGui.Add("Text", "x40 y95 w370 h220 Background" COLORS.card, "")

    loginGui.Add("Text", "x60 y115 w330 c" COLORS.textDim, "USERNAME")
    userEdit := loginGui.Add("Edit", "x60 y135 w330 h32 Background" COLORS.bgLight " c" COLORS.text)

    loginGui.Add("Text", "x60 y175 w330 c" COLORS.textDim, "PASSWORD")
    passEdit := loginGui.Add("Edit", "x60 y195 w330 h32 Password Background" COLORS.bgLight " c" COLORS.text)

    btn := loginGui.Add("Button", "x60 y245 w330 h42 Background" COLORS.accent, "LOGIN")
    btn.SetFont("s12 bold c" COLORS.bg)
    btn.OnEvent("Click", (*) => AttemptLogin(userEdit, passEdit))

    adminLink := loginGui.Add("Text", "x60 y295 w330 Center c" COLORS.gold, "Admin Panel (Master Key) • Ctrl+Alt+P")
    adminLink.OnEvent("Click", (*) => AdminPanel())

    loginGui.OnEvent("Close", (*) => ExitApp())
    loginGui.Show("w450 h345")
}

DestroyLoginGui() {
    global gLoginGui
    try {
        if IsObject(gLoginGui)
            gLoginGui.Destroy()
    } catch {
    }
    gLoginGui := 0
}

AttemptLogin(usernameCtrl, passwordCtrl) {
    global CRED_FILE, MAX_ATTEMPTS, LOCKOUT_FILE
    global MASTER_USER, MASTER_KEY, ADMIN_PASS
    static attemptCount := 0



    if IsDiscordBanned() {
        MsgBox "🚫 This Discord ID is banned.", "v1ln clan - Banned", "Icon! 0x10"
        return
    }

    username := Trim(usernameCtrl.Value)
    password := Trim(passwordCtrl.Value)

    if (username = "" || password = "") {
        MsgBox "Enter username and password.", "v1ln clan - Login", "Icon!"
        return
    }

    ; MASTER
    if (StrLower(username) = StrLower(MASTER_USER) && password = MASTER_KEY) {
        attemptCount := 0
        CreateSession(MASTER_USER, "master")
        SendDiscordLogin("master", MASTER_USER)
        DestroyLoginGui()
        AdminPanel(true)
        return
    }

    ; ADMIN: ADMIN_PASS + Discord ID in admin list
    if (password = ADMIN_PASS && IsAdminDiscordId()) {
        attemptCount := 0
        CreateSession(username, "admin")
        SendDiscordLogin("admin", username)
        DestroyLoginGui()
        LaunchMainProgram()
        return
    }

    ; USER: manifest creds
    try {
credData := FileRead(CRED_FILE)
parts := StrSplit(credData, "|")
if (parts.Length < 2) {
    MsgBox "Credential file missing/corrupt.", "v1ln clan - Error", "Icon!"
    return
}

storedUser := Trim(parts[1])
storedHash := Trim(parts[2])



if (StrLower(username) = StrLower(storedUser) && HashPassword(password) = Integer(storedHash)) {
    
}


        storedUser := Trim(parts[1])
        storedHash := Trim(parts[2])

        if (StrLower(username) = StrLower(storedUser) && HashPassword(password) = Integer(storedHash)) {
            attemptCount := 0
            CreateSession(storedUser, "user")
            SendDiscordLogin("user", storedUser)
            DestroyLoginGui()
            LaunchMainProgram()
            return
        }

        attemptCount += 1
        remaining := MAX_ATTEMPTS - attemptCount
        if (remaining > 0) {
            MsgBox "Invalid login.`nAttempts remaining: " remaining, "v1ln clan - Login Failed", "Icon! 0x30"
            passwordCtrl.Value := ""
            passwordCtrl.Focus()
            return
        }

        FileAppend A_Now, LOCKOUT_FILE
        MsgBox "ACCOUNT LOCKED (too many fails).", "v1ln clan - Lockout", "Icon! 0x10"
        ExitApp
    } catch as err {
        MsgBox "Login error:`n" err.Message, "v1ln clan - Error", "Icon!"
    }
}

; ================= ADMIN PANEL =================
AdminPanel(alreadyAuthed := false) {
    global MASTER_KEY, COLORS, DEFAULT_USER

    if !alreadyAuthed {
        ib := InputBox("Enter MASTER KEY to open Admin Panel:", "v1ln clan - Admin Panel", "Password w460 h170")
        if (ib.Result != "OK")
            return
        if (Trim(ib.Value) != MASTER_KEY) {
            MsgBox "❌ Invalid master key.", "v1ln clan - Access Denied", "Icon! 0x10"
            return
        }
    }

    adminGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "v1ln clan - Admin Panel")
    adminGui.BackColor := COLORS.bg
    adminGui.SetFont("s9 c" COLORS.gold, "Segoe UI")

    adminGui.Add("Text", "x10 y10 w820 c" COLORS.gold, "✅ Login Log (successful logins)")
    lv := adminGui.Add("ListView", "x10 y30 w820 h220", ["Time", "PC Name", "Discord ID", "Role", "MachineHash"])
    LoadSessionLogIntoListView(lv)

    adminGui.Add("Text", "x10 y260 w820 c" COLORS.gold, "🔒 Global Ban (by Discord ID)")
    adminGui.Add("Text", "x10 y285 w120 c" COLORS.gold, "Discord ID:")
    banEdit := adminGui.Add("Edit", "x130 y281 w320 h26 Background" COLORS.bgLight " c" COLORS.text)
    banBtn := adminGui.Add("Button", "x470 y281 w90 h26", "BAN")
    unbanBtn := adminGui.Add("Button", "x570 y281 w90 h26", "UNBAN")
    bannedLbl := adminGui.Add("Text", "x10 y315 w820 c" COLORS.gold, "")
RefreshBannedFromServer(bannedLbl)


    adminGui.Add("Text", "x10 y345 w820 c" COLORS.gold, "🛡️ Global Admin Discord IDs (ADMIN_PASS required)")
    adminGui.Add("Text", "x10 y370 w120 c" COLORS.gold, "Discord ID:")
    adminEdit := adminGui.Add("Edit", "x130 y366 w320 h26 Background" COLORS.bgLight " c" COLORS.text)
    addAdminBtn := adminGui.Add("Button", "x470 y366 w90 h26", "Add")
    delAdminBtn := adminGui.Add("Button", "x570 y366 w90 h26", "Remove")
    addThisPcBtn := adminGui.Add("Button", "x670 y366 w160 h26", "Add THIS PC ID")
    adminLbl := adminGui.Add("Text", "x10 y400 w820 c" COLORS.gold, "")
    RefreshAdminDiscordLabel(adminLbl)

    refreshBtn := adminGui.Add("Button", "x10 y430 w120 h28", "Refresh Log")
    clearLogBtn := adminGui.Add("Button", "x140 y430 w120 h28", "Clear Log")
    copySnippetBtn := adminGui.Add("Button", "x280 y430 w260 h28", "Copy manifest credential snippet")
    changeMasterBtn := adminGui.Add("Button", "x560 y430 w170 h28", "Change Master Key")

    banBtn.OnEvent("Click", OnBanDiscordId.Bind(banEdit, bannedLbl))
    unbanBtn.OnEvent("Click", OnUnbanDiscordId.Bind(banEdit, bannedLbl))
    addAdminBtn.OnEvent("Click", OnAddAdminDiscord.Bind(adminEdit, adminLbl))
    delAdminBtn.OnEvent("Click", OnRemoveAdminDiscord.Bind(adminEdit, adminLbl))
    addThisPcBtn.OnEvent("Click", OnAddThisPcAdmin.Bind(adminLbl))
    refreshBtn.OnEvent("Click", OnRefreshLog.Bind(lv))
    clearLogBtn.OnEvent("Click", OnClearLog.Bind(lv))
    copySnippetBtn.OnEvent("Click", OnCopySnippet.Bind(DEFAULT_USER))
    changeMasterBtn.OnEvent("Click", OnChangeMasterKey.Bind())

    adminGui.OnEvent("Close", (*) => adminGui.Destroy())
    adminGui.Show("w845 h475")
}

OnBanDiscordId(banEdit, bannedLbl, *) {
    did := Trim(banEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "v1ln clan - Admin", "Icon!"
        return
    }

    try {
        WorkerPost("/ban", '{"discord_id":"' did '"}')
        ; local immediate effect
        AddBannedDiscordId(did)
        RefreshBannedDiscordLabel(bannedLbl)
        MsgBox "✅ Globally BANNED: " did, "v1ln clan - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to ban globally:`n" err.Message, "v1ln clan - Admin", "Icon!"
    }
}

OnUnbanDiscordId(banEdit, bannedLbl, *) {
    did := Trim(banEdit.Value)
    did := RegExReplace(did, "[^\d]", "")  ; strip anything not digit

    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "v1ln clan - Admin", "Icon!"
        return
    }

    try {
        ; 1) Update global manifest via Worker
        WorkerPost("/unban", '{"discord_id":"' did '"}')

        ; 2) Pull server truth and overwrite local files
        lists := ResyncListsFromManifestNow()

        ; 3) Update label from the now-synced local file
        RefreshBannedDiscordLabel(bannedLbl)

        ; 4) Confirm result
        stillThere := false
        for x in lists.banned {
            if (Trim(x) = did) {
                stillThere := true
                break
            }
        }

        if stillThere {
            MsgBox "⚠️ Unban request sent, but ID is STILL in global manifest.`n`nID: " did, "v1ln clan - Admin", "Icon! 0x30"
        } else {
            MsgBox "✅ Globally UNBANNED: " did, "v1ln clan - Admin", "Iconi"
        }
    } catch as err {
        MsgBox "❌ Failed to unban globally:`n" err.Message, "v1ln clan - Admin", "Icon!"
    }
}


OnAddAdminDiscord(adminEdit, adminLbl, *) {
    did := Trim(adminEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "v1ln clan - Admin", "Icon!"
        return
    }

    try {
        WorkerPost("/admin/add", '{"discord_id":"' did '"}')
        AddAdminDiscordId(did)
        RefreshAdminDiscordLabel(adminLbl)
        MsgBox "✅ Globally added admin: " did, "v1ln clan - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to add admin globally:`n" err.Message, "v1ln clan - Admin", "Icon!"
    }
}

OnRemoveAdminDiscord(adminEdit, adminLbl, *) {
    did := Trim(adminEdit.Value)
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "Enter a valid Discord ID (numbers only).", "v1ln clan - Admin", "Icon!"
        return
    }

    try {
        WorkerPost("/admin/remove", '{"discord_id":"' did '"}')
        RemoveAdminDiscordId(did)
        RefreshAdminDiscordLabel(adminLbl)
        MsgBox "✅ Globally removed admin: " did, "v1ln clan - Admin", "Iconi"
    } catch as err {
        MsgBox "❌ Failed to remove admin globally:`n" err.Message, "v1ln clan - Admin", "Icon!"
    }
}

OnAddThisPcAdmin(adminLbl, *) {
    did := Trim(ReadDiscordId())
    if (did = "" || !RegExMatch(did, "^\d{6,30}$")) {
        MsgBox "This PC does not have a valid Discord ID saved.", "v1ln clan - Admin", "Icon! 0x30"
        return
    }
    ; Use global endpoint too:
    try {
        WorkerPost("/admin/add", '{"discord_id":"' did '"}')
    } catch {
        ; even if worker fails, keep local
    }
    AddAdminDiscordId(did)
    RefreshAdminDiscordLabel(adminLbl)
    MsgBox "✅ Added THIS PC as admin:`n" did, "v1ln clan - Admin", "Iconi"
}

OnRefreshLog(lv, *) {
    lv.Delete()
    LoadSessionLogIntoListView(lv)
}

OnClearLog(lv, *) {
    global SESSION_LOG_FILE
    if FileExist(SESSION_LOG_FILE) {
        FileDelete SESSION_LOG_FILE
        lv.Delete()
        MsgBox "✅ Login log cleared.", "v1ln clan - Admin", "Iconi"
    } else {
        MsgBox "ℹ️ No log found.", "v1ln clan - Admin", "Iconi"
    }
}

OnCopySnippet(defaultUser, *) {
    CopyManifestCredentialSnippet(defaultUser)
}

OnChangeMasterKey(*) {
    global MASTER_KEY

    ib := InputBox("Enter CURRENT Master Key to change it:", "v1ln clan - Change Master Key", "Password w520 h180")
    if (ib.Result != "OK")
        return
    if (Trim(ib.Value) != MASTER_KEY) {
        MsgBox "❌ Current master key incorrect.", "v1ln clan - Denied", "Icon! 0x10"
        return
    }

    nb := InputBox("Enter NEW Master Key:", "v1ln clan - New Master Key", "Password w520 h180")
    if (nb.Result != "OK")
        return
    newKey := Trim(nb.Value)
    if (newKey = "") {
        MsgBox "Master key cannot be blank.", "v1ln clan - Invalid", "Icon! 0x30"
        return
    }

    cb := InputBox("Confirm NEW Master Key:", "v1ln clan - Confirm Master Key", "Password w520 h180")
    if (cb.Result != "OK")
        return
    if (Trim(cb.Value) != newKey) {
        MsgBox "❌ Keys do not match.", "v1ln clan - Invalid", "Icon! 0x30"
        return
    }

    if SaveMasterKey(newKey) {
        MsgBox "✅ Master key updated and saved on this PC.", "v1ln clan - Success", "Iconi"
    } else {
        MsgBox "❌ Failed to save master key.", "v1ln clan - Error", "Icon! 0x10"
    }
}

; ================= LOG VIEW =================
LoadSessionLogIntoListView(lv) {
    global SESSION_LOG_FILE
    if !FileExist(SESSION_LOG_FILE)
        return

    try {
        txt := FileRead(SESSION_LOG_FILE, "UTF-8")
        for line in StrSplit(txt, "`n", "`r") {
            line := Trim(line)
            if (line = "")
                continue

            ; expected: time|pc|did|role|machineHash
            parts := StrSplit(line, "|")
            t := (parts.Length >= 1) ? parts[1] : ""
            pc := (parts.Length >= 2) ? parts[2] : ""
            did := (parts.Length >= 3) ? parts[3] : ""
            role := (parts.Length >= 4) ? parts[4] : ""
            hash := (parts.Length >= 5) ? parts[5] : ""

            lv.Add("", t, pc, did, role, hash)
        }
    } catch {
    }
}

; ================= MANIFEST SNIPPET TOOL =================
CopyManifestCredentialSnippet(username) {
    pw := InputBox(
        "Enter the NEW universal password.`n`nThis will copy cred_user + cred_hash for manifest.json.",
        "v1ln clan - Generate manifest snippet",
        "Password w560 h190"
    )
    if (pw.Result != "OK")
        return

    newPass := Trim(pw.Value)
    if (newPass = "") {
        MsgBox "Password cannot be blank.", "v1ln clan - Invalid", "Icon! 0x30"
        return
    }

    h := HashPassword(newPass)
    snippet := '"cred_user": "' username '",' "`n" '"cred_hash": "' h '"'
    A_Clipboard := snippet

    MsgBox "✅ Copied to clipboard.`n`nPaste into manifest.json:`n`n" snippet, "v1ln clan", "Iconi"
}

; ================= LAUNCH =================
LaunchMainProgram() {
    global LAUNCHER_PATH, APP_DIR

    diag := "USER: " A_UserName "`n"
        . "COMPUTER: " A_ComputerName "`n"
        . "A_AppData: " A_AppData "`n"
        . "APP_DIR: " APP_DIR "`n"
        . "LAUNCHER_PATH: " LAUNCHER_PATH "`n"
        . "FileExist(LAUNCHER_PATH): " (FileExist(LAUNCHER_PATH) ? "YES" : "NO") "`n"
        . "A_AhkPath: " A_AhkPath "`n"
        . "FileExist(A_AhkPath): " (FileExist(A_AhkPath) ? "YES" : "NO")

    launcher := LAUNCHER_PATH

    if !FileExist(launcher) {
        found := FindMacroLauncher()
        if (found != "")
            launcher := found
    }

    if !FileExist(launcher) {
        MsgBox(
            "❌ MacroLauncher.ahk not found.`n`n"
            . diag "`n`n"
            . "Tip: If you're running as a different Windows user/admin, AppData may point elsewhere.",
            "v1ln clan - Launcher Missing",
            "Icon! 0x10"
        )
        return
    }

    ; Try launching with current AHK interpreter first
    if FileExist(A_AhkPath) {
        try {
            Run '"' A_AhkPath '" "' launcher '"'
            return
        } catch as err {
            MsgBox(
                "Run with A_AhkPath failed:`n" err.Message "`n`n" diag,
                "v1ln clan - Launch Error",
                "Icon!"
            )
        }
    }

    ; Fallback: Windows file association
    try {
        Run '"' launcher '"'
        return
    } catch as err2 {
        MsgBox(
            "❌ Launch failed (association too).`n`n"
            . "Error:`n" err2.Message "`n`n"
            . diag,
            "v1ln clan - Launch Error",
            "Icon! 0x10"
        )
    }
}

FindMacroLauncher() {
    global APP_DIR

    p1 := APP_DIR "\MacroLauncher.ahk"
    if FileExist(p1)
        return p1

    p2 := A_ScriptDir "\MacroLauncher.ahk"
    if FileExist(p2)
        return p2

    base := A_AppData "\MacroLauncher"
    p3 := base "\MacroLauncher.ahk"
    if FileExist(p3)
        return p3

    return ""
}
RefreshBannedFromServer(lblCtrl) {
    global MANIFEST_URL, DISCORD_BAN_FILE

    tmp := A_Temp "\manifest_live.json"
    if !SafeDownload(MANIFEST_URL, tmp, 20000) {
        lblCtrl.Value := "Banned Discord IDs: (sync failed)"
        return false
    }

    try json := FileRead(tmp, "UTF-8")
    catch {
        lblCtrl.Value := "Banned Discord IDs: (sync failed)"
        return false
    }

    lists := ParseManifestLists(json)
    if !IsObject(lists) {
        lblCtrl.Value := "Banned Discord IDs: (sync failed)"
        return false
    }

    ; overwrite local file to match global
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

ResyncListsFromManifestNow() {
    global MANIFEST_URL, DISCORD_BAN_FILE, ADMIN_DISCORD_FILE
    tmp := A_Temp "\manifest_live.json"

    if !SafeDownload(MANIFEST_URL, tmp, 20000)
        throw Error("Failed to download manifest from server.")

    json := FileRead(tmp, "UTF-8")
    lists := ParseManifestLists(json)

    if !IsObject(lists)
        throw Error("Failed to parse manifest lists.")

    OverwriteListFile(DISCORD_BAN_FILE, lists.banned)
    OverwriteListFile(ADMIN_DISCORD_FILE, lists.admins)
    return lists
}
TestSync() {
    global DISCORD_BAN_FILE, ADMIN_DISCORD_FILE
    RefreshManifestAndLauncherBeforeLogin()
    MsgBox "Ban file exists: " (FileExist(DISCORD_BAN_FILE) ? "YES" : "NO")
        . "`nAdmin file exists: " (FileExist(ADMIN_DISCORD_FILE) ? "YES" : "NO")
        . "`n`nBan file path:`n" DISCORD_BAN_FILE
        . "`n`nAdmin file path:`n" ADMIN_DISCORD_FILE
}
CheckCredHashTicker() {
    global SESSION_FILE
    ; only care if someone is logged in
    if !FileExist(SESSION_FILE)
        return

    ; refresh manifest + creds
    if !RefreshManifestAndLauncherBeforeLogin()
        return

    ; now re-check session validity (will delete session if hash changed)
    if !CheckSession() {
        MsgBox "⚠️ Your session was ended because the universal password changed.", "AHK vault", "Icon! 0x30"
    }
}
