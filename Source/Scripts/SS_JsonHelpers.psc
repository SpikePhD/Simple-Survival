; =========================
; SS_JsonHelpers.psc (new)
; Purpose: Safe getters for arrays from PapyrusUtil JSON.
; Requirements: SKSE64, PapyrusUtil SE 4.4+ (psc stubs on compile path)
; Attach: None (utility). Import where needed.
Scriptname SS_JsonHelpers
Import JsonUtil

String[] Function GetStringArraySafe(String file, String jpath) Global
    String[] arr = None
    If JsonUtil.CanResolvePath(file, jpath)
        arr = JsonUtil.PathStringElements(file, jpath)
    EndIf
    If arr == None
        arr = Utility.CreateStringArray(0)
    EndIf
    Return arr
EndFunction

Float[] Function GetFloatArraySafe(String file, String jpath) Global
    Float[] arr = None
    If JsonUtil.CanResolvePath(file, jpath)
        arr = JsonUtil.PathFloatElements(file, jpath)
    EndIf
    If arr == None
        arr = Utility.CreateFloatArray(0)
    EndIf
    Return arr
EndFunction

Int[] Function GetIntArraySafe(String file, String jpath) Global
    Int[] arr = None
    If JsonUtil.CanResolvePath(file, jpath)
        arr = JsonUtil.PathIntElements(file, jpath)
    EndIf
    If arr == None
        arr = Utility.CreateIntArray(0)
    EndIf
    Return arr
EndFunction
