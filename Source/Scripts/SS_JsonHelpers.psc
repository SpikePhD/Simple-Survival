Scriptname SS_JsonHelpers Hidden

; Returns [] (length 0) if jsonPath is missing/empty.
String[] Function GetStringArraySafe(String filePath, String jsonPath) Global
	int n = JsonUtil.PathCount(filePath, jsonPath)
	if n <= 0
		return Utility.CreateStringArray(0)
	endif

	String[] out = Utility.CreateStringArray(n)
	int i = 0
	while i < n
		String idxPath = jsonPath + "[" + ("" + i) + "]"
		out[i] = JsonUtil.GetPathStringValue(filePath, idxPath, "")
		i += 1
	endWhile
	return out
EndFunction

; Returns [] (length 0) if jsonPath is missing/empty.
Float[] Function GetFloatArraySafe(String filePath, String jsonPath) Global
	int n = JsonUtil.PathCount(filePath, jsonPath)
	if n <= 0
		return Utility.CreateFloatArray(0)
	endif

	Float[] out = Utility.CreateFloatArray(n)
	int i = 0
	while i < n
		String idxPath = jsonPath + "[" + ("" + i) + "]"
		out[i] = JsonUtil.GetPathFloatValue(filePath, idxPath, 0.0)
		i += 1
	endWhile
	return out
EndFunction
