; =========================
; SS_JsonHelpers.psc (new)
; Purpose: Safe getters for arrays from PapyrusUtil JSON.
; Requirements: SKSE64, PapyrusUtil SE 4.4+ (psc stubs on compile path)
; Attach: None (utility). Import where needed.
Scriptname SS_JsonHelpers

String[] Function GetStringArraySafe(String file, String jpath) Global
    String[] arr = None
    If JsonUtil.PathExists(file, jpath)
        arr = JsonUtil.GetStringArray(file, jpath)
    EndIf
    If arr == None
        arr = new String[0]
    EndIf
    Return arr
EndFunction

Float[] Function GetFloatArraySafe(String file, String jpath) Global
    Float[] arr = None
    If JsonUtil.PathExists(file, jpath)
        arr = JsonUtil.GetFloatArray(file, jpath)
    EndIf
    If arr == None
        arr = new Float[0]
    EndIf
    Return arr
EndFunction

Int[] Function GetIntArraySafe(String file, String jpath) Global
    Int[] arr = None
    If JsonUtil.PathExists(file, jpath)
        arr = JsonUtil.GetIntArray(file, jpath)
    EndIf
    If arr == None
        arr = new Int[0]
    EndIf
    Return arr
EndFunction
