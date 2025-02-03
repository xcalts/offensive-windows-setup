function activateWindowsAndOffice {
    Write-Host "[o] Activating Windows using `mass grave [.] dev`." -ForegroundColor Yellow
    & ([ScriptBlock]::Create((Invoke-RestMethod https://get.activated.win))) /HWID /Ohook
    Write-Host "    [v] Windows was activated successfully." -ForegroundColor Green
}

function makeSureRunningAsAdmin {
    Write-Host "[o] Checking if the script runs with administrative privileges." -ForegroundColor Yellow
    
    # Create a new principal object representing the current user
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    
    # Check if the current user is in the Administrator role
    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        # If not running as Administrator, output a message and exit
        Write-Host "    [!] This script requires administrator privileges. Please run it as an administrator." -ForegroundColor Red
        
        # Optionally, you can add a pause here if running from double-click to see the message
        Pause
        exit
    }

    Write-Host "    [v] Running with administrative privileges." -ForegroundColor Green
}

function setupBackground {
    Write-Host "[o] Setting up the background." -ForegroundColor Yellow

    $R = 128
    $G = 0
    $B = 64
    
    $code = @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using Microsoft.Win32;
    
    
namespace CurrentUser
{
    public class Desktop
    {
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern int SystemParametersInfo(int uAction, int uParm, string lpvParam, int fuWinIni);
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern int SetSysColors(int cElements, int[] lpaElements, int[] lpRgbValues);
        public const int UpdateIniFile = 0x01;
        public const int SendWinIniChange = 0x02;
        public const int SetDesktopBackground = 0x0014;
        public const int COLOR_DESKTOP = 1;
        public int[] first = {COLOR_DESKTOP};
    
    
        public static void RemoveWallPaper()
        {
            SystemParametersInfo( SetDesktopBackground, 0, "", SendWinIniChange | UpdateIniFile );
            RegistryKey regkey = Registry.CurrentUser.OpenSubKey("Control Panel\\Desktop", true);
            regkey.SetValue(@"WallPaper", 0);
            regkey.Close();
        }
    
        public static void SetBackground(byte r, byte g, byte b)
        {
            int[] elements = {COLOR_DESKTOP};
    
            RemoveWallPaper();
            System.Drawing.Color color = System.Drawing.Color.FromArgb(r,g,b);
            int[] colors = { System.Drawing.ColorTranslator.ToWin32(color) };
    
            SetSysColors(elements.Length, elements, colors);
            RegistryKey key = Registry.CurrentUser.OpenSubKey("Control Panel\\Colors", true);
            key.SetValue(@"Background", string.Format("{0} {1} {2}", color.R, color.G, color.B));
            key.Close();
        }
    }
}  
"@

    try {
        Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing.dll 
    }
    catch {
        # An error is thrown if the type [CurrentUser.Desktop] is already created
        # so we ignore it.
    }
    finally {
        [CurrentUser.Desktop]::SetBackground($R, $G, $B)
    }

    Write-Host "    [v] Background color was set successfully." -ForegroundColor Green
}

function copyIconsToPictures {
    Write-Host "[o] Copying the icons to the ~/Pictures/ folder." -ForegroundColor Yellow

    # Define the source and target directories
    $sourcePath = ".\icons\*"
    $picturesPath = [System.Environment]::GetFolderPath('MyPictures')

    # Check if the target directory exists, if not, create it
    if (-not (Test-Path -Path $picturesPath)) {
        New-Item -Path $picturesPath -ItemType Directory | Out-Null
    }

    # Copy all the icons to the Pictures folder and print each file name
    Get-ChildItem -Path $sourcePath -File | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $picturesPath
        Write-Host "    [+] $($_.Name)" -ForegroundColor Blue
    }

    Write-Host "    [v] Finished copying successfully." -ForegroundColor Green
}

function setupDesktopFolders {
    function Set-FolderIcon {
        [CmdletBinding()]
        param
        (
            [Parameter(Mandatory = $True, Position = 0)]
            [string[]]$Icon,
    
            [Parameter(Mandatory = $True, Position = 1)]
            [string]$Path,
    
            [Parameter(Mandatory = $False)]
            [switch]$Recurse
        )
        BEGIN {
            $originallocale = $PWD
            # Creating content of the DESKTOP.INI file.
            $ini = @"
    [.ShellClassInfo]
    IconFile=FOLDER.ICO
    IconIndex=0
    ConfirmFileOp=0
"@
            Set-Location $Path
            Set-Location ..
            Get-ChildItem | Where-Object { $_.FullName -eq "$Path" } | ForEach-Object { $_.Attributes = 'Directory, System' }
        }
        PROCESS {
            # Check if desktop.ini exists
            $desktopIniPath = Join-Path -Path $Path -ChildPath "desktop.ini"
            $iconFilePath = Join-Path -Path $Path -ChildPath "FOLDER.ICO"
    
            # Ensure desktop.ini is created or updated
            try {
                if (-not (Test-Path -Path $desktopIniPath)) {
                    $ini | Out-File -FilePath $desktopIniPath -Force
                }
                else {
                    Set-Content -Path $desktopIniPath -Value $ini -Force
                }
            }
            catch {
                Write-Host "    [!] Failed to create or update desktop.ini in $Path - $_" -ForegroundColor Red
            }
    
            # Copy the icon file
            try {
                Copy-Item -Path $Icon -Destination $iconFilePath -Force
            }
            catch {
                Write-Host "    [!] Failed to copy icon file to $Path - $_" -ForegroundColor Red
            }
    
            if ($Recurse -eq $True) {
                $recursePath = Get-ChildItem $Path -Recurse | Where-Object { $_.Attributes -match "Directory" }
                foreach ($folder in $recursePath) {
                    Set-FolderIcon -Icon $Icon -Path $folder.FullName
                }
            }
        }
        END {
            # Safely set attributes if files exist
            try {
                if (Test-Path -Path $desktopIniPath) {
                    $inifile = Get-Item $desktopIniPath
                    $inifile.Attributes = 'Hidden'
                }
                else {
                    Write-Host "    [!] desktop.ini does not exist in $Path, skipping attribute setting." -ForegroundColor Yellow
                }
    
                if (Test-Path -Path $iconFilePath) {
                    $icofile = Get-Item $iconFilePath
                    $icofile.Attributes = 'Hidden'
                }
                else {
                    Write-Host "    [!] Icon file does not exist in $Path, skipping attribute setting." -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "    [!] Failed to set attributes in $Path - $_" -ForegroundColor Red
            }
    
            Set-Location $originallocale
        }
    }
    
    Write-Host "[o] Setting up the desktop folders." -ForegroundColor Yellow

    # Define the desktop folders and their icons
    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $folders = @(
        @{Name = "Projects"; Icon = "$HOME\Pictures\projects.ico" },
        @{Name = "Data"; Icon = "$HOME\Pictures\data.ico" },
        @{Name = "Extras"; Icon = "$HOME\Pictures\extras.ico" },
        @{Name = "RDP"; Icon = "$HOME\Pictures\rdp.ico" },
        @{Name = "Repos"; Icon = "$HOME\Pictures\repos.ico" },
        @{Name = "Tools"; Icon = "$HOME\Pictures\tool-box.ico" },
        @{Name = "Lab"; Icon = "$HOME\Pictures\virus.ico" }
    )

    # Create the folders on the desktop if they do not exist and set their icons
    $folders | ForEach-Object {
        # if the folder exist continue
        if (Test-Path -Path $desktopPath\$($_.Name)) {
            Write-Host "    [!] Folder already exists: $($_.Name)" -ForegroundColor Yellow
            return
        }

        $folderPath = Join-Path -Path $desktopPath -ChildPath $_.Name
        if (-not (Test-Path -Path $folderPath)) {
            try {
                New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
                Write-Host "    [+] Created folder: $_.Name" -ForegroundColor Blue
            }
            catch {
                Write-Host "    [x] Failed to create folder: $_.Name - $_" -ForegroundColor Red
                return
            }
        }

        # Verify the icon file exists
        $iconPath = $_.Icon
        if (-not (Test-Path -Path $iconPath)) {
            Write-Host "    [x] Icon file not found: $iconPath for $_.Name" -ForegroundColor Red
            return
        }

        # Use Set-FolderIcon to set the folder icon
        try {
            Set-FolderIcon -Icon $iconPath -Path $folderPath
            Write-Host "    [v] Set icon for folder: $_.Name" -ForegroundColor Green
        }
        catch {
            Write-Host "    [x] Failed to set icon for folder: $_.Name - $_" -ForegroundColor Red
        }
    }

    Write-Host "    [v] Desktop folders were configured successfully." -ForegroundColor Green
}

function downloadChoco {
    # Follow instructions at https://chocolatey.org/install
    Write-Host "[o] Setting up Chocolatey installation." -ForegroundColor Yellow
    
    Set-ExecutionPolicy Bypass -Scope Process -Force | Out-Null
    
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')) 4>$null 3>$null | Out-Null 
    
    Write-Host "    [v] Chocolatey was installed successfully." -ForegroundColor Green
}

function installChocoPackages {
    Write-Host "[o] Installing the Chocolatey packages." -ForegroundColor Yellow

    Write-Host "    [+] dnspy" -ForegroundColor Blue
    choco install dnspy --pre -y | Out-Null

    Write-Host "    [+] reshack" -ForegroundColor Blue
    choco install reshack --pre -y | Out-Null

    Write-Host "    [+] x64dbg.portable" -ForegroundColor Blue
    choco install x64dbg.portable --pre -y | Out-Null

    Write-Host "    [+] pebear" -ForegroundColor Blue
    choco install pebear --pre -y | Out-Null

    Write-Host "    [+] processhacker" -ForegroundColor Blue
    choco install processhacker --pre -y | Out-Null

    Write-Host "    [+] visualstudio2022community" -ForegroundColor Blue
    choco install visualstudio2022community --pre -y | Out-Null
    Write-Host "        [i] You should install more features using the 'Visual Studio Installer'." -ForegroundColor Magenta

    Write-Host "    [+] microsoft-windows-terminal" -ForegroundColor Blue
    choco install microsoft-windows-terminal --pre -y | Out-Null

    Write-Host "    [+] git" -ForegroundColor Blue
    choco install git -y | Out-Null

    Write-Host "    [+] nodejs" -ForegroundColor Blue
    choco install nodejs -y | Out-Null
    Write-Host "        [i] You should instal TLDR as well: 'npm install -g tldr'." -ForegroundColor Magenta
    
    Write-Host "    [+] vscode" -ForegroundColor Blue
    choco install vscode -y | Out-Null
    
    Write-Host "    [+] 7zip" -ForegroundColor Blue
    choco install 7zip --pre -y | Out-Null
    
    Write-Host "    [+] python3" -ForegroundColor Blue
    Write-Host "        [i] You should run 'pip install virtualenv' as well." -ForegroundColor Magenta
    choco install python -y | Out-Null
    
    Write-Host "    [+] firefox" -ForegroundColor Blue
    choco install firefox -y | Out-Null
    
    Write-Host "    [+] googlechrome" -ForegroundColor Blue
    choco install googlechrome -y | Out-Null
    
    Write-Host "    [+] openvpn-connect" -ForegroundColor Blue
    choco install openvpn-connect -y | Out-Null
    
    Write-Host "    [+] openjdk-21" -ForegroundColor Blue
    choco install openjdk --version=21.0.0 -y | Out-Null

    Write-Host "    [+] ghidra" -ForegroundColor Blue
    choco install ghidra -y | Out-Null

    Write-Host "    [+] intellij-idea (community)" -ForegroundColor Blue
    choco install intellijidea-community -y | Out-Null
    
    Write-Host "    [+] sysinternals" -ForegroundColor Blue
    choco install sysinternals -y --params "/InstallDir:$env:USERPROFILE\Desktop\Tools\sysinternals" | Out-Null
    
    Write-Host "    [+] wireshark" -ForegroundColor Blue
    choco install wireshark -y | Out-Null
    
    Write-Host "    [+] cloc" -ForegroundColor Blue
    choco install cloc -y | Out-Null
    
    Write-Host "    [+] greenshot" -ForegroundColor Blue
    Write-Host "        [i] You can set 'CTRL+SHIFT+S' as the capture window action by going to 'Preferences->Settings->Capture Region'." -ForegroundColor Magenta
    Write-Host "        [i] Enable the options to always redirect output to clipboard at 'Preferences->Settings->Destination->Copy to cliboard'." -ForegroundColor Magenta
    choco install -y greenshot --installargs "/LANG=en /NOICONS /COMPONENTS='greenshot,plugins\office,plugins\ocr,plugins\externalcommand'"  | Out-Null
    
    Write-Host "    [+] nerd-fonts-firacode" -ForegroundColor Blue
    choco install nerd-fonts-firacode -y | Out-Null
    
    Write-Host "    [+] oh-my-posh" -ForegroundColor Blue
    choco install oh-my-posh -y | Out-Null

    Write-Host "    [+] winscp" -ForegroundColor Blue
    choco install winscp -y | Out-Null

    Write-Host "    [v] Chocolatey packages were installed successfully." -ForegroundColor Green
}

function upgradeChocoPackages {
    Write-Host "[o] Upgrading all the Chocolatey packages." -ForegroundColor Yellow
    choco upgrade all -y | Out-Null
    Write-Host "    [v] Chocolatey packages were upgraded successfully." -ForegroundColor Green
}

function setupOhMyPsh {
    Write-Host "[o] Setting up the Oh My Psh configuration." -ForegroundColor Yellow
    
    Write-Host "    [+] Create the profile if it doesn't exist" -ForegroundColor Blue
    if (!(Test-Path -Path $PROFILE)) {
        New-Item -Path $PROFILE -Type File -Force | Out-Null
        Write-Host "    [+] Add Oh My Posh initialization to the profile" -ForegroundColor Blue
        Add-Content -Path $PROFILE -Value 'oh-my-posh init pwsh | Invoke-Expression'
    }

    Write-Host "    [v] Oh My Posh has been successfully installed and configured." -ForegroundColor Green
}

function installVSCodeExtensions {
    Write-Host "[o] Installing VSCode extensions." -ForegroundColor Yellow

    Write-Host "    [=] C#" -ForegroundColor White
    Write-Host "    [+] ms-dotnettools.csdevkit" -ForegroundColor Blue
    code --install-extension ms-dotnettools.csdevkit | Out-Null

    Write-Host "    [=] Python" -ForegroundColor White
    Write-Host "    [+] ms-python.python" -ForegroundColor Blue
    code --install-extension ms-python.python | Out-Null
    Write-Host "    [+] kevinrose.vsc-python-indent" -ForegroundColor Blue
    code --install-extension kevinrose.vsc-python-indent | Out-Null
    Write-Host "    [+] ms-python.black-formatter" -ForegroundColor Blue
    code --install-extension ms-python.black-formatter | Out-Null
    Write-Host "    [+] njpwerner.autodocstring" -ForegroundColor Blue
    code --install-extension njpwerner.autodocstring | Out-Null
    
    Write-Host "    [=] Source Code Review" -ForegroundColor White
    Write-Host "    [+] ezforo.copy-relative-path-and-line-numbers" -ForegroundColor Blue
    code --install-extension ezforo.copy-relative-path-and-line-numbers | Out-Null
    Write-Host "    [+] streetsidesoftware.code-spell-checker" -ForegroundColor Blue
    code --install-extension streetsidesoftware.code-spell-checker | Out-Null  
    Write-Host "    [+] gruntfuggly.todo-tree" -ForegroundColor Blue
    code --install-extension gruntfuggly.todo-tree | Out-Null 
    Write-Host "    [+] dabolus.uncanny-cognitive-complexity" -ForegroundColor Blue
    code --install-extension dabolus.uncanny-cognitive-complexity | Out-Null
    
    Write-Host "    [=] Powershell" -ForegroundColor White
    Write-Host "    [+] ms-vscode.powershell" -ForegroundColor Blue
    code --install-extension ms-vscode.powershell | Out-Null

    Write-Host "    [=] ReactJS - Typescript" -ForegroundColor White
    Write-Host "    [+] esbenp.prettier-vscode" -ForegroundColor Blue
    code --install-extension esbenp.prettier-vscode | Out-Null
    Write-Host "    [+] dsznajder.es7-react-js-snippets" -ForegroundColor Blue
    code --install-extension dsznajder.es7-react-js-snippets | Out-Null
    Write-Host "    [+] msjsdiag.vscode-react-native" -ForegroundColor Blue
    code --install-extension msjsdiag.vscode-react-native | Out-Null

    Write-Host "    [=] Misc" -ForegroundColor White
    Write-Host "    [+] tomoki1207.pdf" -ForegroundColor Blue
    code --install-extension tomoki1207.pdf | Out-Null
    Write-Host "    [+] pkief.material-icon-theme" -ForegroundColor Blue
    code --install-extension pkief.material-icon-theme | Out-Null  
    Write-Host "    [+] dracula-theme.theme-dracula" -ForegroundColor Blue
    code --install-extension dracula-theme.theme-dracula | Out-Null 
    Write-Host "    [+] mechatroner.rainbow-csv" -ForegroundColor Blue
    code --install-extension mechatroner.rainbow-csv | Out-Null
    Write-Host "    [+] ms-vscode-remote.remote-ssh" -ForegroundColor Blue
    code --install-extension ms-vscode-remote.remote-ssh | Out-Null
    
    Write-Host "    [v] VSCode extensions were installed successfully." -ForegroundColor Green
}

function createToolsDesktopShortcuts {
    function createDesktopShortcut {
        param (
            [Parameter(Mandatory = $true)]
            [string]$ExecutablePath
        )
        
        $desktopPath = [System.Environment]::GetFolderPath('Desktop')
        $toolsPath = Join-Path -Path $desktopPath -ChildPath "Tools"

        # Check if the "Tools" directory exists, if not, create it
        if (-not (Test-Path -Path $toolsPath)) {
            New-Item -Path $toolsPath -ItemType Directory | Out-Null
        }

        $shortcutPath = -join ($toolsPath, "\", $(Get-Item $ExecutablePath).Name.Replace('.exe', ''), ".lnk")

        # Create a shortcut in the "Tools" directory on the desktop if it does not exist
        if (-not (Test-Path $shortcutPath)) {
            $wshShell = New-Object -ComObject WScript.Shell
            $shortcut = $wshShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $ExecutablePath
            $shortcut.Save()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wshShell) | Out-Null
        }
    }

    Write-Host "[o] Creating the tools' desktop shortcuts." -ForegroundColor Yellow

    Write-Host "    [+] firefox " -ForegroundColor Blue
    createDesktopShortcut -ExecutablePath "C:\Program Files\Mozilla Firefox\Firefox.exe"
    
    Write-Host "    [+] msedge" -ForegroundColor Blue
    createDesktopShortcut -ExecutablePath "C:\Program Files (x86)\Microsoft\Edge\Application\MSedge.exe"
    
    Write-Host "    [+] openvpn-connect" -ForegroundColor Blue
    createDesktopShortcut -ExecutablePath "C:\Program Files\OpenVPN Connect\OpenVPNConnect.exe"
    
    Write-Host "    [+] code" -ForegroundColor Blue
    createDesktopShortcut -ExecutablePath "C:\Program Files\Microsoft VS Code\Code.exe"

    Write-Host "    [+] visual-studio" -ForegroundColor Blue
    createDesktopShortcut -ExecutablePath "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"

    Write-Host "    [+] processhacker" -ForegroundColor Blue
    createDesktopShortcut -ExecutablePath "C:\Program Files\Process Hacker 2\ProcessHacker.exe"

    Write-Host "    [+] pebear" -ForegroundColor Blue
    createDesktopShortcut -ExecutablePath "C:\ProgramData\chocolatey\bin\PE-bear.exe"
    
    Write-Host "    [+] winscp" -ForegroundColor Blue
    createDesktopShortcut -ExecutablePath "C:\Program Files (x86)\WinSCP\WinSCP.exe"

    Write-Host "    [v] Tools' desktop shortcuts were installed successfully." -ForegroundColor Green 
}

function setupFirefox {
    Write-Host "[o] Setting up firefox." -ForegroundColor Yellow
    Write-Host "    [i] Consider importing the FoxyProxy profiles post installation." -ForegroundColor Magenta

    # Set the default path for Firefox installation. Adjust as necessary for different environments or Firefox versions.
    $distributionPath = "C:\Program Files\Mozilla Firefox\distribution"

    # Create the distribution directory if it does not exist
    if (-not (Test-Path $distributionPath)) {
        New-Item -Path $distributionPath -ItemType Directory
    }

    # Define the source file path
    $sourceFile = Join-Path -Path (Get-Location) -ChildPath "configurations\firefox-policies.json"

    # Check if the policies.json file exists in the current directory
    if (-not (Test-Path $sourceFile)) {
        Write-Host "    [!] policies.json not found in the current directory." -ForegroundColor Green
        return
    }

    # Copy the policies.json file to the Firefox distribution directory
    try {
        Copy-Item -Path $sourceFile -Destination $distributionPath -Force
        Write-Host "    [+] policies.json has been successfully copied to: $distributionPath" -ForegroundColor Blue
    }
    catch {
        Write-Host "    [!] Failed to copy policies.json: $_" -ForegroundColor Red
    }

    Write-Host "    [v] Firefox setup completed successfully." -ForegroundColor Green
}

function createShortcutForHostsFile {
    Write-Host "[o] Creating shortcut for hosts file." -ForegroundColor Yellow

    # Define the path to the hosts file
    $hostsFilePath = "C:\Windows\System32\drivers\etc\hosts"

    # Define the path for the shortcut on the desktop
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path -Path $desktopPath -ChildPath "Hosts File Shortcut.lnk"

    # Create a new WScript.Shell COM object
    $shell = New-Object -ComObject WScript.Shell

    # Create the shortcut
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $hostsFilePath
    $shortcut.Description = "Shortcut to the hosts file"
    $shortcut.Save()

    # Clean up COM object
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    Remove-Variable shell

    Write-Host "    [v] Shortcut created on Desktop." -ForegroundColor Green
}

function installWSL {
    Write-Host "[o] Installing the Windows Subsystem for Linux." -ForegroundColor Yellow
    Write-Host "    [i] when running in a VM, you will need to enable the Nested Virualization feature." -ForegroundColor Magenta
    Write-Host '    [i] in Hyper-V, use "Set-VMProcessor -VMName <VMName> -ExposeVirtualizationExtensions $true" command.' -ForegroundColor Magenta
    Write-Host '    [i] when you launch it for the first time, you might want to run "sudo apt-get upgrade && sudo apt-get update".' -ForegroundColor Magenta
    wsl --install --no-launch | Out-Null
    Write-Host "    [v] WSL was installed successfully." -ForegroundColor Green   
}

function setupDefenderExcludedFolder {
    Write-Host "[o] Adding a Microsoft-Defender exclusion for ~/Lab." -ForegroundColor Yellow

    Add-MpPreference -ExclusionPath "C:\Users\user\Desktop\Lab"

    Write-Host "    [v] The exclusion was added successfully." -ForegroundColor Green
}

function permanentlyDisableRealTimeProtection {
    Write-Host "[o] Permanently disable real time protection." -ForegroundColor Yellow
    # Ensure the Real-Time Protection registry path exists
    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Force
    }

    # Disable Real-Time Protection
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1 -Force

    # Ensure the Windows Defender registry path exists
    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Force
    }

    # Turn off Windows Defender Antivirus
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1 -Force
    Write-Host "    [v] The real time protection was disabled permanently." -ForegroundColor Green
}

function reenableRealTimeProtection {
    Write-Host "[o] Reenable real time protection." -ForegroundColor Yellow
    # Re-enable Real-Time Protection
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 0 -Force

    # Turn on Windows Defender Antivirus
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 0 -Force
    Write-Host "    [v] The real time protection was reenabled successfully." -ForegroundColor Green
}

function bginfoSetup {
    Write-Host "[o] Setting up BGInfo at startup." -ForegroundColor Yellow
    $configFile = 

    & $env:USERPROFILE\Desktop\Tools\sysinternals\bginfo.exe "./configurations/bginfo-conf.bgi" /timer:0 /silent

    Write-Host "    [v] BGInfo was setup successfully." -ForegroundColor Green
}

# activateWindowsAndOffice
makeSureRunningAsAdmin
setupBackground
copyIconsToPictures
setupDesktopFolders
downloadChoco
installChocoPackages
# upgradeChocoPackages
setupOhMyPsh
installVSCodeExtensions
createToolsDesktopShortcuts
setupFirefox
createShortcutForHostsFile
# installWSL
setupDefenderExcludedFolder
permanentlyDisableRealTimeProtection
# reenableRealTimeProtection
bginfoSetup