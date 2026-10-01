# ROG Armoury Crate H-2004 diagnostics

This repository documents a reproducible Windows diagnosis for Armoury Crate H-2004 when ASUS ROG keyboard and mouse HID devices still work in Windows.

## What happened

The affected devices were visible to Windows as healthy HID/PnP devices:

- ROG FALCHION ACE HFX: VID/PID `0B05:1B7E` (device model PID `7038`)
- ROG HARPE ACE AIM LAB EDITION: VID/PID `0B05:1A92` (device model PID `6802`)

Armoury Framework logs showed `Rejected request from untrusted process: ...\\verge-mihomo.exe`, followed by `launchService failed: 6802/7038` and `F-1034`. Armoury maps H-2004 to `DEVICE_SERVICE_NOT_FOUND`; the devices themselves were alive and had no Windows PnP problem code.

The local HTTP proxy was `127.0.0.1:7897`, while local ASUS traffic was not consistently bypassing the proxy. Setting user-level `NO_PROXY`/`no_proxy` for loopback addresses and restarting the user-mode Armoury SocketServer/Framework processes restored both device services. After recovery, both services returned `result=true` and `isDeviceAlive=true`.

This is a community diagnostic aid, not an ASUS product or support tool.

## Safe use

Run PowerShell as the affected user. The default fix only changes loopback proxy bypass variables and does not flash firmware, remove drivers, change BIOS, or reboot Windows.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\src\Fix-RogH2004Proxy.ps1 -RestartArmouryProcesses
```

An administrator may additionally apply a system WinHTTP bypass. Use this only when the local machine intentionally uses `127.0.0.1:7897` as its proxy:

```powershell
.\src\Fix-RogH2004Proxy.ps1 -ApplyWinHttpBypass
```

The script refuses that switch unless PowerShell is elevated. It never runs a firmware updater.

## Diagnostics

Collect stages independently; output is written below the script directory and should stay local:

```powershell
.\src\Collect-RogH2004Diagnostics.ps1 -Stage System
.\src\Collect-RogH2004Diagnostics.ps1 -Stage Pnp
.\src\Collect-RogH2004Diagnostics.ps1 -Stage Events
.\src\Collect-RogH2004Diagnostics.ps1 -Stage Files
python .\src\Inspect-RogArmouryBundle.py
```

Do not commit generated evidence. It can contain computer names, usernames, install paths, event messages, serial numbers, and local proxy details. The repository ignores the evidence directory for this reason.

## Firmware boundary

Do not use a firmware package unless the exact model, VID/PID, current version, target version, and official ASUS source have all been verified. The scripts in this repository do not perform firmware operations.

## License

MIT. See [LICENSE](LICENSE).
