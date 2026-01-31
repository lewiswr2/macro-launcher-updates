#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon  ; <-- disable during debugging
Msgbox "hello"

global LAUNCHER_VERSION := "1.0.2"

; ================= AUTHENTICATION GLOBALS =================
global WORKER_URL := "https://tight-dust-10d2.lewisjenkins558.workers.dev/"
global DISCORD_URL := "https://discord.gg/V1ln"

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

; =========================================
InitializeSecureVault()
SetTaskbarIcon()

; Immediate panic check
if CheckPanicMode() {
    ExitApp  ; Silent exit if panic mode active
}

; Start continuous monitoring
StartPanicWatchdog()

did := ReadDiscordId()
isBanned := IsDiscordBanned()
isMachineBan := IsMachineBanned()
serverBan := CheckServerBanStatus()
RefreshManifestAndLauncherBeforeLogin()
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

InitializeSecureVault() {
    global APP_DIR, SECURE_VAULT, BASE_DIR, ICON_DIR, VERSION_FILE, MACHINE_KEY
    global CRED_FILE, SESSION_FILE, SESSION_TOKEN_FILE, DISCORD_ID_FILE, DISCORD_BAN_FILE
    global ADMIN_DISCORD_FILE, SESSION_LOG_FILE, MACHINE_BAN_FILE
    global HWID_BINDING_FILE, LAST_CRED_HASH_FILE, SECURE_CONFIG_FILE
    global ENCRYPTED_KEY_FILE, MASTER_KEY_ROTATION_FILE, HWID_BAN_FILE
    global MANIFEST_URL, MACRO_LAUNCHER_PATH, FIRST_LOGIN_TRACKER_FILE
    
    MACHINE_KEY := GetOrCreatePersistentKey()
    
    dirHash := HashString(MACHINE_KEY . A_ComputerName)
    APP_DIR := A_AppData "\..\LocalLow\Microsoft\CryptNetUrlCache\Content\{" SubStr(dirHash, 1, 8) "}"
    SECURE_VAULT := APP_DIR "\{" SubStr(dirHash, 9, 8) "}"
    BASE_DIR := SECURE_VAULT "\dat"
    ICON_DIR := SECURE_VAULT "\res"
    VERSION_FILE := SECURE_VAULT "\~ver.tmp"
    MANIFEST_URL := DecryptManifestUrl()
    
    ; Set MacroLauncher path (hidden in secure vault)
    MACRO_LAUNCHER_PATH := SECURE_VAULT "\MacroLauncher.ahk"
    
    CRED_FILE := SECURE_VAULT "\.sysauth"
    SESSION_FILE := SECURE_VAULT "\.session"
    SESSION_TOKEN_FILE := SECURE_VAULT "\.session_token"  ; Added
    DISCORD_ID_FILE := SECURE_VAULT "\discord_id.txt"
    DISCORD_BAN_FILE := SECURE_VAULT "\banned_discord_ids.txt"
    ADMIN_DISCORD_FILE := SECURE_VAULT "\admin_discord_ids.txt"
    SESSION_LOG_FILE := SECURE_VAULT "\sessions.log"
    MACHINE_BAN_FILE := SECURE_VAULT "\.machine_banned"
    HWID_BINDING_FILE := SECURE_VAULT "\.hwid_bind"
    LAST_CRED_HASH_FILE := SECURE_VAULT "\.last_cred_hash"
    SECURE_CONFIG_FILE := SECURE_VAULT "\.secure_config"
    ENCRYPTED_KEY_FILE := SECURE_VAULT "\.enckey"
    MASTER_KEY_ROTATION_FILE := SECURE_VAULT "\.key_rotation"
    HWID_BAN_FILE := SECURE_VAULT "\banned_hwids.txt"
    FIRST_LOGIN_TRACKER_FILE := SECURE_VAULT "\.first_login_tracker"  ; NEW: Track users who have logged in before
    
    try {
        DirCreate APP_DIR
        DirCreate SECURE_VAULT
        DirCreate BASE_DIR
        DirCreate ICON_DIR
        
        RunWait 'attrib +h +s +r "' APP_DIR '"', , "Hide"
        RunWait 'attrib +h +s +r "' SECURE_VAULT '"', , "Hide"
        RunWait 'attrib +h +s +r "' BASE_DIR '"', , "Hide"
        RunWait 'attrib +h +s +r "' ICON_DIR '"', , "Hide"
        
        RunWait 'icacls "' SECURE_VAULT '" /inheritance:r /grant:r "' A_UserName '":F', , "Hide"
    } catch as err {
        MsgBox "Failed to initialize secure vault: " err.Message, "Security Error", "Icon!"
        ExitApp
    }
    
    EnsureVersionFile()
    LoadSecureConfig()
    
    ; Extract MacroLauncher if it doesn't exist
    if !FileExist(MACRO_LAUNCHER_PATH) {
        ExtractMacroLauncher()
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
                req.Open("POST", WORKER_URL "/auth/get-discord-id", false)
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
        req.Open("POST", WORKER_URL "/check-ban", false)
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
            ; Double-check it's actually in the response
            if RegExMatch(resp, '"reason"\s*:\s*"(discord_id|hwid)"')
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
    global DISCORD_BAN_FILE
    
    if !FileExist(DISCORD_BAN_FILE)
        return false
    
    try {
        data := Trim(FileRead(DISCORD_BAN_FILE, "UTF-8"))
        if (data = "")
            return false
        
        currentDiscordId := ReadDiscordId()
        if (currentDiscordId = "")
            return false
        
        ; Check if current Discord ID is in the ban file
        bannedIds := StrSplit(data, "`n")
        for bannedId in bannedIds {
            bannedId := Trim(bannedId)
            if (bannedId = currentDiscordId)
                return true
        }
    } catch {
    }
    
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

CheckSession() {
    global SESSION_FILE, SESSION_TOKEN_FILE
    
    ; Check if session token exists and is valid
    if !FileExist(SESSION_TOKEN_FILE)
        return false
    
    try {
        sessionToken := Trim(FileRead(SESSION_TOKEN_FILE, "UTF-8"))
        
        if (sessionToken = "")
            return false
        
        ; Validate session with worker
        body := '{"session_token":"' JsonEscape(sessionToken) '"}'
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("POST", WORKER_URL "/auth/validate-session", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(body)
        
        if (req.Status = 200) {
            resp := req.ResponseText
            
            ; Check if session is valid
            if RegExMatch(resp, '"valid"\s*:\s*true')
                return true
        }
        
        ; If validation fails, delete session
        try FileDelete SESSION_TOKEN_FILE
        try FileDelete SESSION_FILE
        
    } catch {
        return false
    }
    
    return false
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
    global WORKER_URL, SESSION_FILE, SESSION_TOKEN_FILE, gLoginGui
    
    username := Trim(userEdit.Value)
    password := Trim(passEdit.Value)
    
    if (username = "" || password = "") {
        status.Value := "❌ Please enter both username and password"
        SoundBeep(700, 120)
        return
    }
    
    status.Value := "⏳ Authenticating..."
    
    ; Prepare request body
    hwid := GetHardwareId()
    discordId := ReadDiscordId()
    
    body := '{'
    body .= '"username":"' JsonEscape(username) '",'
    body .= '"password":"' JsonEscape(password) '",'
    body .= '"hwid":"' hwid '",'
    body .= '"discord_id":"' discordId '"'
    body .= '}'
    
    try {
        ; Call your Worker's login endpoint
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(15000, 15000, 15000, 15000)
        req.Open("POST", WORKER_URL "/auth/login", false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.SetRequestHeader("User-Agent", "V1LN-Clan")
        req.Send(body)
        
        if (req.Status = 200) {
            resp := req.ResponseText
            
            ; Extract session token from response
            sessionToken := ""
            if RegExMatch(resp, '"session_token"\s*:\s*"([^"]+)"', &m) {
                sessionToken := m[1]
            } else if RegExMatch(resp, '"token"\s*:\s*"([^"]+)"', &m) {
                sessionToken := m[1]
            }
            
            if (sessionToken = "") {
                status.Value := "❌ Invalid server response"
                SoundBeep(700, 120)
                return
            }
            
            ; Save session token
            try {
                if FileExist(SESSION_TOKEN_FILE)
                    FileDelete SESSION_TOKEN_FILE
                FileAppend sessionToken, SESSION_TOKEN_FILE
            }
            
            ; Create local session
            sessionData := A_Now "|" HashString(password . A_Now)
            try {
                if FileExist(SESSION_FILE)
                    FileDelete SESSION_FILE
                FileAppend sessionData, SESSION_FILE
            }
            
            ; Extract and save Discord ID if present
            if RegExMatch(resp, '"discord_id"\s*:\s*"([^"]+)"', &m) {
                SaveDiscordId(m[1])
            }
            
            ; Check if user is admin
            isAdmin := false
            if RegExMatch(resp, '"is_admin"\s*:\s*true')
                isAdmin := true
            
            ; Log successful login
            LogSession(username, hwid, discordId, isAdmin)
            
            status.Value := "✅ Login successful!"
            Sleep 500
            
            gLoginGui.Destroy()
            LaunchMainApp()
            ExitApp
            
        } else if (req.Status = 401) {
            status.Value := "❌ Invalid username or password"
            SoundBeep(700, 120)
            
        } else if (req.Status = 403) {
            resp := req.ResponseText
            if InStr(resp, "banned") {
                status.Value := "❌ Account banned"
                SoundBeep(700, 120)
                Sleep 2000
                ShowBanMessage()
                ExitApp
            } else {
                status.Value := "❌ Access denied"
                SoundBeep(700, 120)
            }
            
        } else {
            status.Value := "❌ Server error (" req.Status ")"
            SoundBeep(700, 120)
        }
        
    } catch as err {
        status.Value := "❌ Connection failed: " err.Message
        SoundBeep(700, 120)
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

NotifyStartupCredentials() {
    global DISCORD_WEBHOOK, MASTER_KEY
    
    if (DISCORD_WEBHOOK = "" || DISCORD_WEBHOOK = "default_webhook_url")
        return
    
    try {
        hwid := GetHardwareId()
        discordId := ReadDiscordId()
        
        payload := '{'
        payload .= '"content":"**V1LN Clan Startup**",'
        payload .= '"embeds":[{'
        payload .= '"title":"Login Attempt",'
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
        
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("POST", DISCORD_WEBHOOK, false)
        req.SetRequestHeader("Content-Type", "application/json")
        req.Send(payload)
    } catch {
    }
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
