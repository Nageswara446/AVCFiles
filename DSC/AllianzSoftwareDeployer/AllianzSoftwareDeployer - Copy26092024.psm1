#You need a unique resource name

[DscResource()]
Class InstallerClass {
  
  [DscProperty(Key)]
  [String]$PackageName
  
  [DscProperty()]
  [ValidateSet('Present','Absent')]
  [String]$Ensure
   
  [DscProperty()]
  [String]$Executable
   
  [DscProperty()]
  [String]$Source

  [DscProperty()]
  [int]$TimeOut
   
  [DscProperty()]
  [String]$DetectionProductUninstallRegKeyValue

  [DscProperty()]
  [string[]]$DetectionProductRegistryKeys
  
  [DscProperty()]
  [String[]]$DetectionFilePath

  [DscProperty()]
  [String[]]$DetectionKeyValues


# Sets the desired state of the resource.
[void] Set() {

    if ($this.Ensure -eq "Present") {
        #Instalation part  
        Write-Verbose "[InstallerClass] Invoking SET()"
        Write-Verbose "[InstallerClass] Version 2.0.0"

        Write-Verbose "Set Local Package directory"
        $localPathString = "C:\Packages"
        $sourcePathArray = $this.Source.Split('\')
        $sourcePathArray[2] = $localPathString
        
        $localSourcePath = [System.String]::Join('\', $sourcePathArray)
        $localSourcePath = $localSourcePath.Substring(2)

        Write-Verbose "Local path:  $($localSourcePath)"
        if (!$localSourcePath.StartsWith($localPathString)) {
            Write-Verbose "Setting local path FAILED, $($localSourcePath)."
            Break;
        }

        try {
            Write-Verbose "[InstallerClass] Invoking SET()"

            $Item = Get-Item $localSourcePath -ErrorAction SilentlyContinue
                    if ($Item) {
                        Write-Verbose "[InstallerClass] Start removing old package data. Running under: '$(whoami)'. Package location: $($Item)"
                        Remove-item $item -Recurse -Force
                    }
                    Write-Verbose "[InstallerClass] Start copy actions"        
            Copy-Item -Path $this.Source -Destination $localSourcePath -Recurse
            }

        catch {
            $ErrorMessage = $_.Exception.Message;
                Write-Host  "Exception occurred in the package copy task ""$($this.Source), destination: $($localSourcePath)"". The error message was: $ErrorMessage."
                Break;
        }

        try {
            #add timeout
            $timeoutValue = 7000
            if ($this.TimeOut -gt 0) {
                $timeoutValue = $this.TimeOut
            }

            #Pre-re. untrusted publisher fix.
            Get-ChildItem -Path $localSourcePath -Recurse | Unblock-File
            
            Write-Verbose "Timeout value: $($timeoutValue)"
            Write-Verbose "Timeout value in configuration: $($this.TimeOut)"
            #Start installation 
            Write-Verbose "Executable: $($this.Executable)";
            Write-Verbose "Start installation";
            Write-Verbose " Path to executable: $($localSourcePath)$($this.Executable)";
            if ($this.Executable -like "*.ps1" ) {
                    try
                        {
                            $PSExecutable = $this.Executable
                            $process = Start-Job -ScriptBlock{

                                Param  ($localSourcePath, $PSExecutable)
                            
                                ."$($localSourcePath)$($PSExecutable)"
                            
                                } -ArgumentList $localSourcePath, $PSExecutable
                                
                            Wait-Job $process.Id -Timeout $this.TimeOut -ErrorAction Stop
                            Receive-Job $process.Id -ErrorAction Stop
                            Stop-Job $process.Id
                            Receive-Job $process -ErrorAction Stop
                            Remove-Job $process.Id
                            Write-Verbose "Instalation finished"
                            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_Success.txt" -Force

                                $Item = Get-Item $localSourcePath -ErrorAction SilentlyContinue
                                    if ($Item) {
                                        Write-Verbose "[InstallerClass] Start removing old package data. Running under: '$(whoami)'. Package location: $($Item)"
                                        Remove-item $item -Recurse -Force -ErrorAction SilentlyContinue
                                    }
                        }
                    catch
                        {
                            $ErrorMessage = $_.Exception.Message;
                            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_FAIL.txt"  -Value $ErrorMessage -Force
                            throw "Exception occurred in the instalation of: ""$($localSourcePath)$($this.Executable)"". The error message was: $ErrorMessage."
                            
                        }
            }
            else
            {
                $process = Start-Process -PassThru -FilePath "$($localSourcePath)$($this.Executable)" -WorkingDirectory $localSourcePath
                    try
                        {
                            $process | Wait-Process -Timeout $timeoutValue -ErrorAction Stop
                            Write-Verbose "Instalation finished. Exit code detected: $($process.ExitCode)";
                            Write-Verbose "Re-Check Instalation using defined detection methods:";

                                #region Re-Check instalation
                                #FULL REGISTRY KEY CHECK
                                if ($this.DetectionProductRegistryKeys.Length -gt 0 ) {
                                    Write-Verbose "Start re-testing with: $([String]::Join(",", $this.DetectionProductRegistryKeys))"

                                    foreach($key in $this.DetectionProductRegistryKeys){

                                        Write-verbose "Re-Testing registry key: $($key)"
                                        $regResult = Test-Path $key
                                    
                                        if(!$regResult) {
                                            $testResult = $false;
                                            Throw "Instalation did not finished successfully. Registry key: $($key) was not found."  
                                        }

                                    Write-Verbose "Re-Check PASS. Registry Key $($key) found."
                                    }     
                                }

                                if ($this.DetectionProductUninstallRegKeyValue -ne "NA" -and "$($this.DetectionProductUninstallRegKeyValue)" -ne '' ) {
                                    Write-Verbose "Start testing with: $($this.DetectionProductUninstallRegKeyValue)"

                                    $reg32 = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($this.DetectionProductUninstallRegKeyValue)"
                                    $reg64 = "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($this.DetectionProductUninstallRegKeyValue)"
                                    $reg64Result = Test-Path $reg64
                                    $reg32Result = Test-Path $reg32

                                    Write-Verbose "reg32: '$($reg32Result)'"
                                    Write-Verbose "reg64: '$($reg64Result)'"
                                    if( !$reg64Result -and !$reg32Result ) {
                                        $testResult = $false;
                                        Throw "Instalation did not finished successfully. Uninstall registry key: $($this.DetectionProductUninstallRegKeyValue) was not found."  
                                    }

                                Write-Verbose "Re-Check PASS Uninstall Registry Key: $($this.DetectionProductUninstallRegKeyValue) found."
                                }

                                #FILE CHECK
                                if ($this.DetectionFilePath -ne  "NA" -and "$($this.DetectionFilePath)" -ne '' ) {
                                    
                                    Foreach($file in $this.DetectionFilePath)
                                    {
                                        Write-Verbose "Start testing file: $($file)"
                                        if (!(Test-Path $file)) {
                                            $testResult = $false;
                                            Throw "Instalation did not finished successfully. Path $($file) was not found."  
                                        }
                                        Write-Verbose "Re-Check PASS Log File: $($file) found"
                                    }
                                }

                                #REGISTRY KEY VALUE CHECK
                                if ($this.DetectionKeyValues -ne  "NA" -and "$($this.DetectionKeyValues)" -ne '' ) {
                                    
                                    Foreach($State in $this.DetectionKeyValues)
                                    {
                                        Write-Verbose "Start registry values check: $($State)"

                                            $DesiredState = $true;
                                            try {
                                                $Values = $state.Split("=")
                                                $Path = $Values[0] 
                                                $Key = $Values[1]
                                                $DesiredKeyValue = $Values[2]
                                                $RegKeyValue = Get-ItemProperty -Path $Path | Select-Object -ExpandProperty $Key -ErrorAction Stop
                                                
                                                    if($RegKeyValue -eq $DesiredKeyValue){
                                                    }
                                                    else{
                                                    $DesiredState =$false;
                                                    }
                                            }
                                            catch {
                                                    $ErrorMessage = $_.Exception.Message;
                                                    Throw "Error while cheking registry values: $ErrorMessage"                 
                                            }
                                            
                                        if ($DesiredState -eq $false) {
                                            $testResult = $false;
                                            $this.DetectionProductUninstallRegKeyValue 
                                            Throw "Instalation did not finished successfully. Registry value $($State) was not found."  
                                        }
                                        Write-Verbose "Re-check PASS. Registry key value check test PASS: $($State) found"
                                    }
                                }
                                #endregion
                            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_SUCCESS.txt"  -Value $process.ExitCode -Force
                                
                                $Item = Get-Item $localSourcePath -ErrorAction SilentlyContinue
                                if ($Item) {
                                    Write-Verbose "[InstallerClass] Start removing old package data. Running under: '$(whoami)'. Package location: $($Item)"
                                    Remove-item $item -Recurse -Force -ErrorAction SilentlyContinue
                                }
                        }
                    catch
                        {
                            $ErrorMessage = $_.Exception.Message;
                            $ErrorType = $_.Exception.GetType().Name.toString()

                            if($ErrorType  -eq'TimeoutException')
                            {
                            Write-Host "Timeout was triggered, Warning: $ErrorMessage"
                            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_TIMEOUT.txt"  -Value $ErrorMessage -Force
                            $process | Stop-Process -Force
                            }

                            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_FAIL.txt"  -Value $ErrorMessage -Force
                            $process | Stop-Process -Force
                            throw "Exception occurred in the instalation of: ""$($localSourcePath)$($this.Executable)"". The error message was: $ErrorMessage."
                        }
            }
        }
        catch {
            $ErrorMessage = $_.Exception.Message;
            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_FAIL.txt"  -Value $ErrorMessage -Force
            throw "Exception occurred in the instalation of: ""$($localSourcePath)$($this.Executable)"". The error message was: $ErrorMessage."
        }     
        
    }
    elseif($this.Ensure -eq "Absent"){
#uninstall part
        Write-Verbose "[InstallerClass] Invoking SET for Uninstall()"
        Write-Verbose "[InstallerClass] Version 2.0.0"

        Write-Verbose "Set Local Package directory"
        $localPathString = "C:\Packages"
        $sourcePathArray = $this.Source.Split('\')
        $sourcePathArray[2] = $localPathString

        $localSourcePath = [System.String]::Join('\', $sourcePathArray)
        $localSourcePath = $localSourcePath.Substring(2)

        Write-Verbose "Local path:  $($localSourcePath)"
        if (!$localSourcePath.StartsWith($localPathString)) {
            Write-Verbose "Setting local path FAILED, $($localSourcePath)."
            Break;
        }

        try {
            Write-Verbose "[InstallerClass] Invoking SET for Uninstall()"

            $Item = Get-Item $localSourcePath -ErrorAction SilentlyContinue
                    if ($Item) {
                        Write-Verbose "[InstallerClass] Start removing old package data. Running under: '$(whoami)'. Package location: $($Item)"
                        Remove-item $item -Recurse -Force
                    }
                    Write-Verbose "[InstallerClass] Start copy actions"        
            Copy-Item -Path $this.Source -Destination $localSourcePath -Recurse
            }

        catch {
            $ErrorMessage = $_.Exception.Message;
                Write-Host  "Exception occurred in the package copy task ""$($this.Source), destination: $($localSourcePath)"". The error message was: $ErrorMessage."
                Break;
        }

        try {
            #add timeout
            $timeoutValue = 7000
            if ($this.TimeOut -gt 0) {
                $timeoutValue = $this.TimeOut
            }

            #Pre-re. untrusted publisher fix.
            Get-ChildItem -Path $localSourcePath -Recurse | Unblock-File
            
            Write-Verbose "Timeout value: $($timeoutValue)"
            Write-Verbose "Timeout value in configuration: $($this.TimeOut)"
            #Start installation 
            Write-Verbose "Executable: $($this.Executable)";
            Write-Verbose "Start Uninstallation";
            Write-Verbose " Path to executable: $($localSourcePath)$($this.Executable)";
          
            if ($this.Executable -like "*.ps1" ) {
                    try
                        {
                            $PSExecutable = $this.Executable
                            $process = Start-Job -ScriptBlock{

                                Param  ($localSourcePath, $PSExecutable)
                            
                                ."$($localSourcePath)$($PSExecutable)"
                            
                                } -ArgumentList $localSourcePath, $PSExecutable
                                
                            Wait-Job $process.Id -Timeout $this.TimeOut -ErrorAction Stop
                            Receive-Job $process.Id -ErrorAction Stop
                            Stop-Job $process.Id
                            Receive-Job $process -ErrorAction Stop
                            Remove-Job $process.Id
                            Write-Verbose "Uninstalation finished"
                            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_Uninstall_Success.txt" -Force

                                $Item = Get-Item $localSourcePath -ErrorAction SilentlyContinue
                                    if ($Item) {
                                        Write-Verbose "[InstallerClass] Start removing old package data. Running under: '$(whoami)'. Package location: $($Item)"
                                        Remove-item $item -Recurse -Force -ErrorAction SilentlyContinue
                                    }
                        }
                    catch
                        {
                            $ErrorMessage = $_.Exception.Message;
                            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_Uninstall_FAIL.txt"  -Value $ErrorMessage -Force
                            throw "Exception occurred in the uninstalation of: ""$($localSourcePath)$($this.Executable)"". The error message was: $ErrorMessage."
                            
                        }
            }
            else
            {
                $process = Start-Process -PassThru -FilePath "$($localSourcePath)$($this.Executable)" -WorkingDirectory $localSourcePath
                    try
                        {
                            $process | Wait-Process -Timeout $timeoutValue -ErrorAction Stop
                            Write-Verbose "Uninstalation finished. Exit code detected: $($process.ExitCode)";
                            Write-Verbose "Re-Check Uninstalation using defined detection methods:";

                                #region Re-Check instalation
                                #FULL REGISTRY KEY CHECK
                                if ($this.DetectionProductRegistryKeys.Length -gt 0 ) {
                                    Write-Verbose "Start re-testing with: $([String]::Join(",", $this.DetectionProductRegistryKeys))"

                                    foreach($key in $this.DetectionProductRegistryKeys){

                                        Write-verbose "Re-Testing registry key: $($key)"
                                        $regResult = Test-Path $key
                                    
                                        if($regResult) {
                                            $testResult = $false;
                                            Throw "Uninstalation did not finished successfully. Registry key: $($key) was found."  
                                        }

                                    Write-Verbose "Re-Check PASS. Registry Key $($key)  not found."
                                    }     
                                }

                                if ($this.DetectionProductUninstallRegKeyValue -ne "NA" -and "$($this.DetectionProductUninstallRegKeyValue)" -ne '' ) {
                                    Write-Verbose "Start testing with: $($this.DetectionProductUninstallRegKeyValue)"

                                    $reg32 = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($this.DetectionProductUninstallRegKeyValue)"
                                    $reg64 = "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($this.DetectionProductUninstallRegKeyValue)"
                                    $reg64Result = Test-Path $reg64
                                    $reg32Result = Test-Path $reg32

                                    Write-Verbose "reg32: '$($reg32Result)'"
                                    Write-Verbose "reg64: '$($reg64Result)'"
                                    if( $reg64Result -and $reg32Result ) {
                                        $testResult = $false;
                                        Throw "Uninstalation did not finished successfully. Uninstall registry key: $($this.DetectionProductUninstallRegKeyValue) was found."  
                                    }

                                Write-Verbose "Re-Check PASS Uninstall Registry Key: $($this.DetectionProductUninstallRegKeyValue) was not found."
                                }

                                #FILE CHECK
                                if ($this.DetectionFilePath -ne  "NA" -and "$($this.DetectionFilePath)" -ne '' ) {
                                    
                                    Foreach($file in $this.DetectionFilePath)
                                    {
                                        Write-Verbose "Start testing file: $($file)"
                                        if ((Test-Path $file)) {
                                            $testResult = $false;
                                            Throw "Uninstalation did not finished successfully. Path $($file) was found."  
                                        }
                                        Write-Verbose "Re-Check PASS Log File: $($file) was not found"
                                    }
                                }

                                #REGISTRY KEY VALUE CHECK
                                if ($this.DetectionKeyValues -ne  "NA" -and "$($this.DetectionKeyValues)" -ne '' ) {
                                    
                                    Foreach($State in $this.DetectionKeyValues)
                                    {
                                        Write-Verbose "Start registry values check: $($State)"

                                            $DesiredState = $true;
                                            try {
                                                $Values = $state.Split("=")
                                                $Path = $Values[0] 
                                                $Key = $Values[1]
                                                $DesiredKeyValue = $Values[2]
                                                $RegKeyValue = Get-ItemProperty -Path $Path | Select-Object -ExpandProperty $Key -ErrorAction Stop
                                                
                                                    if($RegKeyValue -eq $DesiredKeyValue){
                                                    }
                                                    else{
                                                    $DesiredState =$false;
                                                    }
                                            }
                                            catch {
                                                    $ErrorMessage = $_.Exception.Message;
                                                    Throw "Error while cheking registry values: $ErrorMessage"                 
                                            }
                                            
                                        if (!$DesiredState -eq $false) {
                                            $testResult = $false;
                                            $this.DetectionProductUninstallRegKeyValue 
                                            Throw "Instalation did not finished successfully. Registry value $($State) was found."  
                                        }
                                        Write-Verbose "Re-check PASS. Registry key value check test PASS: $($State) was not found."
                                    }
                                }
                                #endregion
                            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_Uninstall_SUCCESS.txt"  -Value $process.ExitCode -Force
                                
                                $Item = Get-Item $localSourcePath -ErrorAction SilentlyContinue
                                if ($Item) {
                                    Write-Verbose "[InstallerClass] Start removing old package data. Running under: '$(whoami)'. Package location: $($Item)"
                                    Remove-item $item -Recurse -Force -ErrorAction SilentlyContinue
                                }
                        }
                    catch
                        {
                            $ErrorMessage = $_.Exception.Message;
                            $ErrorType = $_.Exception.GetType().Name.toString()

                            if($ErrorType  -eq'TimeoutException')
                            {
                            Write-Host "Timeout was triggered, Warning: $ErrorMessage"
                            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_Uninstall_TIMEOUT.txt"  -Value $ErrorMessage -Force
                            $process | Stop-Process -Force
                            }

                            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_Uninstall_FAIL.txt"  -Value $ErrorMessage -Force
                            $process | Stop-Process -Force
                            throw "Exception occurred in the instalation of: ""$($localSourcePath)$($this.Executable)"". The error message was: $ErrorMessage."
                        }
            }
        }
        catch {
            $ErrorMessage = $_.Exception.Message;
            New-Item -Path 'C:\AMOS\PackageInstallationTracker' -Name "$($this.PackageName)_Uninstall_FAIL.txt"  -Value $ErrorMessage -Force
            throw "Exception occurred in the instalation of: ""$($localSourcePath)$($this.Executable)"". The error message was: $ErrorMessage."
        }

    }

   
} #Set        
    
# Tests if the resource is in the desired state.
[bool] Test() {   

[bool] $testResult = $true;

if ($this.Ensure -eq "Present") {
    Write-Verbose "[InstallerClass] Invoking TEST()"
    #presume the state is TRUE (desired)
    [bool] $testResult = $true;
    #Go throuth detection types. Do action based on the type. IF one of the action fails, meaning not as expected, $result is set to $false and return as failed test. 
    Write-Verbose "Set Local Package directory"

        #FULL REGISTRY KEY CHECK
        if ($this.DetectionProductRegistryKeys.Length -gt 0 ) {
            Write-Verbose "Start testing with: $([String]::Join(",", $this.DetectionProductRegistryKeys))"

            foreach($key in $this.DetectionProductRegistryKeys){

                Write-verbose "Testing registry key: $($key)"
               # regkey expected format HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\2090_Oracle_OracleODAC_11.2.03.20_PKG_R1
                $regResult = Test-Path $key
               
                if(!$regResult) {
                    $testResult = $false;
                    Write-Verbose "[InstallerClass] TEST(). RegKey test FAIL $($key) was not found."
                    Return $testResult;
                }
    
             Write-Verbose "[InstallerClass] TEST(). RegKey test PASS Registry Key $($key) found."
            }     
        }

        if ($this.DetectionProductUninstallRegKeyValue -ne "NA" -and "$($this.DetectionProductUninstallRegKeyValue)" -ne '' ) {
            Write-Verbose "Start testing with: $($this.DetectionProductUninstallRegKeyValue)"

            $reg32 = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($this.DetectionProductUninstallRegKeyValue)"
            $reg64 = "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($this.DetectionProductUninstallRegKeyValue)"
            $reg64Result = Test-Path $reg64
            $reg32Result = Test-Path $reg32


            Write-Verbose "reg32: '$($reg32Result)'"
            Write-Verbose "reg64: '$($reg64Result)'"
            if( !$reg64Result -and !$reg32Result ) {
                $testResult = $false;
                Write-Verbose "[InstallerClass] TEST(). Uninstall RegKey test FAIL as path to registry: $($this.DetectionProductUninstallRegKeyValue) was not found."
                Return $testResult;
            }

         Write-Verbose "[InstallerClass] TEST(). Uninstall RegKey test PASS Registry Key: $($this.DetectionProductUninstallRegKeyValue) found."
        }

        #FILE CHECK
        if ($this.DetectionFilePath -ne  "NA" -and "$($this.DetectionFilePath)" -ne '' ) {
            
            Foreach($file in $this.DetectionFilePath)
            {
                #if file dose not exist set $testResult to false and return failed test. 
                Write-Verbose "Start testing file: $($file)"
                if (!(Test-Path $file)) {
                    $testResult = $false;
                    Write-Verbose "[InstallerClass] TEST(). LogFile test FAIL as file: $($file) was not found"
                    Return $testResult;
                }

                Write-Verbose "[InstallerClass] TEST(). LogFile test PASS Log file: $($file) found"
            }
        }

        #REGISTRY KEY VALUE CHECK
        if ($this.DetectionKeyValues -ne  "NA" -and "$($this.DetectionKeyValues)" -ne '' ) {
            
            Foreach($State in $this.DetectionKeyValues)
            {
                #if values are not correct $testResult to false and return failed test. 
                Write-Verbose "Start registry values check: $($State)"

                    $DesiredState = $true;
                    try {
                        $Values = $state.Split("=")
                        $Path = $Values[0] 
                        $Key = $Values[1]
                        $DesiredKeyValue = $Values[2]
                        $RegKeyValue = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $Key -ErrorAction SilentlyContinue
                        
                            if($RegKeyValue -eq $DesiredKeyValue){
                            }
                            else{
                            $DesiredState =$false;
                            }
                    }
                    catch {
                            $ErrorMessage = $_.Exception.Message;
                            Throw "Error while cheking registry values: $ErrorMessage"                 
                    }
                    
                if ($DesiredState -eq $false) {
                    $testResult = $false;
                    Write-Verbose "[InstallerClass] TEST(). Registry key value check  FAIL as Statement: $($State) was not found"
                    Return $testResult;
                }
                Write-Verbose "[InstallerClass] TEST(). Registry key value check test PASS: $($State) found"
            }
        }
 
        #Always test for the custom file for success or fail actions.
        Write-Verbose "Start testing with: $($this.DetectionTypes) Type"
        if (!(Test-Path "C:\AMOS\PackageInstallationTracker\$($this.PackageName)_SUCCESS.txt")) {
            $testResult = $false;
            Write-Verbose "[InstallerClass] TEST(). Custom test FAIL as file: C:\AMOS\PackageInstallationTracker\$($this.PackageName)_SUCCESS.txt indicating successful installation was not found"
            Return $testResult;
        }

        Write-Verbose "[InstallerClass] TEST(). Custom test PASS, custom file: C:\AMOS\PackageInstallationTracker\$($this.PackageName)_SUCCESS.txt found"
        

#if all checks pass return True inticating a pass test. 
Return $testResult;
}

elseif($this.Ensure -eq "Absent"){
    Write-Verbose "[InstallerClass] Invoking TEST()"
    #presume the state is TRUE (desired)
    [bool] $testResult = $true;
    #Go throuth detection types. Do action based on the type. IF one of the action fails, meaning not as expected, $result is set to $false and return as failed test. 
    Write-Verbose "Set Local Package directory"

        #FULL REGISTRY KEY CHECK
        if ($this.DetectionProductRegistryKeys.Length -gt 0 ) {
            Write-Verbose "Start testing with: $([String]::Join(",", $this.DetectionProductRegistryKeys))"

            foreach($key in $this.DetectionProductRegistryKeys){

                Write-verbose "Testing registry key: $($key)"
               # regkey expected format HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\2090_Oracle_OracleODAC_11.2.03.20_PKG_R1
                $regResult = Test-Path $key
               
                if($regResult) {
                    $testResult = $false;
                    Write-Verbose "[InstallerClass] TEST(). RegKey test FAIL $($key) was found."
                    Return $testResult;
                }
    
             Write-Verbose "[InstallerClass] TEST(). RegKey test PASS Registry Key $($key) not found found."
            }     
        }

        if ($this.DetectionProductUninstallRegKeyValue -ne "NA" -and "$($this.DetectionProductUninstallRegKeyValue)" -ne '' ) {
            Write-Verbose "Start testing with: $($this.DetectionProductUninstallRegKeyValue)"

            $reg32 = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($this.DetectionProductUninstallRegKeyValue)"
            $reg64 = "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$($this.DetectionProductUninstallRegKeyValue)"
            $reg64Result = Test-Path $reg64
            $reg32Result = Test-Path $reg32


            Write-Verbose "reg32: '$($reg32Result)'"
            Write-Verbose "reg64: '$($reg64Result)'"
            if( $reg64Result -and $reg32Result ) {
                $testResult = $false;
                Write-Verbose "[InstallerClass] TEST(). Uninstall RegKey test FAIL as path to registry: $($this.DetectionProductUninstallRegKeyValue) was found."
                Return $testResult;
            }

         Write-Verbose "[InstallerClass] TEST(). Uninstall RegKey test PASS Registry Key: $($this.DetectionProductUninstallRegKeyValue) was not found."
        }

        #FILE CHECK
        if ($this.DetectionFilePath -ne  "NA" -and "$($this.DetectionFilePath)" -ne '' ) {
            
            Foreach($file in $this.DetectionFilePath)
            {
                #if file dose not exist set $testResult to false and return failed test. 
                Write-Verbose "Start testing file: $($file)"
                if (Test-Path $file) {
                    $testResult = $false;
                    Write-Verbose "[InstallerClass] TEST(). LogFile test FAIL as file: $($file) was found"
                    Return $testResult;
                }

                Write-Verbose "[InstallerClass] TEST(). LogFile test PASS Log file: $($file) not found found."
            }
        }

        #REGISTRY KEY VALUE CHECK
        if ($this.DetectionKeyValues -ne  "NA" -and "$($this.DetectionKeyValues)" -ne '' ) {
            
            Foreach($State in $this.DetectionKeyValues)
            {
                #if values are not correct $testResult to false and return failed test. 
                Write-Verbose "Start registry values check: $($State)"

                    $DesiredState = $true;
                    try {
                        $Values = $state.Split("=")
                        $Path = $Values[0] 
                        $Key = $Values[1]
                        $DesiredKeyValue = $Values[2]
                        $RegKeyValue = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $Key -ErrorAction SilentlyContinue
                        
                            if($RegKeyValue -eq $DesiredKeyValue){
                            }
                            else{
                            $DesiredState =$false;
                            }
                    }
                    catch {
                            $ErrorMessage = $_.Exception.Message;
                            Throw "Error while cheking registry values: $ErrorMessage"                 
                    }
                    
                if ($DesiredState -eq $false) {
                    $testResult = $false;
                    Write-Verbose "[InstallerClass] TEST(). Registry key value check  FAIL as Statement: $($State) was not found"
                    Return $testResult;
                }
                Write-Verbose "[InstallerClass] TEST(). Registry key value check test PASS: $($State) found"
            }
        }
 
        #Always test for the custom file for success or fail actions.
        Write-Verbose "Start testing with: $($this.DetectionTypes) Type"
        if (!(Test-Path "C:\AMOS\PackageInstallationTracker\$($this.PackageName)_Uninstall_SUCCESS.txt")) {
            $testResult = $false;
            Write-Verbose "[InstallerClass] TEST(). Custom test FAIL as file: C:\AMOS\PackageInstallationTracker\$($this.PackageName)_Uninstall_SUCCESS.txt indicating successful uninstallation was not found"
            Return $testResult;
        }

        Write-Verbose "[InstallerClass] TEST(). Custom test PASS, custom file: C:\AMOS\PackageInstallationTracker\$($this.PackageName)_Uninstall_SUCCESS.txt found"
        

#if all checks pass return True inticating a pass test. 
Return $testResult;
}

    
Return $testResult;






} #Test    

# Gets the resource's current state.
[InstallerClass] Get()  {        

Write-Verbose "Set Local Package directory"
# build object based on the current state of the instalation. 

#useless at the momenent.
$this.Packagename = $this.PackageName
$this.DetectionProductUninstallRegKeyValue = $this.DetectionProductUninstallRegKeyValue;
$this.Ensure  
$this.Executable = $this.Executable;
$this.Source = $this.Source;
$this.DetectionFilePath = $this.DetectionFilePath;
$this.TimeOut = $this.TimeOut;
$this.DetectionProductRegistryKeys = $this.DetectionProductRegistryKeys;
$this.DetectionFilePath = $this.DetectionFilePath;


Return $this;

} #Get   

} #end class InstallerClass

