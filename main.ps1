#Requires -PSEdition Core -Version 7.2
$Script:ErrorActionPreference = 'Stop'
Get-Alias -Scope 'Local' -ErrorAction 'SilentlyContinue' |
	Remove-Alias -Scope 'Local' -Force -ErrorAction 'SilentlyContinue'
Import-Module -Name 'hugoalh.GitHubActionsToolkit' -Scope 'Local'
[String]$OsPathPropertyName = "Path$($Env:RUNNER_OS)"
$RegistryApt = @{
	IsExist = $Null -ine (Get-Command -Name 'apt-get' -CommandType 'Application' -ErrorAction 'SilentlyContinue')
	ScriptRemove = {
		Param ([String[]]$Packages = @())
		ForEach ($Package In $Packages) {
			apt-get --assume-yes remove $Package *>&1 |
				Write-Output
		}
	}
}
$RegistryChocolatey = @{
	IsExist = $Null -ine (Get-Command -Name 'choco' -CommandType 'Application' -ErrorAction 'SilentlyContinue')
	ScriptRemove = {
		Param ([String[]]$Packages = @())
		ForEach ($Package In $Packages) {
			choco uninstall $Package --ignore-detected-reboot --yes *>&1 |
				Write-Output
		}
	}
}
$RegistryDocker = @{
	IsExist = $Null -ine (Get-Command -Name 'docker' -CommandType 'Application' -ErrorAction 'SilentlyContinue')
	ScriptList = {
		docker image ls --all --format '{{json .}}' *>&1 |
			Write-Output
	}
	ScriptRemove = {
		Param ([String[]]$Images = @())
		ForEach ($Image In $Images) {
			docker image rm $Image *>&1 |
				Write-Output
		}
	}
}
$RegistryHomebrew = @{
	IsExist = $Null -ine (Get-Command -Name 'brew' -CommandType 'Application' -ErrorAction 'SilentlyContinue')
	ScriptRemove = {
		Param ([String[]]$Packages = @())
		ForEach ($Package In $Packages) {
			brew uninstall $Package *>&1 |
				Write-Output
		}
	}
}
$RegistryNpm = @{
	IsExist = $Null -ine (Get-Command -Name 'npm' -CommandType 'Application' -ErrorAction 'SilentlyContinue')
	ScriptRemove = {
		Param ([String[]]$Packages = @())
		ForEach ($Package In $Packages) {
			npm --global uninstall $Package *>&1 |
				Write-Output
		}
	}
}
$RegistryPipx = @{
	IsExist = $Null -ine (Get-Command -Name 'pipx' -CommandType 'Application' -ErrorAction 'SilentlyContinue')
	ScriptRemove = {
		Param ([String[]]$Packages = @())
		ForEach ($Package In $Packages) {
			pipx uninstall $Package *>&1 |
				Write-Output
		}
	}
}
$RegistryWmic = @{
	IsExist = $Env:RUNNER_OS -iin @('Windows') -and $Null -ine (Get-Command -Name 'Invoke-CimMethod' -ErrorAction 'SilentlyContinue')
	ScriptRemove = {
		Param ([String[]]$Packages = @())
		ForEach ($Package In $Packages) {
			[String[]]$PackageResolve = Get-CimInstance -ClassName 'Win32_Product' |
				Select-Object -ExpandProperty 'Name' |
				Where-Object -FilterScript { $_ -ilike $Package }
			ForEach ($_ In $PackageResolve) {
				Invoke-CimMethod -Query "select * from Win32_Product where name like `"%$_%`"" -MethodName 'Uninstall' *>&1 |
					Write-Output
			}
		}
	}
}
Function Get-DiskSpace {
	[CmdletBinding()]
	[OutputType([String])]
	Param ()
	If ($Env:RUNNER_OS -iin @('Linux', 'MacOS')) {
		df -h |
			Join-String -Separator "`n" |
			Write-Output
	}
	ElseIf ($Env:RUNNER_OS -iin @('Windows')) {
		Get-Volume |
			Out-String -Width 120 |
			Write-Output
	}
	Else {
		Write-Output -InputObject 'Unknown.'
	}
}
Function Test-StringMatchRegEx {
	[CmdletBinding()]
	[OutputType([Boolean])]
	Param (
		[Parameter(Mandatory = $True, Position = 0)][String]$Item,
		[Parameter(Mandatory = $True, Position = 1)][AllowEmptyCollection()][Alias('Matchers')][RegEx[]]$Matcher
	)
	ForEach ($_M In $Matcher) {
		If ($Item -imatch $_M) {
			Write-Output -InputObject $True
			Return
		}
	}
	Write-Output -InputObject $False
}
[String]$DiskSpaceBefore = Get-DiskSpace
[PSCustomObject]@{
	Runner_OS = $Env:RUNNER_OS
	Env_ToolDirectory = $Env:AGENT_TOOLSDIRECTORY
	Registry_APT = $RegistryApt.IsExist
	Registry_Chocolatey = $RegistryChocolatey.IsExist
	Registry_Docker = $RegistryDocker.IsExist
	Registry_Homebrew = $RegistryHomebrew.IsExist
	Registry_NPM = $RegistryNpm.IsExist
	Registry_Pipx = $RegistryPipx.IsExist
	Registry_WMIC = $RegistryWmic.IsExist
} |
	Format-List |
	Out-String -Width 120 |
	Write-GitHubActionsDebug
[RegEx]$InputListDelimiter = Get-GitHubActionsInput -Name 'input_listdelimiter' -Mandatory -EmptyStringAsNull
[AllowEmptyCollection()][RegEx[]]$InputGeneralInclude = (
	((Get-GitHubActionsInput -Name 'general_include' -EmptyStringAsNull) ?? '') -isplit $InputListDelimiter |
		Where-Object -FilterScript { $_.Length -gt 0 }
) ?? @()
[AllowEmptyCollection()][RegEx[]]$InputGeneralExclude = (
	((Get-GitHubActionsInput -Name 'general_exclude' -EmptyStringAsNull) ?? '') -isplit $InputListDelimiter |
		Where-Object -FilterScript { $_.Length -gt 0 }
) ?? @()
[AllowEmptyCollection()][RegEx[]]$InputDockerInclude = (
	((Get-GitHubActionsInput -Name 'docker_include' -EmptyStringAsNull) ?? '') -isplit $InputListDelimiter |
		Where-Object -FilterScript { $_.Length -gt 0 }
) ?? @()
[AllowEmptyCollection()][RegEx[]]$InputDockerExclude = (
	((Get-GitHubActionsInput -Name 'docker_exclude' -EmptyStringAsNull) ?? '') -isplit $InputListDelimiter |
		Where-Object -FilterScript { $_.Length -gt 0 }
) ?? @()
[Boolean]$InputAptClean = [Boolean]::Parse($Env:INPUT_APT_CLEAN)
[Boolean]$InputAptPrune = [Boolean]::Parse($Env:INPUT_APT_PRUNE)
[Boolean]$InputDockerClean = [Boolean]::Parse($Env:INPUT_DOCKER_CLEAN)
[Boolean]$InputDockerPrune = [Boolean]::Parse($Env:INPUT_DOCKER_PRUNE)
[Boolean]$InputHomebrewClean = [Boolean]::Parse($Env:INPUT_HOMEBREW_CLEAN)
[Boolean]$InputHomebrewPrune = [Boolean]::Parse($Env:INPUT_HOMEBREW_PRUNE)
[Boolean]$InputNpmClean = [Boolean]::Parse($Env:INPUT_NPM_CLEAN)
[Boolean]$InputNpmPrune = [Boolean]::Parse($Env:INPUT_NPM_PRUNE)
[Boolean]$InputOperateAsync = [Boolean]::Parse($Env:INPUT_OPERATE_ASYNC)
[Boolean]$InputOsSwap = [Boolean]::Parse($Env:INPUT_OS_SWAP)
Write-Host -Object 'Resolve operation.'
[String[]]$DockerImageListRaw = @()
[String[]]$DockerImageRemove = @()
[PSCustomObject[]]$GeneralRemove = @()
If ($RegistryDocker.IsExist -and $InputDockerInclude.Count -gt 0) {
	If ($InputOperateAsync) {
		$Null = Start-Job -Name "Docker/List" -ScriptBlock $RegistryDocker.ScriptList
	}
	Else {
		$DockerImageListRaw += Invoke-Command -ScriptBlock $RegistryDocker.ScriptList
	}
}
If ($InputGeneralInclude.Count -gt 0) {
	$GeneralRemove += Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'list.json') -Raw -Encoding 'UTF8NoBOM' -ErrorAction 'Continue' |
		ConvertFrom-Json -Depth 100 |
		Select-Object -ExpandProperty 'Collection' |
		Where-Object -FilterScript { (Test-StringMatchRegEx -Item $_.Name -Matcher $InputGeneralInclude) -and !(Test-StringMatchRegEx -Item $_.Name -Matcher $InputGeneralExclude) } |
		Where-Object -FilterScript {
			($RegistryApt.IsExist -and $Null -ine $_.APT) -or
			($RegistryChocolatey.IsExist -and $Null -ine $_.Chocolatey) -or
			($RegistryHomebrew.IsExist -and $Null -ine $_.Homebrew) -or
			($RegistryNpm.IsExist -and $Null -ine $_.NPM) -or
			($RegistryPipx.IsExist -and $Null -ine $_.Pipx) -or
			($RegistryWmic.IsExist -and $Null -ine $_.WMIC) -or
			$Null -ine $_.Env -or
			$Null -ine $_.($OsPathPropertyName)
		}
}
If ($RegistryDocker.IsExist -and $InputDockerInclude.Count -gt 0 -and $InputOperateAsync) {
	$DockerImageListRaw += Receive-Job -Name "Docker/List" -Wait -AutoRemoveJob -ErrorAction 'Continue'
}
$DockerImageRemove += $DockerImageListRaw |
	Join-String -Separator ',' -OutputPrefix '[' -OutputSuffix ']' |
	ConvertFrom-Json -Depth 100 -ErrorAction 'Continue' |
	ForEach-Object -Process { "$($_.Repository)$(($_.Tag.Length -gt 0) ? ":$($_.Tag)" : '')" } |
	Where-Object -FilterScript { (Test-StringMatchRegEx -Item $_ -Matcher $InputDockerInclude) -and !(Test-StringMatchRegEx -Item $_ -Matcher $InputDockerExclude) }
If ($GeneralRemove.Count -gt 0) {
	Write-Host -Object "Removable item [$($GeneralRemove.Count)]: $(
		$GeneralRemove |
			Select-Object -ExpandProperty 'Name' |
			Sort-Object |
			Join-String -Separator ', '
	)"
}
If ($DockerImageRemove.Count -gt 0) {
	Write-Host -Object "Removable Docker image [$($DockerImageRemove.Count)]: $(
		$DockerImageRemove |
			Sort-Object |
			Join-String -Separator ', '
	)"
}
$Script:ErrorActionPreference = 'Continue'
If ($RegistryDocker.IsExist) {
	If ($InputOperateAsync) {
		Write-Host -Object '[ASYNC] Remove Docker image.'
		$Null = Start-Job -Name "Docker/Remove" -ScriptBlock $RegistryDocker.ScriptRemove -ArgumentList @(, $DockerImageRemove)
	}
	Else {
		ForEach ($_DI In $DockerImageRemove) {
			Write-Host -Object "Remove Docker image ``$_DI``."
			Invoke-Command -ScriptBlock $RegistryDocker.ScriptRemove -ArgumentList @(, $_DI) |
				Write-GitHubActionsDebug
		}
	}
}
Function Invoke-GeneralOptimizeOperation {
	[CmdletBinding()]
	[OutputType([Void])]
	Param (
		[Parameter(Mandatory = $True, Position = 0)][PSCustomObject[]]$Queue,
		[Parameter(Mandatory = $True, Position = 1)][UInt64]$Index
	)
	If ($InputOperateAsync) {
		[String[]]$QueueAPT = $Queue |
			ForEach-Object -Process {
				$_.APT |
					Write-Output
			}
		[String[]]$QueueChocolatey = $Queue |
			ForEach-Object -Process {
				$_.Chocolatey |
					Write-Output
			}
		[String[]]$QueueHomebrew = $Queue |
			ForEach-Object -Process {
				$_.Homebrew |
					Write-Output
			}
		[String[]]$QueueNPM = $Queue |
			ForEach-Object -Process {
				$_.NPM |
					Write-Output
			}
		[String[]]$QueuePipx = $Queue |
			ForEach-Object -Process {
				$_.Pipx |
					Write-Output
			}
		[String[]]$QueueWMIC = $Queue |
			ForEach-Object -Process {
				$_.WMIC |
					Write-Output
			}
		[PSCustomObject[]]$QueueFSPlain = $Queue |
			Where-Object -FilterScript {
				$Null -ieq $_.APT -and $Null -ieq $_.Chocolatey -and $Null -ieq $_.Homebrew -and $Null -ieq $_.NPM -and $Null -ieq $_.Pipx -and $Null -ieq $_.WMIC -and (
					$Null -ine $_.Env -or
					$Null -ine $_.($OsPathPropertyName)
				)
			}
		[PSCustomObject[]]$QueueFSRest = $Queue |
			Where-Object -FilterScript {
				($Null -ine $_.APT -or $Null -ine $_.Chocolatey -or $Null -ine $_.Homebrew -or $Null -ine $_.NPM -or $Null -ine $_.Pipx -or $Null -ine $_.WMIC) -and (
					$Null -ine $_.Env -or
					$Null -ine $_.($OsPathPropertyName)
				)
			}
		If ($RegistryAPT.IsExist -and $QueueAPT.Count -gt 0) {
			Write-Host -Object "[ASYNC] Remove APT package with postpone #$Index."
			$Null = Start-Job -Name "$Index/PM/APT" -ScriptBlock $APTCommandUninstallPackage -ArgumentList @(, $QueueAPT)
		}
		If ($RegistryChocolatey.IsExist -and $QueueChocolatey.Count -gt 0) {
			Write-Host -Object "[ASYNC] Remove Chocolatey package with postpone #$Index."
			$Null = Start-Job -Name "$Index/PM/Chocolatey" -ScriptBlock $ChocolateyCommandUninstallPackage -ArgumentList @(, $QueueChocolatey)
		}
		If ($RegistryHomebrew.IsExist -and $QueueHomebrew.Count -gt 0) {
			Write-Host -Object "[ASYNC] Remove Homebrew package with postpone #$Index."
			$Null = Start-Job -Name "$Index/PM/Homebrew" -ScriptBlock $HomebrewCommandUninstallPackage -ArgumentList @(, $QueueHomebrew)
		}
		If ($RegistryNpm.IsExist -and $QueueNPM.Count -gt 0) {
			Write-Host -Object "[ASYNC] Remove NPM package with postpone #$Index."
			$Null = Start-Job -Name "$Index/PM/NPM" -ScriptBlock $NPMCommandUninstallPackage -ArgumentList @(, $QueueNPM)
		}
		If ($RegistryPipx.IsExist -and $QueuePipx.Count -gt 0) {
			Write-Host -Object "[ASYNC] Remove Pipx package with postpone #$Index."
			$Null = Start-Job -Name "$Index/PM/Pipx" -ScriptBlock $PipxCommandUninstallPackage -ArgumentList @(, $QueuePipx)
		}
		If ($RegistryWmic.IsExist -and $QueueWMIC.Count -gt 0) {
			Write-Host -Object "[ASYNC] Remove WMIC package with postpone #$Index."
			$Null = Start-Job -Name "$Index/PM/WMIC" -ScriptBlock $WMICCommandUninstallPackage -ArgumentList @(, $QueueWMIC)
		}
		If ($QueueFSPlain.Count -gt 0) {
			ForEach ($FSPlain In $QueueFSPlain) {
				Write-Host -Object "[ASYNC] Remove $($FSPlain.Description) file with postpone #$Index."
				$Null = Start-Job -Name "$Index/FSPlain/$($FSPlain.Name)" -ScriptBlock {
					ForEach ($EnvName In ($Using:FSPlain).Env) {
						[String]$EnvValue = Get-Content -LiteralPath "Env:\$EnvName" -ErrorAction 'SilentlyContinue'
						If ($EnvValue.Length -gt 0 -and (Test-Path -LiteralPath $EnvValue)) {
							Get-ChildItem -LiteralPath $EnvValue -Force -ErrorAction 'Continue' |
								Remove-Item -Recurse -Force -Confirm:$False -ErrorAction 'Continue'
						}
					}
					ForEach ($Path In ($Using:FSPlain).($Using:OsPathPropertyName)) {
						[String]$PathResolve = ($Path -imatch '\$Env:') ? (Invoke-Expression -Command "`"$Path`"") : $Path
						If ($PathResolve.Length -gt 0 -and (Test-Path -LiteralPath $PathResolve)) {
							Get-ChildItem -LiteralPath $PathResolve -Force -ErrorAction 'Continue' |
								Remove-Item -Recurse -Force -Confirm:$False -ErrorAction 'Continue'
						}
					}
				}
			}
		}
		If ($QueueFSRest.Count -gt 0) {
			$Null = Wait-Job -Name "$Index/PM/*" -ErrorAction 'SilentlyContinue'
			ForEach ($FSRest In $QueueFSRest) {
				Write-Host -Object "[ASYNC] Remove $($FSRest.Description) file with postpone #$Index."
				$Null = Start-Job -Name "$Index/FSRest/$($FSRest.Name)" -ScriptBlock {
					ForEach ($EnvName In ($Using:FSRest).Env) {
						[String]$EnvValue = Get-Content -LiteralPath "Env:\$EnvName" -ErrorAction 'SilentlyContinue'
						If ($EnvValue.Length -gt 0 -and (Test-Path -LiteralPath $EnvValue)) {
							Get-ChildItem -LiteralPath $EnvValue -Force -ErrorAction 'Continue' |
								Remove-Item -Recurse -Force -Confirm:$False -ErrorAction 'Continue'
						}
					}
					ForEach ($Path In ($Using:FSRest).($Using:OsPathPropertyName)) {
						[String]$PathResolve = ($Path -imatch '\$Env:') ? (Invoke-Expression -Command "`"$Path`"") : $Path
						If ($PathResolve.Length -gt 0 -and (Test-Path -LiteralPath $PathResolve)) {
							Get-ChildItem -LiteralPath $PathResolve -Force -ErrorAction 'Continue' |
								Remove-Item -Recurse -Force -Confirm:$False -ErrorAction 'Continue'
						}
					}
				}
			}
		}
		$Null = Wait-Job -Name "$Index/*" -ErrorAction 'SilentlyContinue'
	}
	Else {
		ForEach ($Item In $Queue) {
			If ($RegistryAPT.IsExist -and $Null -ine $Item.APT) {
				Write-Host -Object "Remove $($Item.Description) via APT."
				Invoke-Command -ScriptBlock $APTCommandUninstallPackage -ArgumentList @(, $Item.APT) |
					Write-GitHubActionsDebug
			}
			If ($RegistryChocolatey.IsExist -and $Null -ine $Item.Chocolatey) {
				Write-Host -Object "Remove $($Item.Description) via Chocolatey."
				Invoke-Command -ScriptBlock $ChocolateyCommandUninstallPackage -ArgumentList @(, $Item.Chocolatey) |
					Write-GitHubActionsDebug
			}
			If ($RegistryHomebrew.IsExist -and $Null -ine $Item.Homebrew) {
				Write-Host -Object "Remove $($Item.Description) via Homebrew."
				Invoke-Command -ScriptBlock $HomebrewCommandUninstallPackage -ArgumentList @(, $Item.Homebrew) |
					Write-GitHubActionsDebug
			}
			If ($RegistryNpm.IsExist -and $Null -ine $Item.NPM) {
				Write-Host -Object "Remove $($Item.Description) via NPM."
				Invoke-Command -ScriptBlock $NPMCommandUninstallPackage -ArgumentList @(, $Item.NPM) |
					Write-GitHubActionsDebug
			}
			If ($RegistryPipx.IsExist -and $Null -ine $Item.Pipx) {
				Write-Host -Object "Remove $($Item.Description) via Pipx."
				Invoke-Command -ScriptBlock $PipxCommandUninstallPackage -ArgumentList @(, $Item.Pipx) |
					Write-GitHubActionsDebug
			}
			If ($RegistryWmic.IsExist -and $Null -ine $Item.WMIC) {
				Write-Host -Object "Remove $($Item.Description) via WMIC."
				Invoke-Command -ScriptBlock $WMICCommandUninstallPackage -ArgumentList @(, $Item.WMIC) |
					Write-GitHubActionsDebug
			}
			If ($Null -ine $Item.Env -or $Null -ine $Item.($OsPathPropertyName)) {
				Write-Host -Object "Remove $($Item.Description) files."
				ForEach ($EnvName In $Item.Env) {
					[String]$EnvValue = Get-Content -LiteralPath "Env:\$EnvName" -ErrorAction 'SilentlyContinue'
					If ($EnvValue.Length -gt 0 -and (Test-Path -LiteralPath $EnvValue)) {
						Get-ChildItem -LiteralPath $EnvValue -Force -ErrorAction 'Continue' |
							Remove-Item -Recurse -Force -Confirm:$False -ErrorAction 'Continue'
					}
				}
				ForEach ($Path In $Item.($OsPathPropertyName)) {
					[String]$PathResolve = ($Path -imatch '\$Env:') ? (Invoke-Expression -Command "`"$Path`"") : $Path
					If ($PathResolve.Length -gt 0 -and (Test-Path -LiteralPath $PathResolve)) {
						Get-ChildItem -LiteralPath $PathResolve -Force -ErrorAction 'Continue' |
							Remove-Item -Recurse -Force -Confirm:$False -ErrorAction 'Continue'
					}
				}
			}
		}
	}
}
ForEach ($Index In (
	$GeneralRemove |
		Select-Object -ExpandProperty 'Postpone' |
		Sort-Object -Unique
)) {
	Invoke-GeneralOptimizeOperation -Queue (
		$GeneralRemove |
			Where-Object -FilterScript { $_.Postpone -eq $Index }
	) -Index $Index
}
If ($InputOperateAsync) {
	$Null = Wait-Job -ErrorAction 'SilentlyContinue'
	If (Get-GitHubActionsDebugStatus) {
		Get-Job |
			ForEach-Object -Process {
				Enter-GitHubActionsLogGroup -Title "$($_.Name) ($($_.State))"
				Receive-Job -Name $_.Name -Wait -AutoRemoveJob
				Exit-GitHubActionsLogGroup
			}
	}
	Else {
		Get-Job |
			Remove-Job -Force -Confirm:$False
	}
}
If ($RegistryAPT.IsExist) {
	If ($InputAptPrune) {
		Write-Host -Object 'Prune APT package.'
		apt-get --assume-yes autoremove *>&1 |
			Write-GitHubActionsDebug
	}
	If ($InputAptClean) {
		Write-Host -Object 'Remove APT cache.'
		apt-get --assume-yes clean *>&1 |
			Write-GitHubActionsDebug
	}
}
If ($RegistryDocker.IsExist) {
	If ($InputDockerPrune) {
		Write-Host -Object 'Prune Docker image.'
		docker image prune --force *>&1 |
			Write-GitHubActionsDebug
	}
	If ($InputDockerClean) {
		Write-Host -Object 'Clean Docker cache.'
		docker system prune --force *>&1 |
			Write-GitHubActionsDebug
	}
}
If ($RegistryHomebrew.IsExist) {
	If ($InputHomebrewPrune) {
		Write-Host -Object 'Prune Homebrew package.'
		brew autoremove *>&1 |
			Write-GitHubActionsDebug
	}
	If ($InputHomebrewClean) {
		Write-Host -Object 'Remove Homebrew cache.'
		brew cleanup --prune=all -s *>&1 |
			Write-GitHubActionsDebug
	}
}
If ($RegistryNpm.IsExist) {
	If ($InputNpmPrune) {
		Write-Host -Object 'Prune NPM package.'
		npm prune *>&1 |
			Write-GitHubActionsDebug
	}
	If ($InputNpmClean) {
		Write-Host -Object 'Remove NPM cache.'
		npm cache clean --force *>&1 |
			Write-GitHubActionsDebug
	}
}
If ($InputOsSwap) {
	If ($Env:RUNNER_OS -iin @('Linux')) {
		Write-Host -Object 'Remove Linux page/swap file.'
		swapoff -a *>&1 |
			Write-GitHubActionsDebug
		Remove-Item -LiteralPath '/mnt/swapfile' -Recurse -Force -Confirm:$False -ErrorAction 'Continue'
	}
}
$Script:ErrorActionPreference = 'Stop'
[String]$DiskSpaceAfter = Get-DiskSpace
Write-Host -Object @"
===== DISK SPACE BEFORE =====
$DiskSpaceBefore

===== DISK SPACE AFTER =====
$DiskSpaceAfter
"@
$LASTEXITCODE = 0
