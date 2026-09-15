param([string]$Name = 'current')
$ErrorActionPreference = 'Stop'
$qaRoot = $PSScriptRoot
$adbPath = 'D:\Android\Sdk\platform-tools\adb.exe'
Start-Sleep -Milliseconds 600
& $adbPath -s 3f2420aa shell uiautomator dump /sdcard/na2slna-qa-window.xml 2>$null | Out-Null
& $adbPath -s 3f2420aa pull /sdcard/na2slna-qa-window.xml "$qaRoot/window.xml" 2>$null | Out-Null
& $adbPath -s 3f2420aa exec-out screencap -p > "$qaRoot/screenshots/$Name.png"
[xml]$qaTree = Get-Content -LiteralPath "$qaRoot/window.xml"
$qaTree.SelectNodes('//node') | Where-Object { $_.'content-desc' -or $_.text -or $_.clickable -eq 'true' } | ForEach-Object {
  [pscustomobject]@{ Label = ($_.text + ' ' + $_.'content-desc').Trim().Replace("`n", ' | '); Bounds = $_.bounds; Class = $_.class; Clickable = $_.clickable; Checked = $_.checked }
} | ConvertTo-Json -Compress
