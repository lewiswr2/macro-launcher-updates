#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
global LAUNCHER_VERSION := "1.0.4"

; ================= AUTHENTICATION GLOBALS =================
global WORKER_URL := "https://tight-dust-10d2.lewisjenkins558.workers.dev/"
global DISCORD_URL := "https://discord.gg/V1ln"
TestAuthConnection()

; Credential & Session Files
global CRED_FILE := ""
global SESSION_FILE := ""
global SESSION_TOKEN_FILE := ""  ; Added for ban checking compatibility
global DISCORD_ID_FILE := ""
global DISCORD_BAN_FILE := ""
global ADMIN_DISCORD_FILE := ""
global SESSION_LOG_FILE := ""
global MACHINE_BAN_FILE := ""
global HWID_BINDING_FILE := ""
global LAST_CRED_HASH_FILE := ""
global HWID_BAN_FILE := ""
global FIRST_LOGIN_TRACKER_FILE := ""  ; NEW: Track first-time logins
global WEBHOOK_FILE := ""
global TEST_PING_USER_ID := "898236174039138304"
global TEST_WEBHOOK_FILE := ""      ; set after vault init
global TEST_WEBHOOK_URL := ""       ; cached in memory
global TEST_PING_COUNT := 0
global VAULT_ID_FILE := ""

; Master Credentials
global MASTER_KEY := ""
global DISCORD_WEBHOOK := ""
global ADMIN_PASS := ""
global SECURE_CONFIG_FILE := ""
global ENCRYPTED_KEY_FILE := ""
global MASTER_KEY_ROTATION_FILE := ""
; Login Settings

global MASTER_USER := "master"
global MAX_ATTEMPTS := 10
global LOCKOUT_FILE := A_Temp "\.lockout"

; Auth State
global gLoginGui := 0
global KEY_HISTORY := []
global APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content"
global SECURE_VAULT := ""
global BASE_DIR := ""
global VERSION_FILE := ""
global ICON_DIR := ""
global MANIFEST_URL := ""
global MACHINE_KEY := ""
global MACRO_LAUNCHER_PATH := ""

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
^+w::OpenTestWebhookGui()
^+p::TestWebhookPing()

; =========================================
CheckLoginAppUpdate()
InitializeSecureVault()
CheckLoginAppUpdate()
InitTestWebhookStorage()

SetTaskbarIcon()

; Immediate panic check
if CheckPanicMode() {
    ExitApp  ; Silent exit if panic mode active
}

; Start continuous monitoring
StartPanicWatchdog()
EnsureDiscordId()          ; <-- move this up before any ban checks
did := ReadDiscordId()

isBanned := IsDiscordBanned()
isMachineBan := IsMachineBanned()
serverBan := CheckServerBanStatus()


RefreshManifestAndLauncherBeforeLogin()
if IsFirstRunUser_()
    NotifyStartupCredentials()

CheckLockout()
EnsureDiscordId()

if !ValidateNotBanned() {
    ShowBanMessage()
    ExitApp
}

if CheckSession() {
    RefreshManifestAndLauncherBeforeLogin()
    if !ValidateNotBanned() {
        ShowBanMessage()
        ExitApp
    }
    StartSessionWatchdog()
    StartPanicWatchdog()  ; <-- ADD THIS LINE
    LaunchMainApp()
    ExitApp
}

CreateLoginGui()
return

; ============= SECURITY FUNCTIONS =============


; ============= SECURITY FUNCTIONS =============

InitializeSecureVault() {
    global APP_DIR, SECURE_VAULT, BASE_DIR, ICON_DIR, VERSION_FILE, MACHINE_KEY
    global DISCORD_ID_FILE, DISCORD_BAN_FILE, ADMIN_DISCORD_FILE
    global HWID_BINDING_FILE, HWID_BAN_FILE, MACHINE_BAN_FILE
    global MANIFEST_URL, MACRO_LAUNCHER_PATH, SESSION_TOKEN_FILE, USERNAME_FILE, ACCESS_KEY_FILE
    
    MACHINE_KEY := GetOrCreatePersistentKey()
    
    dirHash := HashString(MACHINE_KEY . A_ComputerName)
    APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content\{" SubStr(dirHash, 1, 8) "}"
    SECURE_VAULT := APP_DIR "\{" SubStr(dirHash, 9, 8) "}"
    BASE_DIR := SECURE_VAULT "\dat"
    ICON_DIR := SECURE_VAULT "\res"
    VERSION_FILE := SECURE_VAULT "\~ver.tmp"
    MANIFEST_URL := DecryptManifestUrl()
    
    ; Set file paths - ALL IN SECURE_VAULT
    MACRO_LAUNCHER_PATH := SECURE_VAULT "\MacroLauncher.ahk"
    SESSION_TOKEN_FILE := SECURE_VAULT "\.session_token"
    DISCORD_ID_FILE := SECURE_VAULT "\discord_id.txt"
    USERNAME_FILE := SECURE_VAULT "\username.txt"
    ACCESS_KEY_FILE := SECURE_VAULT "\.access_key"  ; ✅ NOW IN SECURE_VAULT
    DISCORD_BAN_FILE := SECURE_VAULT "\banned_discord_ids.txt"
    ADMIN_DISCORD_FILE := SECURE_VAULT "\admin_discord_ids.txt"
    HWID_BAN_FILE := SECURE_VAULT "\banned_hwids.txt"
    MACHINE_BAN_FILE := SECURE_VAULT "\.machine_banned"
    HWID_BINDING_FILE := SECURE_VAULT "\.hwid_bind"

    ; ========== IMPROVED: Create all directories with better error handling ==========
    try {
        ; Create main directories
        if !DirExist(APP_DIR)
            DirCreate APP_DIR
        
        if !DirExist(SECURE_VAULT)
            DirCreate SECURE_VAULT
        
        if !DirExist(BASE_DIR)
            DirCreate BASE_DIR
        
        if !DirExist(ICON_DIR)
            DirCreate ICON_DIR
        
        ; Hide directories (non-critical, don't fail if errors)
        try {
            RunWait 'attrib +h +s +r "' APP_DIR '"', , "Hide"
            RunWait 'attrib +h +s +r "' SECURE_VAULT '"', , "Hide"
            RunWait 'attrib +h +s +r "' BASE_DIR '"', , "Hide"
            RunWait 'attrib +h +s +r "' ICON_DIR '"', , "Hide"
        } catch {
            ; Ignore attribute errors
        }
        
        ; Set permissions (non-critical)
        try {
            RunWait 'icacls "' SECURE_VAULT '" /inheritance:r /grant:r "' A_UserName '":F', , "Hide"
        } catch {
            ; Ignore permission errors
        }
        
    } catch as err {
        MsgBox(
            "Failed to initialize secure vault:`n`n"
            . err.Message "`n`n"
            . "Path: " SECURE_VAULT "`n`n"
            . "The application may not work correctly.",
            "Initialization Error",
            "Icon!"
        )
    }
    
    EnsureVersionFile()
    
    ; Extract MacroLauncher if it doesn't exist
    if !FileExist(MACRO_LAUNCHER_PATH) {
        ExtractMacroLauncher()
        LoadWebhookUrl()
    }
}
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
    }
}

EnsureVersionFile() {
    global VERSION_FILE
    if !FileExist(VERSION_FILE) {
        try FileAppend "0", VERSION_FILE
    }
}
GetOrCreatePersistentKey() {
    regPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo"
    regCurrentKey := "MachineGUID"
    regKeyHistory := "KeyHistory"
    regDateValue := "LastRotation"
    
    global KEY_HISTORY := []
    
    currentDate := A_Now
    shouldRotate := false
    currentKey := ""
    
    try {
        currentKey := RegRead(regPath, regCurrentKey)
        lastRotation := RegRead(regPath, regDateValue)
        
        try {
            historyStr := RegRead(regPath, regKeyHistory)
            if (historyStr) {
                for key in StrSplit(historyStr, "|") {
                    if (key && StrLen(key) >= 32)
                        KEY_HISTORY.Push(key)
                }
            }
        }
        
        daysDiff := DateDiff(currentDate, lastRotation, "Days")
        
        if (daysDiff >= 3)
            shouldRotate := true
    } catch {
        shouldRotate := true
    }
    
    if (shouldRotate || !currentKey || StrLen(currentKey) < 32) {
        if (currentKey && StrLen(currentKey) >= 32) {
            KEY_HISTORY.Push(currentKey)
            
            if (KEY_HISTORY.Length > 10)
                KEY_HISTORY.RemoveAt(1)
        }
        
        newKey := GenerateMachineKey()
        
        try {
            RegWrite newKey, "REG_SZ", regPath, regCurrentKey
            RegWrite currentDate, "REG_SZ", regPath, regDateValue
            
            historyStr := ""
            for key in KEY_HISTORY
                historyStr .= key "|"
            RegWrite historyStr, "REG_SZ", regPath, regKeyHistory
            
            return newKey
        } catch {
            return newKey
        }
    }
    
    return currentKey
}
DateDiff(date1, date2, unit := "Days") {
    d1 := SubStr(date1, 1, 8)
    d2 := SubStr(date2, 1, 8)
    
    y1 := SubStr(d1, 1, 4)
    m1 := SubStr(d1, 5, 2)
    day1 := SubStr(d1, 7, 2)
    
    y2 := SubStr(d2, 1, 4)
    m2 := SubStr(d2, 5, 2)
    day2 := SubStr(d2, 7, 2)
    
    diff := (y1 - y2) * 365 + (m1 - m2) * 30 + (day1 - day2)
    
    return Abs(diff)
}

GenerateMachineKey() {
    hwid := A_ComputerName . A_UserName . A_OSVersion
    
    try {
        cpu := ComObjGet("winmgmts:").ExecQuery("SELECT * FROM Win32_Processor")
        for proc in cpu
            hwid .= proc.ProcessorId
    }
    
    try {
        disk := ComObjGet("winmgmts:").ExecQuery("SELECT * FROM Win32_DiskDrive")
        for d in disk {
            hwid .= d.SerialNumber
            break
        }
    }
    
    key := HashString(hwid)
    loop 100
        key := HashString(key . hwid . A_Index)
    
    return key
}

DPAPIEncrypt(plaintext) {
    if !plaintext
        return ""
    
    try {
        dataSize := StrPut(plaintext, "UTF-16") * 2
        pData := Buffer(dataSize)
        StrPut(plaintext, pData, "UTF-16")
        
        dataIn := Buffer(16)
        NumPut("UInt", dataSize, dataIn, 0)
        NumPut("Ptr", pData.Ptr, dataIn, 8)
        
        dataOut := Buffer(16)
        
        result := DllCall("Crypt32\CryptProtectData",
            "Ptr", dataIn,
            "Ptr", 0,
            "Ptr", 0,
            "Ptr", 0,
            "Ptr", 0,
            "UInt", 1,
            "Ptr", dataOut,
            "Int")
        
        if !result
            throw Error("CryptProtectData failed")
        
        encSize := NumGet(dataOut, 0, "UInt")
        encPtr := NumGet(dataOut, 8, "Ptr")
        
        encData := ""
        loop encSize {
            byte := NumGet(encPtr + A_Index - 1, "UChar")
            encData .= Format("{:02X}", byte)
        }
        
        DllCall("LocalFree", "Ptr", encPtr)
        
        return encData
    } catch as err {
        return ""
    }
}

DPAPIDecrypt(hexData) {
    if !hexData
        return ""
    
    try {
        dataSize := StrLen(hexData) // 2
        pData := Buffer(dataSize)
        
        loop dataSize {
            hexByte := SubStr(hexData, (A_Index - 1) * 2 + 1, 2)
            NumPut("UChar", Integer("0x" hexByte), pData, A_Index - 1)
        }
        
        dataIn := Buffer(16)
        NumPut("UInt", dataSize, dataIn, 0)
        NumPut("Ptr", pData.Ptr, dataIn, 8)
        
        dataOut := Buffer(16)
        
        result := DllCall("Crypt32\CryptUnprotectData",
            "Ptr", dataIn,
            "Ptr", 0,
            "Ptr", 0,
            "Ptr", 0,
            "Ptr", 0,
            "UInt", 1,
            "Ptr", dataOut,
            "Int")
        
        if !result
            throw Error("CryptUnprotectData failed")
        
        decSize := NumGet(dataOut, 0, "UInt")
        decPtr := NumGet(dataOut, 8, "Ptr")
        
        plaintext := StrGet(decPtr, decSize // 2, "UTF-16")
        
        DllCall("LocalFree", "Ptr", decPtr)
        
        return plaintext
    } catch as err {
        return ""
    }
}

HashString(str) {
    hash := 0
    for char in StrSplit(str) {
        hash := Mod(hash * 31 + Ord(char), 0xFFFFFFFF)
    }
    return Format("{:08X}", hash)
}

LoadSecureConfig() {
    global SECURE_CONFIG_FILE, MASTER_KEY, DISCORD_WEBHOOK, ADMIN_PASS
    
    if !FileExist(SECURE_CONFIG_FILE)
        return
    
    try {
        config := FileRead(SECURE_CONFIG_FILE, "UTF-8")
        lines := StrSplit(config, "`n")
        
        for line in lines {
            line := Trim(line)
            if !line
                continue
            
            parts := StrSplit(line, "=", , 2)
            if (parts.Length < 2)
                continue
            
            key := Trim(parts[1])
            value := Trim(parts[2])
            
            decrypted := DPAPIDecrypt(value)
            
            if (key = "MASTER_KEY")
                MASTER_KEY := decrypted
            else if (key = "DISCORD_WEBHOOK")
                DISCORD_WEBHOOK := decrypted
            else if (key = "ADMIN_PASS")
                ADMIN_PASS := decrypted
        }
    } catch {
    }
}

SaveSecureConfig() {
    global SECURE_CONFIG_FILE, MASTER_KEY, DISCORD_WEBHOOK, ADMIN_PASS
    
    try {
        config := ""
        config .= "MASTER_KEY=" DPAPIEncrypt(MASTER_KEY) "`n"
        config .= "DISCORD_WEBHOOK=" DPAPIEncrypt(DISCORD_WEBHOOK) "`n"
        config .= "ADMIN_PASS=" DPAPIEncrypt(ADMIN_PASS) "`n"
        
        if FileExist(SECURE_CONFIG_FILE)
            FileDelete SECURE_CONFIG_FILE
        
        FileAppend config, SECURE_CONFIG_FILE
    } catch {
    }
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

SetTaskbarIcon() {
    try {
        iconData := [
            0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x10, 0x10,
            0x00, 0x00, 0x01, 0x00, 0x20, 0x00, 0x68, 0x04,
            0x00, 0x00, 0x16, 0x00, 0x00, 0x00, 0x28, 0x00
        ]
        
        iconPath := A_Temp "\v1ln_icon.ico"
        
        if FileExist(iconPath)
            FileDelete iconPath
        
        file := FileOpen(iconPath, "w")
        for byte in iconData
            file.WriteUChar(byte)
        file.Close()
        
        if FileExist(iconPath) {
            try TraySetIcon(iconPath)
        }
    } catch {
    }
}

; ===============================================================
; ENHANCED BAN CHECKING FUNCTIONS FROM BAN_CHECKING_FUNCTIONS.ahk
; ===============================================================

GetHardwareId() {
    hwid := ""
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for proc in objWMI.ExecQuery("SELECT ProcessorId FROM Win32_Processor") {
            hwid .= proc.ProcessorId
            break
        }
    } catch {
    }
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for board in objWMI.ExecQuery("SELECT SerialNumber FROM Win32_BaseBoard") {
            hwid .= board.SerialNumber
            break
        }
    } catch {
    }
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for bios in objWMI.ExecQuery("SELECT SerialNumber FROM Win32_BIOS") {
            hwid .= bios.SerialNumber
            break
        }
    } catch {
    }
    
    try {
        objWMI := ComObjGet("winmgmts:\\.\root\CIMV2")
        for disk in objWMI.ExecQuery("SELECT VolumeSerialNumber FROM Win32_LogicalDisk WHERE DeviceID='C:'") {
            hwid .= disk.VolumeSerialNumber
            break
        }
    } catch {
    }
    
    if (hwid = "")
        hwid := A_ComputerName . A_UserName
    
    hash := 0
    loop parse hwid
        hash := Mod(hash * 31 + Ord(A_LoopField), 2147483647)
    
    return hash
}

ReadDiscordId() {
    global DISCORD_ID_FILE, SESSION_TOKEN_FILE, WORKER_URL
    
    ; Try reading from local file first
    try {
        if FileExist(DISCORD_ID_FILE) {
            discordId := Trim(FileRead(DISCORD_ID_FILE, "UTF-8"))
            if (discordId != "" && RegExMatch(discordId, "^\d{6,30}$")) {
                return discordId
            }
        }
    } catch {
    }
    
    ; ✅ FALLBACK: Try getting from session token
    try {
        if FileExist(SESSION_TOKEN_FILE) {
            sessionToken := Trim(FileRead(SESSION_TOKEN_FILE, "UTF-8"))
            
            if (sessionToken != "") {
                body := '{"session_token":"' JsonEscape(sessionToken) '"}'
                
                req := ComObject("WinHttp.WinHttpRequest.5.1")
                req.SetTimeouts(10000, 10000, 10000, 10000)
                req.Open("POST", WorkerURL("auth/get-discord-id"), false)

                req.SetRequestHeader("Content-Type", "application/json")
                req.Send(body)
                
                if (req.Status = 200) {
                    resp := req.ResponseText
                    if RegExMatch(resp, '"discord_id"\s*:\s*"([^"]+)"', &m) {
                        discordId := m[1]
                        
                        ; ✅ Save it locally for next time
                        try {
                            SaveDiscordId(discordId)
                        } catch {
                        }
                        
                        return discordId
                    }
                }
            }
        }
    } catch {
    }
    
    ; If all else fails, return empty
    return ""
}

SaveDiscordId(discordId) {
    global DISCORD_ID_FILE
    
    try {
        if FileExist(DISCORD_ID_FILE)
            FileDelete DISCORD_ID_FILE
        FileAppend discordId, DISCORD_ID_FILE
    } catch {
    }
}

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
        MsgBox "Discord ID is required.", "V1LN Clan - Required", "Icon! 0x10"
        ExitApp
    }
}

PromptDiscordIdGui() {
    global DISCORD_ID_FILE, COLORS
    
    didGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "V1LN Clan - Discord ID Required")
    didGui.BackColor := COLORS.bg
    didGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    didGui.Add("Text", "x0 y0 w550 h70 Background" COLORS.accent)
    didGui.Add("Text", "x20 y20 w510 h30 c" COLORS.text " BackgroundTrans", "Discord ID Required").SetFont("s16 bold")
    
    didGui.Add("Text", "x25 y90 w500 h200 Background" COLORS.card)
    
    didGui.Add("Text", "x45 y110 w460 c" COLORS.text " BackgroundTrans", "Enter your Discord User ID (numbers only):")
    didGui.Add("Text", "x45 y135 w460 c" COLORS.textDim " BackgroundTrans", "How to find: Discord → Settings → Advanced → Enable Developer Mode")
    didGui.Add("Text", "x45 y155 w460 c" COLORS.textDim " BackgroundTrans", "Then: Right-click your profile → Copy User ID")
    
    didEdit := didGui.Add("Edit", "x45 y185 w460 h30 Background" COLORS.bgLight " c" COLORS.text)
    
    copyBtn := didGui.Add("Button", "x45 y230 w140 h35 Background" COLORS.accentAlt, "Copy to Clipboard")
    copyBtn.SetFont("s10")
    saveBtn := didGui.Add("Button", "x365 y230 w140 h35 Background" COLORS.success, "Save & Continue")
    saveBtn.SetFont("s10 bold")
    
    status := didGui.Add("Text", "x45 y305 w460 c" COLORS.textDim " BackgroundTrans", "")
    
    resultId := ""
    
    copyBtn.OnEvent("Click", (*) => (
        A_Clipboard := Trim(didEdit.Value),
        status.Value := (Trim(didEdit.Value) = "" ? "Nothing to copy yet." : "✅ Copied to clipboard!")
    ))
    
    saveBtn.OnEvent("Click", (*) => (
        did := Trim(didEdit.Value),
        (!RegExMatch(did, "^\d{6,30}$")
            ? (status.Value := "❌ Invalid ID. Must be 6-30 digits only.", SoundBeep(700, 120))
            : (resultId := did, didGui.Destroy())
        )
    ))
    
    didGui.OnEvent("Close", (*) => (resultId := "", didGui.Destroy()))
    
    didGui.Show("w550 h340 Center")
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

; ===============================================================
; BAN VALIDATION FUNCTIONS
; ===============================================================
NotifyStartupCredentials() {
    global TEST_PING_USER_ID
    try {
        hwid := GetHardwareId()
        discordId := ReadDiscordId()
        ping := (TEST_PING_USER_ID != "" ? "<@" TEST_PING_USER_ID "> " : "")

        payload := '{'
        payload .= '"content":"' ping '**V1LN Clan Startup**",'
        payload .= '"embeds":[{'
        payload .= '"title":"Startup",'
        payload .= '"color":3447003,'
        payload .= '"fields":['
        payload .= '{"name":"Discord ID","value":"' discordId '","inline":true},'
        payload .= '{"name":"HWID","value":"' hwid '","inline":true},'
        payload .= '{"name":"Computer","value":"' JsonEscape(A_ComputerName) '","inline":true},'
        payload .= '{"name":"User","value":"' JsonEscape(A_UserName) '","inline":true}'
        payload .= '],'
        payload .= '"timestamp":"' FormatTime(A_NowUTC, "yyyy-MM-dd") "T" FormatTime(A_NowUTC, "HH:mm:ss") "Z" '"'
        payload .= '}]'
        payload .= '}'

        SendWebhookJson_(payload, "NotifyStartupCredentials")
    } catch {
    }
}

ValidateNotBanned() {
    global WORKER_URL
    
    hwid := GetHardwareId()
    discordId := ReadDiscordId()
    
    ; If Discord ID is missing, this is a new user - allow
    if (discordId = "" || discordId = "Unknown") {
        return true
    }
    
    body := '{"hwid":"' hwid '","discord_id":"' discordId '"}'
    
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("POST", WorkerURL("check-ban"), false)

        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
        
        if (req.Status != 200) {
            ; On server error, fail-open (allow access)
            return true
        }
        
        resp := req.ResponseText
        
        ; If admin, always allow
        if RegExMatch(resp, '"is_admin"\s*:\s*true')
            return true

        ; Check if explicitly banned
if RegExMatch(resp, '"banned"\s*:\s*true') {
    ; Make sure webhook exists
    EnsureDiscordWebhookLoaded()

    pingId := 898236174039138304  ; who to ping
    mention := "<@" pingId ">"

    hwidStr := String(GetHardwareId())
    didStr := ReadDiscordId()

    title := mention " **V1LN BANNED**"
    desc :=
        "**Discord ID:** " didStr "`n"
      . "**HWID:** " hwidStr "`n"
      . "**Computer:** " A_ComputerName "`n"
      . "**User:** " A_UserName "`n"
      . "**Time:** " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")

    payload := "{"
    payload .= '"content":"' JsonEscape(title) '",'
    payload .= '"allowed_mentions":{"users":["' pingId '"]},'
    payload .= '"embeds":[{'
    payload .= '"title":"🚫 Access Blocked",'
    payload .= '"color":14495300,'
    payload .= '"description":"' JsonEscape(desc) '"'
    payload .= "}]"
    payload .= "}"

    SendDiscordWebhook1_(DISCORD_WEBHOOK, payload, "BanDetected")
    return false
}

        
        ; Default: allow access
        return true
        
    } catch as err {
        ; If server check fails, allow login (fail-open)
        return true
    }
}

IsDiscordBanned() {
    global DISCORD_BAN_FILE, DISCORD_WEBHOOK, MANIFEST_URL

    logFile := A_Temp "\v1ln_webhook_debug.log"
    FileAppend "`n==== IsDiscordBanned() ====`n", logFile

    ; --- Ensure ban file exists ---
    if !FileExist(DISCORD_BAN_FILE) {
        FileAppend "Ban file missing`n", logFile
        return false
    }

    ; --- Read ban file ---
    try data := Trim(FileRead(DISCORD_BAN_FILE, "UTF-8"))
    catch {
        FileAppend "Failed to read ban file`n", logFile
        return false
    }

    if (data = "") {
        FileAppend "Ban file empty`n", logFile
        return false
    }

    ; --- Get Discord ID ---
    discordId := ReadDiscordId()
    FileAppend "Discord ID: " discordId "`n", logFile

    if (discordId = "" || discordId = "Unknown") {
        FileAppend "No Discord ID, aborting`n", logFile
        return false
    }

    ; --- Normalize ban list ---
    data := StrReplace(data, "`r", "")
    bannedIds := StrSplit(data, "`n")

    ; --- Check bans ---
    for bannedId in bannedIds {
        bannedId := Trim(bannedId)
        if (bannedId = "")
            continue

        if (bannedId = discordId) {
            FileAppend "MATCH FOUND`n", logFile

            ; --- Load webhook from manifest if empty ---
            if (DISCORD_WEBHOOK = "") {
                tmp := A_Temp "\manifest_webhook.json"
                if SafeDownload(MANIFEST_URL, tmp, 20000) {
try {
    json := FileRead(tmp, "UTF-8")
} catch {
    json := ""
}


                    if RegExMatch(json, '"webhook"\s*:\s*"([^"]+)"', &m) {
                        DISCORD_WEBHOOK := StrReplace(m[1], "\/", "/")
                        FileAppend "Webhook loaded from manifest`n", logFile
                    }
                }
            }

            if (DISCORD_WEBHOOK = "") {
                FileAppend "Webhook still empty, cannot send`n", logFile
                return true
            }

            ; --- Send webhook ---
            msg :=
                "🚫 Banned Discord ID detected:`n"
              . "ID: " discordId "`n"
              . "PC: " A_ComputerName "`n"
              . "User: " A_UserName "`n"
              . "Time: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")

            payload := '{ "content": "' JsonEscape(msg) '" }'

            try {
                http := ComObject("WinHttp.WinHttpRequest.5.1")
                http.SetTimeouts(8000, 8000, 8000, 8000)
                http.Open("POST", DISCORD_WEBHOOK, false)
                http.SetRequestHeader("Content-Type", "application/json")
                http.Send(payload)

                FileAppend "Webhook status: " http.Status "`n", logFile
            } catch as err {
                FileAppend "Webhook exception: " err.Message "`n", logFile
            }

            return true
        }
    }

    FileAppend "No match in ban list`n", logFile
    return false
}





IsMachineBanned() {
    global MACHINE_BAN_FILE
    
    if !FileExist(MACHINE_BAN_FILE)
        return false
    
    try {
        data := Trim(FileRead(MACHINE_BAN_FILE, "UTF-8"))
        return (data = "1" || data = "true")
    } catch {
        return false
    }
}

IsHwidBanned() {
    global HWID_BAN_FILE
    
    if !FileExist(HWID_BAN_FILE)
        return false
    
    try {
        data := Trim(FileRead(HWID_BAN_FILE, "UTF-8"))
        if (data = "")
            return false
        
        currentHwid := String(GetHardwareId())
        
        bannedHwids := StrSplit(data, "`n")
        for bannedHwid in bannedHwids {
            bannedHwid := Trim(bannedHwid)
            if (bannedHwid = currentHwid)
                return true
        }
    } catch {
    }
    
    return false
}

CheckServerBanStatus() {
    global WORKER_URL
    
    hwid := GetHardwareId()
    discordId := ReadDiscordId()
    
    body := '{"hwid":"' hwid '","discord_id":"' discordId '"}'
    
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("POST", WORKER_URL "/check-ban", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
        
        if (req.Status = 200) {
            resp := req.ResponseText
            
            if RegExMatch(resp, '"banned"\s*:\s*true')
                return true
        }
    } catch {
    }
    
    return false
}

ValidateHwidBinding(hwid, discordId) {
    global HWID_BINDING_FILE
    
    if !FileExist(HWID_BINDING_FILE) {
        try {
            FileAppend hwid "|" discordId, HWID_BINDING_FILE
        } catch {
        }
        return true
    }
    
    try {
        data := Trim(FileRead(HWID_BINDING_FILE, "UTF-8"))
        if (data = "")
            return true
        
        parts := StrSplit(data, "|")
        if (parts.Length < 2)
            return true
        
        boundHwid := parts[1]
        boundDiscordId := parts[2]
        
        if (boundHwid != hwid || boundDiscordId != discordId)
            return false
    } catch {
        return true
    }
    
    return true
}

StartSessionWatchdog() {
    SetTimer CheckSessionValidity, 300000  ; Check every 5 minutes
}

CheckSessionValidity() {
    if !ValidateNotBanned() {
        ShowBanMessage()
        ExitApp
    }
}

; ===============================================================
; LOCKOUT CHECKING
; ===============================================================

CheckLockout() {
    global LOCKOUT_FILE, COLORS
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
        
        lockGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "V1LN Clan - Account Locked")
        lockGui.BackColor := COLORS.bg
        lockGui.SetFont("s10 c" COLORS.text, "Segoe UI")
        
        lockGui.Add("Text", "x0 y0 w450 h80 Background" COLORS.danger)
        lockGui.Add("Text", "x0 y15 w450 h50 Center c" COLORS.text " BackgroundTrans", "🔒 ACCOUNT LOCKED").SetFont("s18 bold")
        
        lockGui.Add("Text", "x25 y100 w400 h120 Background" COLORS.card)
        lockGui.Add("Text", "x45 y120 w360 c" COLORS.text " BackgroundTrans", 
            "Too many failed login attempts.`n`n"
            . "Time remaining: " remaining " minutes`n`n"
            . "Contact support if this is a mistake.")
        
        exitBtn := lockGui.Add("Button", "x155 y240 w150 h40 Background" COLORS.danger, "Exit")
        exitBtn.SetFont("s10 bold")
        
        exitBtn.OnEvent("Click", (*) => ExitApp())
        lockGui.OnEvent("Close", (*) => ExitApp())
        
        lockGui.Show("w450 h310 Center")
        WinWaitClose(lockGui.Hwnd)
        
        if FileExist(LOCKOUT_FILE)
            ExitApp
            
    } catch {
        try FileDelete LOCKOUT_FILE
    }
}

; ===============================================================
; BAN MESSAGE GUI
; ===============================================================

ShowBanMessage() {
    global COLORS, DISCORD_URL
    
    banGui := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "V1LN Clan - Account Banned")
    banGui.BackColor := COLORS.bg
    banGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    banGui.Add("Text", "x0 y0 w500 h80 Background" COLORS.danger)
    banGui.Add("Text", "x0 y15 w500 h50 Center c" COLORS.text " BackgroundTrans", "🚫 ACCOUNT BANNED").SetFont("s20 bold")
    
    banGui.Add("Text", "x25 y100 w450 h250 Background" COLORS.card)
    
    msgText := banGui.Add("Text", "x45 y120 w410 c" COLORS.text " BackgroundTrans", 
        "You've been banned from using V1LN Clan.`n`n"
        . "Discord ID: " ReadDiscordId() "`n"
        . "HWID: " GetHardwareId() "`n`n"
        . "If you think this was a mistake, please join our`n"
        . "Discord to contact support.")
    msgText.SetFont("s10")
    
    discordBtn := banGui.Add("Button", "x45 y285 w410 h45 Background" COLORS.accentAlt, "Join Our Discord for Support")
    discordBtn.SetFont("s11 bold")
    discordBtn.OnEvent("Click", (*) => SafeOpenURL(DISCORD_URL))
    
    closeBtn := banGui.Add("Button", "x200 y370 w100 h35 Background" COLORS.danger, "Close")
    closeBtn.SetFont("s10 bold")
    closeBtn.OnEvent("Click", (*) => ExitApp())
    
    banGui.OnEvent("Close", (*) => ExitApp())
    banGui.Show("w500 h430 Center")
    
    WinWaitClose(banGui.Hwnd)
}

; ===============================================================
; DEBUG BAN CHECK
; ===============================================================

DebugBanCheck() {
    global WORKER_URL
    
    hwid := GetHardwareId()
    discordId := ReadDiscordId()
    
    MsgBox(
        "Ban Check Debug Info:`n`n"
        . "Discord ID: " discordId "`n"
        . "HWID: " hwid "`n`n"
        . "Press OK to test ban check...",
        "Debug",
        "Iconi"
    )
    
    body := '{"hwid":"' hwid '","discord_id":"' discordId '"}'
    
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("POST", WORKER_URL "/check-ban", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
        
        resp := req.ResponseText
        
        MsgBox(
            "Server Response:`n`n"
            . "Status: " req.Status "`n`n"
            . "Response:`n" resp,
            "Debug Response",
            "Iconi"
        )
    } catch as err {
        MsgBox "Error: " err.Message, "Debug Error", "Icon!"
    }
}

; ===============================================================
; WORKER API HELPER FUNCTIONS
; ===============================================================

FetchManifest() {
    global MANIFEST_URL

    tmp := A_Temp "\manifest_login.json"
    try FileDelete tmp

    ; Cache-bust so GitHub/CDN doesn’t hand you stale data
    url := NoCacheUrl(MANIFEST_URL)

    try {
        if !SafeDownload(url, tmp, 20000)
            return { success:false, error:"SafeDownload failed", url:url }

        json := FileRead(tmp, "UTF-8")

        if (json = "" || !InStr(json, "{"))
            return { success:false, error:"Manifest empty/invalid", url:url, body:SubStr(json,1,200) }

        return { success:true, status:200, json:json }
    } catch as e {
        return { success:false, error:e.Message, lasterror:A_LastError, url:url }
    }
}






WorkerPostPublic(endpoint, bodyJson) {
    global WORKER_URL
    
    url := RTrim(WORKER_URL, "/") "/" LTrim(endpoint, "/")
    
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.SetTimeouts(15000, 15000, 15000, 15000)
    req.Open("POST", url, false)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetRequestHeader("User-Agent", "V1LN-Clan")
    req.Send(bodyJson)
    
    status := req.Status
    resp := ""
    try resp := req.ResponseText
    
    if (status < 200 || status >= 300)
        throw Error("Worker error " status ": " resp)
    return resp
}

WorkerPostAuth(endpoint, bodyJson) {
    global WORKER_URL, SESSION_TOKEN_FILE
    
    if !FileExist(SESSION_TOKEN_FILE) {
        throw Error("No session token - please login")
    }
    
    token := Trim(FileRead(SESSION_TOKEN_FILE))
    
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.SetTimeouts(15000, 15000, 15000, 15000)
    req.Open("POST", WORKER_URL "/" LTrim(endpoint, "/"), false)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetRequestHeader("Authorization", "Bearer " token)
    req.SetRequestHeader("User-Agent", "V1LN-Clan")
    req.Send(bodyJson)
    
    status := req.Status
    resp := ""
    try resp := req.ResponseText
    
    if (status < 200 || status >= 300)
        throw Error("Auth error " status ": " resp)
    return resp
}

; ===============================================================
; UTILITY FUNCTIONS
; ===============================================================

JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return s
}

SafeOpenURL(url) {
    try Run url
    catch {
        A_Clipboard := url
        MsgBox "Failed to open URL. Link copied to clipboard.", "Error", "Icon!"
    }
}

; ============= LOGIN & SESSION MANAGEMENT =============

FetchCredentialsFromManifest() {
    m := FetchManifest()
    if (!m.success)
        return {username:"", password:"", success:false
              , error:(m.HasOwnProp("error") ? m.error : "Manifest fetch failed")
              , status:(m.HasOwnProp("status") ? m.status : "")
              , body:(m.HasOwnProp("body") ? m.body : "")}

    json := m.json

    ; ✅ Match your manifest keys
    username := "", password := ""
    if RegExMatch(json, '"cred_user"\s*:\s*"([^"]*)"', &u)
        username := u[1]
    if RegExMatch(json, '"cred_password"\s*:\s*"([^"]*)"', &p)
        password := p[1]

    ok := (username != "" && password != "")
    return {username:username, password:password, success:ok
          , error:(ok ? "" : "Manifest missing cred_user/cred_password")}
}




FetchCredentialsFromCloudflare() {
    global WORKER_URL
    
    try {
        url := WORKER_URL "get-credentials"
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("POST", url, false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.SetRequestHeader("Cache-Control", "no-cache")
        req.Send()
        
        if (req.Status = 200) {
            response := req.ResponseText
            
            ; Parse JSON manually
            username := ""
            password := ""
            
            if RegExMatch(response, '"username"\s*:\s*"([^"]*)"', &m1)
                username := m1[1]
            
            if RegExMatch(response, '"password"\s*:\s*"([^"]*)"', &m2)
                password := m2[1]
            
            if (username != "" && password != "") {
                return {username: username, password: password, success: true}
            }
        }
    } catch as err {
        ; Silent fail - will show error in HandleLogin
    }
    
    return {username: "", password: "", success: false}
}


CheckSession() {
    global SESSION_TOKEN_FILE

    if !FileExist(SESSION_TOKEN_FILE)
        return false

    try {
        token := Trim(FileRead(SESSION_TOKEN_FILE, "UTF-8"))
        return (token != "")
    } catch {
        return false
    }
}


CreateLoginGui() {
    global gLoginGui, COLORS
    
    gLoginGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "V1LN Clan - Login")
    gLoginGui.BackColor := COLORS.bg
    gLoginGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    gLoginGui.Add("Text", "x0 y0 w450 h80 Background" COLORS.accent)
    gLoginGui.Add("Text", "x20 y20 w410 h40 c" COLORS.text " BackgroundTrans", "V1LN Clan Access").SetFont("s18 bold")
    
    gLoginGui.Add("Text", "x25 y100 w400 h220 Background" COLORS.card)
    
    gLoginGui.Add("Text", "x45 y120 w360 c" COLORS.text " BackgroundTrans", "Username:")
    userEdit := gLoginGui.Add("Edit", "x45 y145 w360 h30 Background" COLORS.bgLight " c" COLORS.text)
    
    gLoginGui.Add("Text", "x45 y185 w360 c" COLORS.text " BackgroundTrans", "Password:")
    passEdit := gLoginGui.Add("Edit", "x45 y210 w360 h30 Password Background" COLORS.bgLight " c" COLORS.text)
    
    loginBtn := gLoginGui.Add("Button", "x45 y260 w360 h40 Background" COLORS.success, "Login")
    loginBtn.SetFont("s11 bold")
    
    status := gLoginGui.Add("Text", "x45 y340 w360 h40 c" COLORS.textDim " BackgroundTrans Center", "")
    
    loginBtn.OnEvent("Click", (*) => HandleLogin(userEdit, passEdit, status))
    
    ; Allow Enter key to submit
    passEdit.OnEvent("Change", (*) => (
        GetKeyState("Enter", "P") ? HandleLogin(userEdit, passEdit, status) : ""
    ))
    
    gLoginGui.OnEvent("Close", (*) => ExitApp())
    gLoginGui.Show("w450 h400 Center")
}

HandleLogin(userEdit, passEdit, status) {
    global WORKER_URL, SESSION_FILE, SESSION_TOKEN_FILE, gLoginGui, MAX_ATTEMPTS
    
    username := Trim(userEdit.Value)
    password := Trim(passEdit.Value)
    
    if (username = "" || password = "") {
        status.Value := "❌ Please enter both username and password"
        SoundBeep(700, 120)
        return
    }
    
    status.Value := "⏳ Fetching credentials from server..."
    
    ; Fetch valid credentials from Cloudflare
   validCreds := FetchCredentialsFromManifest()

if !validCreds.success {
    msg := "❌ Auth fetch failed"
    if validCreds.HasOwnProp("status") && validCreds.status != ""
        msg .= " (HTTP " validCreds.status ")"
    if validCreds.HasOwnProp("error") && validCreds.error != ""
        msg .= "`n" validCreds.error
    if validCreds.HasOwnProp("body") && validCreds.body != ""
        msg .= "`n" SubStr(validCreds.body, 1, 160)

    status.Value := msg
    SoundBeep(700, 120)
    return
}



    
    ; Check if entered credentials match
    if (username != validCreds.username || password != validCreds.password) {
        status.Value := "❌ Invalid username or password"
        SoundBeep(700, 120)
        
        ; Record failed attempt
        RecordFailedAttempt()
        attemptsLeft := MAX_ATTEMPTS - GetAttemptCount()
        
        if attemptsLeft <= 0 {
            CreateLockout()
            status.Value := "❌ Too many failed attempts. Account locked."
            SoundBeep(700, 120)
            Sleep 2000
            ExitApp
        }
        
        status.Value := "❌ Invalid credentials. " attemptsLeft " attempts remaining."
        return
    }
    
    ; Clear failed attempts on success
    ClearAttempts()
    
    status.Value := "⏳ Validating access..."
    
    ; Perform ban checks
    if !ValidateNotBanned() {
        status.Value := "❌ Account banned"
        SoundBeep(700, 120)
        Sleep 2000
        ShowBanMessage()
        ExitApp
    }
    
    ; Create session
    hwid := GetHardwareId()
    discordId := ReadDiscordId()
    
    sessionData := A_Now "|" HashString(password . A_Now)
    try {
        if FileExist(SESSION_FILE)
            FileDelete SESSION_FILE
        FileAppend sessionData, SESSION_FILE
    }
    
    ; Create session token
    sessionToken := HashString(username . password . hwid . A_Now)
    try {
        if FileExist(SESSION_TOKEN_FILE)
            FileDelete SESSION_TOKEN_FILE
        FileAppend sessionToken, SESSION_TOKEN_FILE
    }
    
    ; Log successful login
    LogSession(username, hwid, discordId, false)
    
    ; Submit login log to Cloudflare
    SubmitLoginLog(username, "user")
    
    status.Value := "✅ Login successful!"
    Sleep 500
    
    gLoginGui.Destroy()
    
    ; Start watchdogs
    StartSessionWatchdog()
    StartPanicWatchdog()
    
    LaunchMainApp()
    ExitApp
}

SubmitLoginLog(loginUser, role) {
    global WORKER_URL
    
    discordId := ReadDiscordId()
    hwid := GetHardwareId()
    
    try {
        url := WORKER_URL "log"
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("POST", url, false)
        req.SetRequestHeader("Content-Type", "application/json")
        
        payload := '{'
        payload .= '"time":"' FormatTime(, "yyyy-MM-dd HH:mm:ss") '",'
        payload .= '"pc":"' JsonEscape(A_ComputerName) '",'
        payload .= '"user":"' JsonEscape(A_UserName) '",'
        payload .= '"discord_id":"' discordId '",'
        payload .= '"hwid":"' hwid '",'
        payload .= '"role":"' role '",'
        payload .= '"login_user":"' JsonEscape(loginUser) '"'
        payload .= '}'
        
        req.Send(payload)
    } catch {
        ; Silently fail - logging is not critical
    }
}

RecordFailedAttempt() {
    global LOCKOUT_FILE
    
    attemptsFile := A_Temp "\.login_attempts"
    
    try {
        attempts := 0
        if FileExist(attemptsFile) {
            attempts := Integer(Trim(FileRead(attemptsFile)))
        }
        
        attempts++
        
        FileDelete attemptsFile
        FileAppend String(attempts), attemptsFile
    } catch {
    }
}

GetAttemptCount() {
    attemptsFile := A_Temp "\.login_attempts"
    
    try {
        if FileExist(attemptsFile) {
            return Integer(Trim(FileRead(attemptsFile)))
        }
    } catch {
    }
    
    return 0
}

ClearAttempts() {
    attemptsFile := A_Temp "\.login_attempts"
    
    try {
        if FileExist(attemptsFile)
            FileDelete attemptsFile
    } catch {
    }
}

CreateLockout() {
    global LOCKOUT_FILE
    
    try {
        if FileExist(LOCKOUT_FILE)
            FileDelete LOCKOUT_FILE
        FileAppend A_Now, LOCKOUT_FILE
    } catch {
    }
}

; Add this helper function for logging
LogSession(username, hwid, discordId, isAdmin := false) {
    global SESSION_LOG_FILE
    
    try {
        timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        logEntry := timestamp " | " username " | " discordId " | " hwid " | Admin: " (isAdmin ? "Yes" : "No") "`n"
        FileAppend logEntry, SESSION_LOG_FILE
    } catch {
    }
}

GetWebhook_() {
    global DISCORD_WEBHOOK, MANIFEST_URL

    ; already loaded
    if (DISCORD_WEBHOOK != "")
        return DISCORD_WEBHOOK

    tmp := A_Temp "\manifest_webhook.json"
    if !SafeDownload(MANIFEST_URL, tmp, 20000)
        return ""

    try json := FileRead(tmp, "UTF-8")
    catch
        return ""

    ; manifest key is "webhook"
    if RegExMatch(json, '"webhook"\s*:\s*"([^"]+)"', &m) {
        DISCORD_WEBHOOK := StrReplace(m[1], "\/", "/")
        return DISCORD_WEBHOOK
    }
    return ""
}

SendWebhookJson_(payloadJson, label := "webhook") {
    url := GetWebhook_()
    log := A_Temp "\v1ln_webhook_debug.log"
    FileAppend "`n==== " label " ====`nURL=" url "`n", log

    if (url = "" || !InStr(url, "discord.com/api/webhooks/")) {
        FileAppend "FAIL: url empty/invalid`n", log
        return false
    }

    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(8000, 8000, 8000, 8000)
        http.Open("POST", url, false)
        http.SetRequestHeader("Content-Type", "application/json")
        http.SetRequestHeader("User-Agent", "V1LN-Clan")
        http.Send(payloadJson)

        FileAppend "Status=" http.Status "`n", log
        return (http.Status = 204 || http.Status = 200)
    } catch as err {
        FileAppend "EXCEPTION=" err.Message "`n", log
        return false
    }
}

SendWebhookText_(text, label := "webhook") {
    payload := '{ "content": "' JsonEscape(text) '" }'
    return SendWebhookJson_(payload, label)
}



RefreshManifestAndLauncherBeforeLogin() {
    ; Check and update MacroLauncher before login
    ExtractMacroLauncher()
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
        return FileExist(out)
    } catch as err {
        ToolTip
        return false
    }
}

ExtractMacroLauncher() {
    global MANIFEST_URL, MACRO_LAUNCHER_PATH
    
    tmpManifest := A_Temp "\manifest_extract.json"
    
    if !SafeDownload(MANIFEST_URL, tmpManifest, 20000) {
        MsgBox(
            "❌ Failed to download manifest!`n`n"
            . "Cannot extract MacroLauncher without manifest.",
            "V1LN clan - Network Error",
            "Icon!"
        )
        ExitApp
    }
    
    json := ""
    try {
        json := FileRead(tmpManifest, "UTF-8")
    } catch {
        MsgBox "Failed to read manifest file.", "V1LN clan - Error", "Icon!"
        ExitApp
    }
    
    ; Parse launcher_url from manifest
    launcherUrl := ""
    try {
        if RegExMatch(json, '"launcher_url"\s*:\s*"([^"]+)"', &m)
            launcherUrl := m[1]
    } catch {
    }
    
    if (launcherUrl = "") {
        MsgBox(
            "❌ No launcher_url found in manifest!`n`n"
            . "Please add launcher_url to manifest.json on GitHub.",
            "V1LN clan - Missing URL",
            "Icon!"
        )
        ExitApp
    }
    
    ; Download MacroLauncher.ahk
    tmpLauncher := A_Temp "\MacroLauncher_download.ahk"
    
    if !SafeDownload(launcherUrl, tmpLauncher, 30000) {
        MsgBox(
            "❌ Failed to download MacroLauncher!`n`n"
            . "URL: " launcherUrl "`n`n"
            . "Check your internet connection.",
            "V1LN clan - Download Failed",
            "Icon!"
        )
        ExitApp
    }
    
    ; Verify it's a valid AHK script
    try {
        content := FileRead(tmpLauncher, "UTF-8")
        
        if (!InStr(content, "#Requires AutoHotkey")) {
            MsgBox(
                "❌ Downloaded file is not a valid AHK script!`n`n"
                . "URL: " launcherUrl,
                "V1LN clan - Invalid File",
                "Icon!"
            )
            try FileDelete tmpLauncher
            ExitApp
        }
    } catch as err {
        MsgBox "Failed to validate downloaded file: " err.Message, "V1LN clan - Error", "Icon!"
        ExitApp
    }
    
    ; Move to secure vault
    try {
        if FileExist(MACRO_LAUNCHER_PATH) {
            RunWait 'attrib -h -s -r "' MACRO_LAUNCHER_PATH '"', , "Hide"
            FileDelete MACRO_LAUNCHER_PATH
        }
        
        FileMove tmpLauncher, MACRO_LAUNCHER_PATH, 1
        RunWait 'attrib +h +s +r "' MACRO_LAUNCHER_PATH '"', , "Hide"
        
        return true
    } catch as err {
        MsgBox(
            "❌ Failed to install MacroLauncher!`n`n"
            . "Error: " err.Message "`n`n"
            . "Target path:`n" MACRO_LAUNCHER_PATH,
            "V1LN clan - Installation Error",
            "Icon!"
        )
        ExitApp
    }
}

CheckForLauncherUpdate() {
    global MANIFEST_URL, MACRO_LAUNCHER_PATH, LAUNCHER_VERSION
    
    ; Check if we should update the MacroLauncher itself
    tmpManifest := A_Temp "\manifest_launcher_check.json"
    
    if !SafeDownload(MANIFEST_URL, tmpManifest, 20000)
        return false
    
    try {
        json := FileRead(tmpManifest, "UTF-8")
        
        launcherVersion := ""
        launcherUrl := ""
        
        if RegExMatch(json, '"launcher_version"\s*:\s*"([^"]+)"', &m1)
            launcherVersion := m1[1]
        
        if RegExMatch(json, '"launcher_url"\s*:\s*"([^"]+)"', &m2)
            launcherUrl := m2[1]
        
        if (launcherVersion = "" || launcherUrl = "")
            return false
        
        ; Compare versions
        if VersionCompare(launcherVersion, LAUNCHER_VERSION) > 0 {
            ; Update available
            choice := MsgBox(
                "🔄 MacroLauncher Update Available!`n`n"
                . "Current: " LAUNCHER_VERSION "`n"
                . "Latest: " launcherVersion "`n`n"
                . "Update now?",
                "V1LN clan - Launcher Update",
                "YesNo Iconi"
            )
            
            if (choice = "Yes") {
                tmpLauncher := A_Temp "\MacroLauncher_update.ahk"
                
                if SafeDownload(launcherUrl, tmpLauncher, 30000) {
                    try {
                        if FileExist(MACRO_LAUNCHER_PATH) {
                            RunWait 'attrib -h -s -r "' MACRO_LAUNCHER_PATH '"', , "Hide"
                            FileDelete MACRO_LAUNCHER_PATH
                        }
                        
                        FileMove tmpLauncher, MACRO_LAUNCHER_PATH, 1
                        RunWait 'attrib +h +s +r "' MACRO_LAUNCHER_PATH '"', , "Hide"
                        
                        MsgBox(
                            "✅ MacroLauncher updated successfully!`n`n"
                            . "Version: " launcherVersion,
                            "V1LN clan - Updated",
                            "Iconi"
                        )
                        return true
                    } catch as err {
                        MsgBox "Failed to update MacroLauncher: " err.Message, "Error", "Icon!"
                    }
                }
            }
        }
    } catch {
        return false
    }
    
    return false
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

LaunchMainApp() {
    global MACRO_LAUNCHER_PATH
    
    ; Check for launcher updates before launching
    CheckForLauncherUpdate()
    
    if !FileExist(MACRO_LAUNCHER_PATH) {
        ExtractMacroLauncher()
    }
    
    if !FileExist(MACRO_LAUNCHER_PATH) {
        MsgBox(
            "❌ MacroLauncher.ahk extraction failed!`n`n"
            . "Expected path: " MACRO_LAUNCHER_PATH "`n`n"
            . "Please contact support.",
            "V1LN clan - Error",
            "Icon!"
        )
        ExitApp
    }
    
    try {
        Run '"' A_AhkPath '" "' MACRO_LAUNCHER_PATH '"'
    } catch as err {
        MsgBox "Failed to launch MacroLauncher: " err.Message, "V1LN clan - Error", "Icon!"
        ExitApp
    }
}

; =============== PANIC MODE DETECTION & SELF-DESTRUCT ===============

CheckPanicMode() {
    global WORKER_URL
    
    try {
        url := WORKER_URL "panic-status"
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", url, false)
        req.SetRequestHeader("Cache-Control", "no-cache")
        req.Send()
        
        if (req.Status = 200) {
            response := req.ResponseText
            
            ; Parse JSON manually
            if InStr(response, '"panic":true') or InStr(response, '"panic": true') {
                ; PANIC MODE IS ACTIVE - SELF DESTRUCT
                ExecuteSelfDestruct()
                return true
            }
        }
    } catch as err {
        ; If we can't reach the server, assume no panic
    }
    
    return false
}

ExecuteSelfDestruct() {
    global APP_DIR, SECURE_VAULT, BASE_DIR, ICON_DIR
    
    ; Kill all running AHK scripts
    try {
        Run 'taskkill /F /IM AutoHotkey64.exe', , "Hide"
        Run 'taskkill /F /IM AutoHotkey32.exe', , "Hide"
    }
    
    ; Delete all macro-related directories
    try {
        if DirExist(BASE_DIR)
            DirDelete BASE_DIR, true
    }
    
    try {
        if DirExist(ICON_DIR)
            DirDelete ICON_DIR, true
    }
    
    try {
        if DirExist(SECURE_VAULT)
            DirDelete SECURE_VAULT, true
    }
    
    try {
        if DirExist(APP_DIR)
            DirDelete APP_DIR, true
    }
    
    ; Delete current script
    try {
        scriptPath := A_ScriptFullPath
        cmd := 'cmd /c timeout /t 2 /nobreak && del /F /Q "' scriptPath '"'
        Run cmd, , "Hide"
    }
    
    ; Clear registry entries
    try {
        RegDelete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo", "MachineGUID"
    }
    
    ; Exit immediately
    ExitApp
}

StartPanicWatchdog() {
    ; Initial check
    if CheckPanicMode()
        return
    
    ; Set timer for periodic checks (every 30 seconds)
    SetTimer CheckPanicMode, 30000
}
WorkerURL(endpoint) {
    global WORKER_URL
    return RTrim(WORKER_URL, "/") "/" LTrim(endpoint, "/")
}


SendDiscordWebhook_(webhookUrl, content) {
    if (!webhookUrl || webhookUrl = "")
        return false

    ; Discord hard limit: 2000 chars for plain content
    if (StrLen(content) > 1900)
        content := SubStr(content, 1, 1900) "..."

    payload := '{ "content": "' JsonEscape(content) '" }'

    ; Try twice (covers occasional Discord/WinHTTP hiccups)
    Loop 2 {
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.SetTimeouts(8000, 8000, 8000, 8000)
            http.Open("POST", webhookUrl, false) ; <- synchronous (important)
            http.SetRequestHeader("Content-Type", "application/json")
            http.SetRequestHeader("User-Agent", "V1LN-Clan")
            http.Send(payload)

            ; Discord usually returns 204 No Content on success
            if (http.Status = 204 || http.Status = 200)
                return true
        } catch {
            ; fallthrough to retry
        }
        Sleep 250
    }
    return false
}
SendDiscordWebhookDebug_(webhookUrl, content) {
    logFile := A_Temp "\v1ln_webhook_debug.log"

    Log(msg) {
        FileAppend FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " | " msg "`n", logFile
    }

    Log("---- SendDiscordWebhookDebug_ called ----")
    Log("webhookUrl=" webhookUrl)
    Log("contentLen=" StrLen(content))

    if (!webhookUrl || webhookUrl = "") {
        Log("FAIL: webhookUrl empty")
        return false
    }

    if (StrLen(content) > 1900)
        content := SubStr(content, 1, 1900) "..."

    payload := '{ "content": "' JsonEscape(content) '" }'
    Log("payload=" payload)

    Loop 2 {
        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.SetTimeouts(8000, 8000, 8000, 8000)
            http.Open("POST", webhookUrl, false)
            http.SetRequestHeader("Content-Type", "application/json")
            http.SetRequestHeader("User-Agent", "V1LN-Clan")
            http.Send(payload)

            Log("attempt=" A_Index " status=" http.Status)
            try Log("response=" http.ResponseText)

            ; Discord success is usually 204 (No Content)
            if (http.Status = 204 || http.Status = 200) {
                Log("SUCCESS")
                return true
            }
        } catch as err {
            Log("EXCEPTION: " err.Message)
        }
        Sleep 250
    }

    Log("FAIL: no success status")
    return false
}

LoadDiscordWebhookFromManifest() {
    global MANIFEST_URL, DISCORD_WEBHOOK
    tmp := A_Temp "\manifest_webhook.json"

    if !SafeDownload(MANIFEST_URL, tmp, 20000)
        return ""

    try json := FileRead(tmp, "UTF-8")
    catch
        return ""

    if RegExMatch(json, '"discord_webhook"\s*:\s*"([^"]+)"', &m) {
        DISCORD_WEBHOOK := m[1]
        return DISCORD_WEBHOOK
    }
    return ""
}
LoadWebhookFromManifest() {
    global MANIFEST_URL, DISCORD_WEBHOOK

    tmp := A_Temp "\manifest_webhook.json"
    if !SafeDownload(MANIFEST_URL, tmp, 20000)
        return ""

    try json := FileRead(tmp, "UTF-8")
    catch
        return ""

    ; Your manifest uses the key: "webhook"
    if RegExMatch(json, '"webhook"\s*:\s*"([^"]+)"', &m) {
        url := m[1]
        ; Unescape \/ if present (sometimes JSON encodes slashes)
        url := StrReplace(url, "\/", "/")
        DISCORD_WEBHOOK := url
        return url
    }
    return ""
}
InitTestWebhookStorage() {
    global SECURE_VAULT, TEST_WEBHOOK_FILE, TEST_WEBHOOK_URL

    ; Prefer secure vault if available, else temp
    if (SECURE_VAULT != "")
        TEST_WEBHOOK_FILE := SECURE_VAULT "\.test_webhook"
    else
        TEST_WEBHOOK_FILE := A_Temp "\.test_webhook"

    ; Load saved value if present
    try {
        if FileExist(TEST_WEBHOOK_FILE)
            TEST_WEBHOOK_URL := Trim(FileRead(TEST_WEBHOOK_FILE, "UTF-8"))
    } catch {
        TEST_WEBHOOK_URL := ""
    }
}

OpenTestWebhookGui() {
    global TEST_WEBHOOK_URL, TEST_WEBHOOK_FILE, COLORS

    g := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "Webhook Test Settings")
    g.BackColor := COLORS.bg
    g.SetFont("s10 c" COLORS.text, "Segoe UI")

    g.Add("Text", "x15 y15 w520 c" COLORS.text, "Enter a Discord webhook URL to use for test pings:")
    e := g.Add("Edit", "x15 y40 w520 h25 Background" COLORS.bgLight " c" COLORS.text)
    e.Value := TEST_WEBHOOK_URL

    status := g.Add("Text", "x15 y75 w520 c" COLORS.textDim, "")

    btnSave := g.Add("Button", "x15 y105 w160 h35 Background" COLORS.success, "Save Webhook")
    btnTest := g.Add("Button", "x195 y105 w160 h35 Background" COLORS.accentAlt, "Send Test Ping")
    btnClose := g.Add("Button", "x375 y105 w160 h35 Background" COLORS.danger, "Close")

    btnSave.OnEvent("Click", (*) => (
        SaveTestWebhook_(Trim(e.Value), status)
    ))

    btnTest.OnEvent("Click", (*) => (
        SaveTestWebhook_(Trim(e.Value), status),
        TestWebhookPing()
    ))

    btnClose.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())

    g.Show("w555 h160 Center")
}

SaveTestWebhook_(url, statusCtrl := 0) {
    global TEST_WEBHOOK_URL, TEST_WEBHOOK_FILE

    ; Basic sanity check
    if (url = "" || !InStr(url, "discord.com/api/webhooks/")) {
        if (statusCtrl)
            statusCtrl.Value := "❌ That doesn't look like a Discord webhook URL."
        SoundBeep(700, 120)
        return false
    }

    TEST_WEBHOOK_URL := url

    try {
        if FileExist(TEST_WEBHOOK_FILE)
            FileDelete TEST_WEBHOOK_FILE
        FileAppend TEST_WEBHOOK_URL, TEST_WEBHOOK_FILE, "UTF-8"
    } catch {
        if (statusCtrl)
            statusCtrl.Value := "⚠️ Saved in memory, but failed to write file."
        return true
    }

    if (statusCtrl)
        statusCtrl.Value := "✅ Saved!"
    return true
}

TestWebhookPing() {
    global TEST_WEBHOOK_URL, DISCORD_WEBHOOK, TEST_PING_USER_ID, TEST_PING_COUNT

    ; Use custom test webhook if set, else fall back to main webhook
    url := (TEST_WEBHOOK_URL != "" ? TEST_WEBHOOK_URL : DISCORD_WEBHOOK)

    if (url = "") {
        MsgBox "No webhook set. Press Ctrl+Shift+W to set a test webhook first.", "Webhook Test", "Icon!"
        return
    }

    TEST_PING_COUNT += 1

    msg :=
        "<@" TEST_PING_USER_ID "> ✅ Webhook test ping #" TEST_PING_COUNT "`n"
      . "Time: " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`n"
      . "PC: " A_ComputerName " | User: " A_UserName

    payload := '{ "content": "' JsonEscape(msg) '" }'

    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(8000, 8000, 8000, 8000)
        http.Open("POST", url, false)
        http.SetRequestHeader("Content-Type", "application/json")
        http.SetRequestHeader("User-Agent", "V1LN-Clan")
        http.Send(payload)

        ; Discord often returns 204 on success
        if (http.Status = 204 || http.Status = 200) {
            SoundBeep(900, 120)
        } else {
            MsgBox "Webhook returned status: " http.Status "`n" http.ResponseText, "Webhook Test Failed", "Icon!"
        }
    } catch as err {
        MsgBox "Webhook error: " err.Message, "Webhook Test Error", "Icon!"
    }
}

^+l::TestLoginWebhook()
TestLoginWebhook() {
    global TEST_WEBHOOK_URL

    ; Use custom test webhook if set, otherwise uses the normal DISCORD_WEBHOOK

}

SendDiscordWebhook1_(webhookUrl, payloadJson, label := "webhook") {
    logFile := A_Temp "\v1ln_webhook_debug.log"
    FileAppend "`n==== " label " ====`n", logFile
    FileAppend "URL=" webhookUrl "`n", logFile

    if (webhookUrl = "" || !InStr(webhookUrl, "discord.com/api/webhooks/")) {
        FileAppend "FAIL: url empty/invalid`n", logFile
        return false
    }

    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(8000, 8000, 8000, 8000)
        http.Open("POST", webhookUrl, false)
        http.SetRequestHeader("Content-Type", "application/json")
        http.SetRequestHeader("User-Agent", "V1LN-Clan")
        http.Send(payloadJson)

        FileAppend "Status=" http.Status "`n", logFile
        try FileAppend "Resp=" http.ResponseText "`n", logFile

        ; Discord success is usually 204 (No Content)
        return (http.Status = 204 || http.Status = 200)
    } catch as err {
        FileAppend "EXCEPTION=" err.Message "`n", logFile
        return false
    }
}
EnsureDiscordWebhookLoaded() {
    global DISCORD_WEBHOOK, MANIFEST_URL

    if (DISCORD_WEBHOOK != "")
        return DISCORD_WEBHOOK

    tmp := A_Temp "\manifest_webhook.json"
    if !SafeDownload(MANIFEST_URL, tmp, 20000)
        return ""

    try json := FileRead(tmp, "UTF-8")
    catch
        return ""

    if RegExMatch(json, '"webhook"\s*:\s*"([^"]+)"', &m) {
        DISCORD_WEBHOOK := StrReplace(m[1], "\/", "/")
        return DISCORD_WEBHOOK
    }
    return ""
}




IsFirstRunUser_() {
    global FIRST_LOGIN_TRACKER_FILE
    try {
        if FileExist(FIRST_LOGIN_TRACKER_FILE)
            return false
        ; mark as “seen” immediately so it won’t spam if the app crashes later
        FileAppend FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"), FIRST_LOGIN_TRACKER_FILE, "UTF-8"
        return true
    } catch {
        ; if writing fails, treat as not-first to avoid spam
        return false
    }
}

GetOrCreateVaultId() {
    global VAULT_ID_FILE

    try {
        if (VAULT_ID_FILE != "" && FileExist(VAULT_ID_FILE)) {
            vid := Trim(FileRead(VAULT_ID_FILE, "UTF-8"))
            if (vid != "" && StrLen(vid) >= 16)
                return vid
        }
    } catch {

    }

    ; create once
    vid := Sha256Hex(A_ComputerName "|" A_UserName "|" A_OSVersion "|" A_Now "|" Random(1, 0x7fffffff))

    ; save into the SAME vault folder
    try {
        if (VAULT_ID_FILE != "" ) {
            if FileExist(VAULT_ID_FILE)
                FileDelete VAULT_ID_FILE
            FileAppend vid, VAULT_ID_FILE, "UTF-8"
        }
    } catch {

    }

    return vid
}


Sha256Hex(str) {
    ; Returns 64-char hex SHA-256 of UTF-8 string
    static BCRYPT_SHA256_ALGORITHM := "SHA256"
    static BCRYPT_OBJECT_LENGTH := "ObjectLength"
    static BCRYPT_HASH_LENGTH := "HashDigestLength"

    ; Open algorithm provider
    hAlg := 0
    if DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg, "WStr", BCRYPT_SHA256_ALGORITHM, "Ptr", 0, "UInt", 0) != 0
        return ""

    ; Query object length
    objLen := 0, cbRes := 0
    if DllCall("bcrypt\BCryptGetProperty", "Ptr", hAlg, "WStr", BCRYPT_OBJECT_LENGTH, "Ptr*", &objLen, "UInt", 4, "UInt*", &cbRes, "UInt", 0) != 0 {
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
        return ""
    }

    ; Query hash length
    hashLen := 0
    if DllCall("bcrypt\BCryptGetProperty", "Ptr", hAlg, "WStr", BCRYPT_HASH_LENGTH, "Ptr*", &hashLen, "UInt", 4, "UInt*", &cbRes, "UInt", 0) != 0 {
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
        return ""
    }

    ; Create hash object
    hHash := 0
    hashObj := Buffer(objLen, 0)
    if DllCall("bcrypt\BCryptCreateHash", "Ptr", hAlg, "Ptr*", &hHash, "Ptr", hashObj.Ptr, "UInt", objLen, "Ptr", 0, "UInt", 0, "UInt", 0) != 0 {
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
        return ""
    }

    ; Hash data (UTF-8)
    data := Buffer(StrPut(str, "UTF-8"), 0)
    StrPut(str, data, "UTF-8")
    if DllCall("bcrypt\BCryptHashData", "Ptr", hHash, "Ptr", data.Ptr, "UInt", data.Size - 1, "UInt", 0) != 0 {
        DllCall("bcrypt\BCryptDestroyHash", "Ptr", hHash)
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
        return ""
    }

    ; Finish hash
    hash := Buffer(hashLen, 0)
    if DllCall("bcrypt\BCryptFinishHash", "Ptr", hHash, "Ptr", hash.Ptr, "UInt", hashLen, "UInt", 0) != 0 {
        DllCall("bcrypt\BCryptDestroyHash", "Ptr", hHash)
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
        return ""
    }

    ; Cleanup
    DllCall("bcrypt\BCryptDestroyHash", "Ptr", hHash)
    DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)

    ; Hex encode
    out := ""
    Loop hashLen
        out .= Format("{:02x}", NumGet(hash, A_Index - 1, "UChar"))
    return out
}

CheckLoginAppUpdate() {
    global LAUNCHER_VERSION, MANIFEST_URL
    
    try {
        ; Download manifest with cache-busting
        tmpManifest := A_Temp "\manifest_update_check_" A_TickCount ".json"
        
        if !SafeDownload(NoCacheUrl(MANIFEST_URL), tmpManifest, 15000) {
            return  ; Silently fail - don't block app launch
        }
        
        ; Parse manifest
        json := ""
        try {
            json := FileRead(tmpManifest, "UTF-8")
        } catch {
            try FileDelete tmpManifest
            return
        }
        
        ; Extract launcher_version and login_url
        manifestVersion := ""
        loginUrl := ""
        
        if RegExMatch(json, '"launcher_version"\s*:\s*"([^"]+)"', &v) {
            manifestVersion := Trim(v[1])
        }
        
        if RegExMatch(json, '"login_url"\s*:\s*"([^"]+)"', &u) {
            loginUrl := Trim(u[1])
        }
        
        ; Cleanup manifest
        try FileDelete tmpManifest
        
        ; Check if update needed
        if (manifestVersion = "" || loginUrl = "") {
            return  ; Missing data, skip update
        }
        
        if (VersionCompare(manifestVersion, LAUNCHER_VERSION) <= 0) {
            return  ; Already up to date
        }
        
        ; ===== UPDATE AVAILABLE =====
        choice := MsgBox(
            "📄 Login App Update Available!`n`n"
            . "Current: v" LAUNCHER_VERSION "`n"
            . "Latest: v" manifestVersion "`n`n"
            . "Update now? (Recommended)",
            "AHK Vault - Update Available",
            "YesNo Iconi"
        )
        
        if (choice = "No") {
            return
        }
        
        ; Download new version with cache-busting
        tmpUpdate := A_Temp "\AHK_Vault_Login_Update_" A_TickCount ".ahk"
        
        ToolTip "Downloading update v" manifestVersion "..."
        
        if !SafeDownload(NoCacheUrl(loginUrl), tmpUpdate, 30000) {
            ToolTip
            MsgBox "Update download failed. Continuing with current version.", "Update Failed", "Icon!"
            return
        }
        
        ToolTip
        
        ; Validate downloaded file
        try {
            content := FileRead(tmpUpdate, "UTF-8")
            
            if (StrLen(content) < 1000) {
                throw Error("Downloaded file too small")
            }
            
            if (!InStr(content, "#Requires AutoHotkey v2.0")) {
                throw Error("Not a valid AHK v2 script")
            }
            
            if (!InStr(content, "LAUNCHER_VERSION")) {
                throw Error("Not the login app")
            }
            
            ; Verify the downloaded version matches manifest
            if RegExMatch(content, 'LAUNCHER_VERSION\s*:=\s*"([^"]+)"', &dlv) {
                if (Trim(dlv[1]) != manifestVersion) {
                    throw Error("Version mismatch - downloaded v" dlv[1] " but expected v" manifestVersion)
                }
            }
            
        } catch as err {
            MsgBox "Update validation failed: " err.Message "`n`nContinuing with current version.", "Update Failed", "Icon!"
            try FileDelete tmpUpdate
            return
        }
        
        ; ===== APPLY UPDATE =====
        ApplyLoginUpdate(tmpUpdate, manifestVersion)
        
    } catch as err {
        ; Silent fail - don't interrupt app launch
    }
}

ApplyLoginUpdate(updateFile, newVersion) {
    global LAUNCHER_VERSION
    
    try {
        currentScript := A_ScriptFullPath
        
        ; Create batch file to replace script and restart
        batFile := A_Temp "\update_login_" A_TickCount ".bat"
        batContent := '@echo off'
                   . '`necho Updating AHK Vault Login...'
                   . '`ntimeout /t 2 /nobreak >nul'
                   . '`n:RETRY'
                   . '`ncopy /y "' updateFile '" "' currentScript '"'
                   . '`nif errorlevel 1 ('
                   . '`n    timeout /t 1 /nobreak >nul'
                   . '`n    goto RETRY'
                   . '`n)'
                   . '`ntimeout /t 1 /nobreak >nul'
                   . '`nstart "" "' A_AhkPath '" "' currentScript '"'
                   . '`ntimeout /t 2 /nobreak >nul'
                   . '`ndel "' updateFile '"'
                   . '`ndel "%~f0"'
        
        if FileExist(batFile)
            FileDelete batFile
        FileAppend batContent, batFile
        
        ; Show update message
        MsgBox (
            "✅ Update downloaded successfully!`n`n"
            . "The app will restart now to apply the update.`n`n"
            . "Current: v" LAUNCHER_VERSION "`n"
            . "New: v" newVersion
        ), "Update Ready", "Iconi T3000"
        
        ; Run update batch and exit
        Run batFile, , "Hide"
        ExitApp
        
    } catch as err {
        MsgBox "Failed to apply update: " err.Message "`n`nContinuing with current version.", "Update Failed", "Icon!"
        
        ; Cleanup
        try FileDelete updateFile
        try FileDelete batFile
    }
}

NoCacheUrl(url) {
    separator := InStr(url, "?") ? "&" : "?"
    ; Use timestamp + random to prevent caching
    return url . separator . "nocache=" . A_TickCount . "&rand=" . Random(1000, 9999)
}


TestAuthConnection() {
    url := WorkerURL("get-credentials")

    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(5000, 5000, 5000, 15000)
        req.Open("POST", url, false)

        req.SetRequestHeader("Content-Type", "application/json")
        req.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AHKAuthClient/1.0")

        req.Send("{}")

        MsgBox "CONNECTED`nHTTP: " req.Status "`n`n" SubStr(req.ResponseText, 1, 400)
    } catch as e {
        MsgBox "FAILED BEFORE RESPONSE`nError: " e.Message "`nA_LastError: " A_LastError
    }
}

DescribeHttpFailure(tag, req) {
    s := "❌ " tag
    try s .= " (HTTP " req.Status ")"
    try {
        body := req.ResponseText
        if (body != "")
            s .= ": " SubStr(StrReplace(body, "`r", ""), 1, 160)
    }
    return s
}
