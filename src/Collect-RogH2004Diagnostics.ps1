param([ValidateSet('System','Pnp','Events','Files')][string]$Stage)
$ErrorActionPreference = 'Continue'
$outDir = Join-Path $PSScriptRoot 'rog-h2004-evidence'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
function Save-Data($name, $data) { $data | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $outDir $name) -Encoding UTF8 }
$brand = 'ASUS|ASUSTeK|Armoury|\bROG\b|\bAURA\b|LightingService|\bAac[A-Z]\w*|ENE RGB|Patriot.*RGB'
if ($Stage -eq 'System') {
  $os = Get-CimInstance Win32_OperatingSystem
  $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
  $services = @(Get-CimInstance Win32_Service | Where-Object { ($_.Name+' '+$_.DisplayName+' '+$_.PathName) -match $brand } | ForEach-Object {
    $s = $_; $reg = Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\'+$s.Name) -ErrorAction SilentlyContinue
    $exe = if ($s.PathName -match '^\s*"([^"\r\n]+)"') { $matches[1] } elseif ($s.PathName -match '^\s*(.*?\.exe)\b') { $matches[1] } else { $s.PathName }
    $exe = [Environment]::ExpandEnvironmentVariables($exe)
    $file = Get-Item -LiteralPath $exe -ErrorAction SilentlyContinue
    [pscustomobject]@{Name=$s.Name;DisplayName=$s.DisplayName;State=$s.State;StartMode=$s.StartMode;DelayedAutoStart=$reg.DelayedAutoStart;StartName=$s.StartName;ProcessId=$s.ProcessId;PathName=$s.PathName;Executable=$exe;Exists=[bool]$file;FileVersion=$file.VersionInfo.FileVersion;Modified=$file.LastWriteTime;Dependencies=@($reg.DependOnService)}
  })
  $packages = @(foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) { Get-ItemProperty ($root+'\*') -ErrorAction SilentlyContinue | Where-Object { ($_.DisplayName+' '+$_.Publisher) -match $brand } | Select-Object DisplayName,DisplayVersion,Publisher,InstallDate,InstallLocation,InstallSource,UninstallString,ModifyPath,PSPath })
  $appx = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { ($_.Name+' '+$_.Publisher) -match 'ASUS|Armoury|ROG|AURA' } | Select-Object Name,Version,PackageFullName,InstallLocation,Status)
  $processes = @(Get-CimInstance Win32_Process | Where-Object { ($_.Name+' '+$_.ExecutablePath) -match $brand+'|firmware|fwupdate' } | Select-Object Name,ProcessId,ParentProcessId,ExecutablePath,CreationDate)
  $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { ($_.TaskName+' '+$_.TaskPath) -match $brand } | Select-Object TaskName,TaskPath,State)
  $data = [pscustomobject]@{CollectedAt=(Get-Date).ToString('o');OS=[pscustomobject]@{Caption=$os.Caption;Version=$os.Version;BuildNumber=$os.BuildNumber;DisplayVersion=$cv.DisplayVersion;UBR=$cv.UBR;LastBootUpTime=$os.LastBootUpTime;Architecture=$os.OSArchitecture};Services=$services;Packages=$packages;Appx=$appx;Processes=$processes;Tasks=$tasks}
  Save-Data '01-system.json' $data
  [pscustomobject]@{OS=$data.OS;Services=$services;Packages=@($packages | Select-Object DisplayName,DisplayVersion,InstallLocation);Appx=$appx;Processes=$processes;Tasks=$tasks} | ConvertTo-Json -Depth 6
}
if ($Stage -eq 'Pnp') {
  $drivers = @()
  $devices = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPClass -in @('Keyboard','Mouse','HIDClass','USB') -or ($_.Name+' '+($_.HardwareID -join ' ')) -match 'ASUS|ROG|VID_0B05' } | ForEach-Object {
    $d = $_
    $vidpid = if (($d.PNPDeviceID+' '+($d.HardwareID -join ' ')) -match '(?i)VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') { $matches[1]+':'+$matches[2] } else { $null }
    [pscustomobject]@{FriendlyName=$d.Name;Class=$d.PNPClass;InstanceId=$d.PNPDeviceID;Status=$d.Status;Present=$d.Present;ConfigManagerErrorCode=$d.ConfigManagerErrorCode;HardwareIds=@($d.HardwareID);CompatibleIds=@($d.CompatibleID);VID_PID=$vidpid;Service=$d.Service;Manufacturer=$d.Manufacturer;Driver=@()}
  })
  $pnpList = @($devices | Where-Object Present | Select-Object Class,FriendlyName,InstanceId,Status,@{n='Problem';e={$_.ConfigManagerErrorCode}})
  Save-Data '02-pnp.json' ([pscustomobject]@{CollectedAt=(Get-Date).ToString('o');Devices=$devices;PresentDevices=$pnpList;Properties=@()})
  [pscustomobject]@{Count=$devices.Count;ClassSummary=@($devices | Group-Object Class | Select-Object Name,Count);Problems=@($devices | Where-Object ConfigManagerErrorCode -ne 0);AsusDevices=@($devices | Where-Object VID_PID -like '0B05:*' | Select-Object FriendlyName,Class,Status,ConfigManagerErrorCode,VID_PID)} | ConvertTo-Json -Depth 4
}
if ($Stage -eq 'Events') {
  $since = (Get-Date).AddHours(-24)
  $names = @('Application','System')
  $meta = @(foreach ($pattern in @('*DriverFrameworks-UserMode*','*Kernel-PnP*','*DeviceSetupManager*')) { Get-WinEvent -ListLog $pattern -ErrorAction SilentlyContinue | Select-Object LogName,IsEnabled,RecordCount,LogMode })
  $names += @($meta | Where-Object IsEnabled | Select-Object -ExpandProperty LogName)
  $errors = @(); $events = @(foreach ($name in ($names | Select-Object -Unique)) { try { $found = @(Get-WinEvent -FilterHashtable @{LogName=$name;StartTime=$since;Level=@(1,2,3)} -MaxEvents 2500 -ErrorAction Stop); foreach ($e in $found) { if ($name -notin @('Application','System') -or ($e.ProviderName+' '+$e.Message) -match 'ASUS|Armoury|ROG|AURA|LightingService|\bHID\b|\bUSB\b|firmware|device install|0B05|Aac|Framework') { [pscustomobject]@{TimeCreated=$e.TimeCreated.ToString('o');LogName=$e.LogName;Provider=$e.ProviderName;Id=$e.Id;Level=$e.LevelDisplayName;RecordId=$e.RecordId;Message=$e.Message} } } } catch { $errors += [pscustomobject]@{LogName=$name;Error=$_.Exception.Message} } })
  Save-Data '03-events.json' ([pscustomobject]@{Since=$since.ToString('o');LogMetadata=$meta;Events=$events;QueryErrors=$errors})
  [pscustomobject]@{LogMetadata=$meta;QueryErrors=$errors;Count=$events.Count;Events=@($events | Sort-Object TimeCreated -Descending | Select-Object -First 45)} | ConvertTo-Json -Depth 6
}
if ($Stage -eq 'Files') {
  $parents = @($env:ProgramData,$env:LOCALAPPDATA,$env:APPDATA,$env:ProgramFiles,${env:ProgramFiles(x86)}) | Select-Object -Unique
  $roots = @(foreach ($parent in $parents) { Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue | Where-Object Name -match 'ASUS|Armoury|\bROG\b|AURA|LightingService|^ENE|Patriot' | Select-Object -ExpandProperty FullName })
  $roots += @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -ErrorAction SilentlyContinue | Where-Object Name -match 'ASUS|Armoury|ROG|AURA' | Select-Object -ExpandProperty FullName)
  $roots = @($roots | Select-Object -Unique)
  $files = @(foreach ($root in $roots) { Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue | Select-Object FullName,Length,Extension,LastWriteTime,CreationTime })
  Save-Data '04-files.json' ([pscustomobject]@{Roots=$roots;Files=$files})
  [pscustomobject]@{Roots=$roots;FileCount=$files.Count;RecentFiles=@($files | Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-3) -and ($_.Extension -match '\.(log|txt|json|xml|ini|db|sqlite|zip|etl)$' -or $_.FullName -match 'firmware|fwupdate|HAL|SDK') } | Sort-Object LastWriteTime -Descending | Select-Object -First 12)} | ConvertTo-Json -Depth 5
}
