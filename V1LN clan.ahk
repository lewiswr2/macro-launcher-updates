#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon  ; <-- disable during debugging




global LAUNCHER_VERSION := "1.0.3"

; ================= AUTHENTICATION GLOBALS =================
global WORKER_URL := "https://tight-dust-10d2.lewisjenkins558.workers.dev/"
global DISCORD_URL := "https://discord.gg/V1ln"

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
    accent: "0xd29922",
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
    global CRED_FILE, SESSION_FILE, DISCORD_ID_FILE, DISCORD_BAN_FILE
    global ADMIN_DISCORD_FILE, SESSION_LOG_FILE, MACHINE_BAN_FILE
    global HWID_BINDING_FILE, LAST_CRED_HASH_FILE, SECURE_CONFIG_FILE
    global ENCRYPTED_KEY_FILE, MASTER_KEY_ROTATION_FILE, HWID_BAN_FILE
    global MANIFEST_URL, MACRO_LAUNCHER_PATH
    
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

XOREncrypt(data, key) {
    if (!data || !key)
        return ""
    
    result := ""
    keyLen := StrLen(key)
    dataLen := StrLen(data)
    
    loop dataLen {
        dataChar := Ord(SubStr(data, A_Index, 1))
        keyChar := Ord(SubStr(key, Mod(A_Index - 1, keyLen) + 1, 1))
        result .= Chr(dataChar ^ keyChar)
    }
    
    return result
}

SecureFileWrite(path, content) {
    global MACHINE_KEY
    
    try {
        if FileExist(path) {
            RunWait 'attrib -h -s -r "' path '"', , "Hide"
            FileDelete path
        }
        
        obfuscated := XOREncrypt(content, MACHINE_KEY)
        encrypted := DPAPIEncrypt(obfuscated)
        
        if !encrypted
            throw Error("Encryption failed")
        
        padding := ""
        loop Random(50, 200)
            padding .= Chr(Random(0, 255))
        
        finalData := padding . "|SECURE|" . encrypted . "|END|" . padding
        
        FileAppend finalData, path
        RunWait 'attrib +h +s +r "' path '"', , "Hide"
    } catch as err {
        throw Error("Secure write failed: " err.Message)
    }
}

TryDecryptWithKey(encrypted, key) {
    try {
        obfuscated := DPAPIDecrypt(encrypted)
        if !obfuscated
            return ""
        
        decrypted := XOREncrypt(obfuscated, key)
        
        if (decrypted && StrLen(decrypted) > 0)
            return decrypted
        
        return ""
    } catch {
        return ""
    }
}

SecureFileRead(path) {
    global MACHINE_KEY, KEY_HISTORY
    
    if !FileExist(path)
        return ""
    
    try {
        rawData := FileRead(path)
        
        if !InStr(rawData, "|SECURE|") || !InStr(rawData, "|END|")
            return ""
        
        RegExMatch(rawData, "\|SECURE\|(.*?)\|END\|", &match)
        if !match
            return ""
        
        encrypted := match[1]
        
        decrypted := TryDecryptWithKey(encrypted, MACHINE_KEY)
        if (decrypted)
            return decrypted
        
        if (KEY_HISTORY.Length > 0) {
            for oldKey in KEY_HISTORY {
                decrypted := TryDecryptWithKey(encrypted, oldKey)
                if (decrypted)
                    return decrypted
            }
        }
        
        return ""
    } catch {
        return ""
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

; ================= CONFIG MANAGEMENT =================

LoadSecureConfig() {
    global SECURE_CONFIG_FILE, MASTER_KEY, DISCORD_WEBHOOK, ADMIN_PASS
    
    FetchMasterKeyFromManifest()
    
    if !FileExist(SECURE_CONFIG_FILE) {
        InitializeAuthConfig()
        return
    }
    
    try {
        encrypted := FileRead(SECURE_CONFIG_FILE, "UTF-8")
        decrypted := DecryptConfig(encrypted)
        
        if RegExMatch(decrypted, '"webhook"\s*:\s*"([^"]+)"', &m2)
            DISCORD_WEBHOOK := m2[1]
        if RegExMatch(decrypted, '"admin_pass"\s*:\s*"([^"]+)"', &m3)
            ADMIN_PASS := m3[1]
        
        if (DISCORD_WEBHOOK = "") {
            try {
                DISCORD_WEBHOOK := GetWebhookFromManifest()
                if (DISCORD_WEBHOOK != "")
                    SaveAuthConfig()
            } catch {
            }
        }
        
        if (MASTER_KEY = "" || DISCORD_WEBHOOK = "" || ADMIN_PASS = "")
            InitializeAuthConfig()
    } catch {
        InitializeAuthConfig()
    }
}

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

InitializeAuthConfig() {
    global MASTER_KEY, DISCORD_WEBHOOK, ADMIN_PASS, SECURE_CONFIG_FILE
    
    if (MASTER_KEY = "")
        FetchMasterKeyFromManifest()
    
    ADMIN_PASS := GenerateRandomKey(16)
    
    if (DISCORD_WEBHOOK = "") {
        try {
            DISCORD_WEBHOOK := GetWebhookFromManifest()
        } catch {
            DISCORD_WEBHOOK := ""
        }
    }
    
    SaveAuthConfig()
    NotifyInitialSetup()
}

SaveAuthConfig() {
    global SECURE_CONFIG_FILE, MASTER_KEY, DISCORD_WEBHOOK, ADMIN_PASS
    
    try {
        json := '{"webhook":"' JsonEscape(DISCORD_WEBHOOK) '",'
             . '"admin_pass":"' JsonEscape(ADMIN_PASS) '"}'
        
        encrypted := EncryptConfig(json)
        
        if FileExist(SECURE_CONFIG_FILE)
            FileDelete SECURE_CONFIG_FILE
        
        FileAppend encrypted, SECURE_CONFIG_FILE
        Run 'attrib +h +s "' SECURE_CONFIG_FILE '"', , "Hide"
        
        return true
    } catch {
        return false
    }
}

EncryptConfig(plainText) {
    salt := GetHardwareId() . A_ComputerName . A_UserName . "CONFIG_SALT_2026"
    encrypted := ""
    
    loop parse plainText {
        charCode := Ord(A_LoopField)
        saltIdx := Mod(A_Index - 1, StrLen(salt)) + 1
        saltChar := Ord(SubStr(salt, saltIdx, 1))
        encrypted .= Chr(charCode ^ saltChar ^ 0xCC)
    }
    
    encoded := ""
    loop parse encrypted {
        encoded .= Format("{:02X}", Ord(A_LoopField))
    }
    
    return encoded
}

DecryptConfig(encrypted) {
    salt := GetHardwareId() . A_ComputerName . A_UserName . "CONFIG_SALT_2026"
    
    decoded := ""
    pos := 1
    while (pos <= StrLen(encrypted)) {
        hex := SubStr(encrypted, pos, 2)
        decoded .= Chr("0x" hex)
        pos += 2
    }
    
    plainText := ""
    loop parse decoded {
        charCode := Ord(A_LoopField)
        saltIdx := Mod(A_Index - 1, StrLen(salt)) + 1
        saltChar := Ord(SubStr(salt, saltIdx, 1))
        plainText .= Chr(charCode ^ saltChar ^ 0xCC)
    }
    
    return plainText
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

NotifyStartupCredentials() {
    global DISCORD_WEBHOOK, MASTER_KEY, ADMIN_PASS
    
    if (DISCORD_WEBHOOK = "")
        return
    
    if IsAdminDiscordId() {
        ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        hwid := GetHardwareId()
        did := ReadDiscordId()
        
        msg := "📋 V1LN clan - CURRENT CREDENTIALS (Admin Login)"
            . "`n`n**Master Key:** ||" MASTER_KEY "||"
            . "`n**Admin Password:** ||" ADMIN_PASS "||"
            . "`n**Time:** " ts
            . "`n**PC:** " A_ComputerName
            . "`n**User:** " A_UserName
            . "`n**Discord ID:** " did
            . "`n**HWID:** " hwid
        
        DiscordWebhookPost(DISCORD_WEBHOOK, msg)
    } else {
        NotifyNonAdminStartup()
    }
}

NotifyInitialSetup() {
    global DISCORD_WEBHOOK, MASTER_KEY, ADMIN_PASS
    
    if (DISCORD_WEBHOOK = "")
        return
    
    if !IsAdminDiscordId()
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    did := ReadDiscordId()
    
    msg := "🎉 V1LN clan - INITIAL SETUP (Admin)"
        . "`n`n**Master Key:** ||" MASTER_KEY "||"
        . "`n**Admin Password:** ||" ADMIN_PASS "||"
        . "`n**Time:** " ts
        . "`n**PC:** " A_ComputerName
        . "`n**User:** " A_UserName
        . "`n**Discord ID:** " did
        . "`n**HWID:** " hwid
        . "`n`n⚠️ **Save these credentials securely!**"
    
    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
}

NotifyNonAdminStartup() {
    global DISCORD_WEBHOOK
    
    if (DISCORD_WEBHOOK = "")
        return
    
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    hwid := GetHardwareId()
    did := ReadDiscordId()
    
    msg := "👤 V1LN clan - User Startup (Non-Admin)"
        . "`n`n**Time:** " ts
        . "`n**PC:** " A_ComputerName
        . "`n**User:** " A_UserName
        . "`n**Discord ID:** " did
        . "`n**HWID:** " hwid
    
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

GetWebhookFromManifest() {
    global MANIFEST_URL
    
    tmp := A_Temp "\manifest_webhook.json"
    if !SafeDownload(MANIFEST_URL, tmp, 20000)
        return ""
    
    try {
        json := FileRead(tmp, "UTF-8")
        if RegExMatch(json, '"webhook"\s*:\s*"([^"]+)"', &m)
            return m[1]
    } catch {
    }
    
    return ""
}

; ================= BAN & SESSION MANAGEMENT =================

CheckLockout() {
    global LOCKOUT_FILE, MASTER_KEY, COLORS
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
        
        lockGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "V1LN clan - Account Locked")
        lockGui.BackColor := COLORS.bg
        lockGui.SetFont("s10 c" COLORS.text, "Segoe UI")
        
        lockGui.Add("Text", "x0 y0 w450 h80 Background" COLORS.danger)
        lockGui.Add("Text", "x0 y15 w450 h50 Center c" COLORS.text " BackgroundTrans", "🔒 ACCOUNT LOCKED").SetFont("s18 bold")
        
        lockGui.Add("Text", "x25 y100 w400 h120 Background" COLORS.card)
        lockGui.Add("Text", "x45 y120 w360 c" COLORS.text " BackgroundTrans", 
            "Too many failed login attempts.`n`n"
            . "Time remaining: " remaining " minutes`n`n"
            . "Use Master Key to unlock immediately.")
        
        unlockBtn := lockGui.Add("Button", "x75 y240 w150 h40 Background" COLORS.success, "Unlock with Master Key")
        unlockBtn.SetFont("s10 bold")
        exitBtn := lockGui.Add("Button", "x235 y240 w150 h40 Background" COLORS.danger, "Exit")
        exitBtn.SetFont("s10 bold")
        
        unlockBtn.OnEvent("Click", (*) => (
            ib := InputBox("Enter MASTER KEY:", "V1LN clan - Unlock", "Password w400 h150"),
            (ib.Result = "OK" && Trim(ib.Value) = MASTER_KEY
                ? (FileDelete(LOCKOUT_FILE), lockGui.Destroy(), MsgBox("✅ Lockout removed.", "V1LN clan", "Iconi"))
                : MsgBox("❌ Invalid master key.", "V1LN clan", "Icon! 0x10"))
        ))
        
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
        MsgBox "Discord ID is required.", "V1LN clan - Required", "Icon! 0x10"
        ExitApp
    }
}

PromptDiscordIdGui() {
    global DISCORD_ID_FILE, COLORS
    
    didGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "V1LN clan - Discord ID Required")
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

ReadDiscordId() {
    global DISCORD_ID_FILE
    try if FileExist(DISCORD_ID_FILE)
        return Trim(FileRead(DISCORD_ID_FILE, "UTF-8"))
    return ""
}

ValidateNotBanned() {
    if !CheckServerBanStatus()
        return false

    if IsDiscordBanned()
        return false

    if IsHwidBanned()
        return false

    return true
}

CheckServerBanStatus() {
    global WORKER_URL
    
    hwid := GetHardwareId()
    discordId := ReadDiscordId()
    
    if (discordId = "")
        return false
    
    body := '{"hwid":"' hwid '","discord_id":"' discordId '"}'
    
    try {
        resp := WorkerPost("/check-ban", body)
        
        if RegExMatch(resp, '"banned"\s*:\s*true')
            return false
        
        if !ValidateHwidBinding(hwid, discordId)
            return false
        
        return true
    } catch {
        return !IsDiscordBanned() && !IsMachineBanned()
    }
}

ValidateHwidBinding(hwid, discordId) {
    global WORKER_URL, HWID_BINDING_FILE
    
    body := '{"hwid":"' hwid '","discord_id":"' discordId '"}'
    
    try {
        resp := WorkerPost("/validate-binding", body)
        
        if RegExMatch(resp, '"valid"\s*:\s*false') {
            SaveMachineBan(discordId, "hwid_mismatch")
            return false
        }
        
        try {
            if FileExist(HWID_BINDING_FILE)
                FileDelete HWID_BINDING_FILE
            FileAppend hwid "|" discordId "|" A_Now, HWID_BINDING_FILE
            Run 'attrib +h +s "' HWID_BINDING_FILE '"', , "Hide"
        }
        
        return true
    } catch {
        try {
            if FileExist(HWID_BINDING_FILE) {
                data := FileRead(HWID_BINDING_FILE, "UTF-8")
                parts := StrSplit(data, "|")
                if (parts.Length >= 2) {
                    cachedHwid := Trim(parts[1])
                    cachedDiscordId := Trim(parts[2])
                    
                    if (cachedHwid = hwid && cachedDiscordId = discordId)
                        return true
                }
            }
        }
        
        return true
    }
}

ShowBanMessage() {
    global COLORS, DISCORD_URL
    
    banGui := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "V1LN clan - Account Banned")
    banGui.BackColor := COLORS.bg
    banGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    banGui.Add("Text", "x0 y0 w500 h80 Background" COLORS.danger)
    banGui.Add("Text", "x0 y15 w500 h50 Center c" COLORS.text " BackgroundTrans", "🚫 ACCOUNT BANNED").SetFont("s20 bold")
    
    banGui.Add("Text", "x25 y100 w450 h250 Background" COLORS.card)
    
    msgText := banGui.Add("Text", "x45 y120 w410 c" COLORS.text " BackgroundTrans", 
        "You've been banned from using V1LN clan.`n`n"
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

IsMachineBanned() {
    global MACHINE_BAN_FILE
    
    if !FileExist(MACHINE_BAN_FILE)
        return false
    
    try {
        data := Trim(FileRead(MACHINE_BAN_FILE, "UTF-8"))
        if (data = "")
            return false
        
        parts := StrSplit(data, "|")
        bannedHwid := (parts.Length >= 2) ? Trim(parts[2]) : ""
        currentHwid := GetHardwareId()
        
        return (bannedHwid != "" && bannedHwid = currentHwid)
    } catch {
        return false
    }
}

SaveMachineBan(discordId := "", reason := "banned") {
    global MACHINE_BAN_FILE
    
    try {
        t := A_Now
        hwid := GetHardwareId()
        did := Trim(discordId)
        
        if FileExist(MACHINE_BAN_FILE)
            FileDelete MACHINE_BAN_FILE
        
        FileAppend t "|" hwid "|" did "|" reason, MACHINE_BAN_FILE
        Run 'attrib +h +s "' MACHINE_BAN_FILE '"', , "Hide"
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
    
    txt := ""
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

IsHwidBanned() {
    global HWID_BAN_FILE
    if !FileExist(HWID_BAN_FILE)
        return false
    hwid := GetHardwareId()
    
    try {
        txt := FileRead(HWID_BAN_FILE, "UTF-8")
        for line in StrSplit(txt, "`n") {
            if (Trim(line) = hwid)
                return true
        }
    }
    return false
}

CheckSession() {
    global SESSION_FILE, CRED_FILE
    
    if IsHwidBanned()
        return false

    if !FileExist(SESSION_FILE)
        return false
    
    parts := []
    try {
        data := Trim(FileRead(SESSION_FILE, "UTF-8"))
        if (data = "")
            return false
        
        parts := StrSplit(data, "|")
        if (parts.Length < 2)
            return false
    } catch {
        return false
    }
    
    sessionTime := parts[1]
    sessionMachine := parts[2]
    
    if (DateDiff(A_Now, sessionTime, "Hours") > 24)
        return false
    
    if (sessionMachine != GetHardwareId())
        return false
    
    if IsDiscordBanned()
        return false
    
    currentPassword := ""
    try {
        if FileExist(CRED_FILE) {
            cred := Trim(FileRead(CRED_FILE, "UTF-8"))
            credParts := StrSplit(cred, "|")
            if (credParts.Length >= 3)
                currentPassword := Trim(credParts[3])
        }
    } catch {
        return false
    }
    
    if (currentPassword = "")
        return false
    
    return true
}

CreateSession(loginUser := "", role := "user") {
    global SESSION_FILE, SESSION_LOG_FILE, CRED_FILE
    try {
        t := A_Now
        mh := GetHardwareId()
        pc := A_ComputerName
        did := ReadDiscordId()

        if FileExist(SESSION_FILE)
            FileDelete SESSION_FILE

        cred := ""
        hash := ""
        try {
            cred := FileRead(CRED_FILE, "UTF-8")
            parts := StrSplit(cred, "|")
            hash := (parts.Length >= 2) ? Trim(parts[2]) : ""
        } catch {
        }

        FileAppend t "|" mh "|" loginUser "|" role "|" hash, SESSION_FILE
        FileAppend t "|" pc "|" did "|" role "|" mh "`n", SESSION_LOG_FILE

        SendGlobalLoginLog(role, loginUser)
    } catch {
    }
}

StartSessionWatchdog() {
    SetTimer(CheckCredHashTicker, 10000)
    SetTimer(CheckBanStatusPeriodic, 10000)
    SetTimer(RefreshMasterKeyPeriodic, 10000)
}

RefreshMasterKeyPeriodic() {
    FetchMasterKeyFromManifest()
}

CheckCredHashTicker() {
    global SESSION_FILE
    if !FileExist(SESSION_FILE)
        return
    
    RefreshManifestAndLauncherBeforeLogin()
}

CheckBanStatusPeriodic() {
    if !ValidateNotBanned() {
        try DestroyLoginGui()
        ShowBanMessage()
    }
}

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
    
    if (status < 200 || status >= 300)
        throw Error("Worker error " status ": " resp)
    return resp
}

WorkerPostPublic(endpoint, bodyJson) {
    global WORKER_URL

    url := RTrim(WORKER_URL, "/") "/" LTrim(endpoint, "/")

    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Option[6] := 1
    req.SetTimeouts(15000, 15000, 15000, 15000)

    req.Open("POST", url, false)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetRequestHeader("User-Agent", "AHK-Vault")

    req.Send(bodyJson)

    status := req.Status
    resp := ""
    try resp := req.ResponseText

    if (status < 200 || status >= 300)
        throw Error("Worker error " status ": " resp)

    return resp
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

SendDiscordLogin(role, loginUser) {
    global DISCORD_WEBHOOK
    if (DISCORD_WEBHOOK = "")
        return

    ownerId := "898236174039138304"  ; OWNER DISCORD ID (hardcoded)
    did := ReadDiscordId()           ; Discord ID of the user logging in
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")

    ; Build message
    msg :=
        "<@" ownerId ">"                                  ; Ping owner
        . "`nLogin detected by <@" did ">"                ; Ping logging-in user
        . "`n"
        . "`nRole: " role
        . "`nDiscord ID: " did
        . "`nPC Name: " A_ComputerName
        . "`nWindows User: " A_UserName
        . "`nLogin Username: " loginUser
        . "`nTime: " ts

    DiscordWebhookPost(DISCORD_WEBHOOK, msg)
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
    }
}

RefreshManifestAndLauncherBeforeLogin() {
    global MANIFEST_URL, CRED_FILE, SESSION_FILE, LAST_CRED_HASH_FILE
    global DISCORD_BAN_FILE, ADMIN_DISCORD_FILE, DISCORD_WEBHOOK, HWID_BAN_FILE
    
    FetchMasterKeyFromManifest()
    
    tmp := A_Temp "\manifest.json"
    if !SafeDownload(MANIFEST_URL, tmp, 30000)
        return false
    
    json := ""
    try json := FileRead(tmp, "UTF-8")
    catch {
        return false
    }
    
    lists := ParseManifestLists(json)
    if IsObject(lists) {
        OverwriteListFile(DISCORD_BAN_FILE, lists.banned)
        OverwriteListFile(ADMIN_DISCORD_FILE, lists.admins)
        OverwriteListFile(HWID_BAN_FILE, lists.banned_hwids)
    }
    
    mf := ParseManifestForCredsAndLauncher(json)
    if !IsObject(mf)
        return false
    
    user := Trim(mf.cred_user)
    hash := Trim(mf.cred_hash)
    password := Trim(mf.cred_password)
    webhook := Trim(mf.webhook)
    
    if (webhook != "" && DISCORD_WEBHOOK = "") {
        DISCORD_WEBHOOK := webhook
        SaveAuthConfig()
    }
    
    if (user = "" || (hash = "" && password = ""))
        return false
    
    last := ""
    try {
        if FileExist(LAST_CRED_HASH_FILE)
            last := Trim(FileRead(LAST_CRED_HASH_FILE, "UTF-8"))
    } catch {
        last := ""
    }
    
    try {
        if FileExist(CRED_FILE)
            FileDelete CRED_FILE
        FileAppend user "|" hash "|" password, CRED_FILE
        Run 'attrib +h "' CRED_FILE '"', , "Hide"
    } catch {
    }
    
    if (last != "" && last != hash) {
        try FileDelete SESSION_FILE
    }
    
    try {
        if FileExist(LAST_CRED_HASH_FILE)
            FileDelete LAST_CRED_HASH_FILE
        FileAppend hash, LAST_CRED_HASH_FILE
        Run 'attrib +h "' LAST_CRED_HASH_FILE '"', , "Hide"
    } catch {
    }
    
    return true
}

ParseManifestForCredsAndLauncher(json) {
    obj := { cred_user: "", cred_hash: "", cred_password: "", webhook: "" }
    try {
        if RegExMatch(json, '"cred_user"\s*:\s*"([^"]+)"', &m1)
            obj.cred_user := m1[1]
        if RegExMatch(json, '"cred_hash"\s*:\s*"([^"]+)"', &m2)
            obj.cred_hash := m2[1]
        if RegExMatch(json, '"cred_password"\s*:\s*"([^"]+)"', &m3)
            obj.cred_password := m3[1]
        if RegExMatch(json, '"webhook"\s*:\s*"([^"]+)"', &m5)
            obj.webhook := m5[1]
    } catch {
        return false
    }
    return obj
}

ParseManifestLists(json) {
    obj := { banned: [], admins: [], banned_hwids: [] }

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

; ================= LOGIN GUI =================

CreateLoginGui() {
    global COLORS, gLoginGui
    
    RefreshManifestAndLauncherBeforeLogin()
    
    if IsDiscordBanned() {
        ShowBanMessage()
        ExitApp
    }
    
    gLoginGui := Gui("+AlwaysOnTop -MaximizeBox -MinimizeBox", "V1LN clan - Login")
    loginGui := gLoginGui
    
    loginGui.BackColor := COLORS.bg
    loginGui.SetFont("s10 c" COLORS.text, "Segoe UI")
    
    loginGui.Add("Text", "x0 y0 w550 h90 Background" COLORS.accent)
    
    title := loginGui.Add("Text", "x0 y25 w550 h40 Center c" COLORS.text " BackgroundTrans", "V1LN clan")
    title.SetFont("s22 bold")
    
    loginGui.Add("Text", "x75 y110 w400 h240 Background" COLORS.card)
    
    loginGui.Add("Text", "x95 y130 w360 c" COLORS.textDim " BackgroundTrans", "USERNAME")
    userEdit := loginGui.Add("Edit", "x95 y155 w360 h32 Background" COLORS.bgLight " c" COLORS.text)
    userEdit.SetFont("s10")
    
    loginGui.Add("Text", "x95 y200 w360 c" COLORS.textDim " BackgroundTrans", "PASSWORD")
    passEdit := loginGui.Add("Edit", "x95 y225 w360 h32 Password Background" COLORS.bgLight " c" COLORS.text)
    passEdit.SetFont("s10")
    
    btn := loginGui.Add("Button", "x95 y275 w360 h45 Background" COLORS.accent, "LOGIN →")
    btn.SetFont("s12 bold c" COLORS.text)
    btn.OnEvent("Click", (*) => AttemptLogin(userEdit, passEdit))
    
    loginGui.OnEvent("Close", (*) => ExitApp())
    loginGui.Show("w550 h410 Center")
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
        ShowBanMessage()
        return
    }
    
    username := Trim(usernameCtrl.Value)
    password := Trim(passwordCtrl.Value)
    
    if (username = "" || password = "") {
        MsgBox "Enter username and password.", "V1LN clan - Login", "Icon!"
        return
    }
    
    ; MASTER LOGIN
    if (StrLower(username) = StrLower(MASTER_USER) && password = MASTER_KEY) {
        attemptCount := 0
        CreateSession(MASTER_USER, "master")
        SendDiscordLogin("master", MASTER_USER)
        StartSessionWatchdog()
        DestroyLoginGui()
        LaunchMainApp()
        ExitApp
    }
    
    ; ADMIN LOGIN
    if (password = ADMIN_PASS && IsAdminDiscordId()) {
        attemptCount := 0
        CreateSession(username, "admin")
        SendDiscordLogin("admin", username)
        StartSessionWatchdog()
        DestroyLoginGui()
        LaunchMainApp()
        ExitApp
    }
    
    ; USER LOGIN
    try {
        credData := ""
        if FileExist(CRED_FILE)
            credData := FileRead(CRED_FILE, "UTF-8")
        
        if (credData = "")
            throw Error("Credential file is empty. Try restarting the script to refresh from manifest.")
        
        parts := StrSplit(credData, "|")
        
        if (parts.Length < 2)
            throw Error("Credential file format invalid.")
        
        storedUser := Trim(parts[1])
        storedHash := Trim(parts[2])
        storedPassword := (parts.Length >= 3) ? Trim(parts[3]) : ""
        
        if (storedPassword != "" && StrLower(username) = StrLower(storedUser) && password = storedPassword) {
            attemptCount := 0
            CreateSession(storedUser, "user")
            SendDiscordLogin("user", storedUser)
            StartSessionWatchdog()
            DestroyLoginGui()
            LaunchMainApp()
            ExitApp
        }
        
        if (storedHash != "") {
            enteredHash := HashPassword(password)
            if (StrLower(username) = StrLower(storedUser) && enteredHash = storedHash) {
                attemptCount := 0
                CreateSession(storedUser, "user")
                SendDiscordLogin("user", storedUser)
                StartSessionWatchdog()
                DestroyLoginGui()
                LaunchMainApp()
                ExitApp
            }
        }
        
        ; LOGIN FAILED
        attemptCount++
        remaining := MAX_ATTEMPTS - attemptCount
        
        if (remaining > 0) {
            MsgBox "Invalid login.`nAttempts remaining: " remaining, "V1LN clan - Login Failed", "Icon! 0x30"
            passwordCtrl.Value := ""
            passwordCtrl.Focus()
            return
        }
        
        if FileExist(LOCKOUT_FILE)
            FileDelete LOCKOUT_FILE
        FileAppend A_Now, LOCKOUT_FILE
        MsgBox "ACCOUNT LOCKED (too many failed attempts).", "V1LN clan - Lockout", "Icon! 0x10"
        ExitApp
        
    } catch as err {
        MsgBox "Login error:`n" err.Message, "V1LN clan - Error", "Icon!"
    }
}

IsAdminDiscordId() {
    global ADMIN_DISCORD_FILE
    did := StrLower(Trim(ReadDiscordId()))
    if (did = "")
        return false
    
    if !FileExist(ADMIN_DISCORD_FILE)
        return false
    
    try {
        txt := FileRead(ADMIN_DISCORD_FILE, "UTF-8")
        for line in StrSplit(txt, "`n") {
            if (StrLower(Trim(line)) = did)
                return true
        }
    }
    
    return false
}

; ================= MACRO LAUNCHER EXTRACTION =================

ExtractMacroLauncher() {
    global MACRO_LAUNCHER_PATH, SECURE_VAULT, MANIFEST_URL
    
    ; Download MacroLauncher from GitHub manifest
    tmpManifest := A_Temp "\manifest_launcher.json"
    
    if !SafeDownload(MANIFEST_URL, tmpManifest, 20000) {
        MsgBox(
            "❌ Failed to download manifest!`n`n"
            . "Cannot extract MacroLauncher without manifest.",
            "V1LN clan - Download Error",
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