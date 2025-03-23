# Author: Chris Fryer - Atturra
# IMPORTANT: An instance of this script should be ran against each vCenter in your environment.
#
# Make sure VMware PowerCLI is installed. If not, run:
# Install-Module -Name VMware.PowerCLI -Scope AllUsers -Force

# Import the PowerCLI Module
Import-Module VMware.PowerCLI

# Parameters - update these with your environment details
	# Create a secure string for the password (do this once)
		#$securePassword = Read-Host -AsSecureString "Enter your vCenter password"
		#$securePassword | ConvertFrom-SecureString | Out-File "vcenter_encrypted.txt"
# Update vCenter details - one script per vcenter
$vCenterServer = "IP Address or Hostname HERE"
# Update username details
$username = "username@vsphere.local"
$securePasswordText = Get-Content "vcenter_encrypted.txt" #update with the full folder pather to your text file
$securePassword = $securePasswordText | ConvertTo-SecureString
$credentials = New-Object System.Management.Automation.PSCredential($username, $securePassword)

# Suppress certificate warnings (optional, remove in production environments)
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

try {
    # Connect to vCenter Server
    Connect-VIServer -Server $vCenterServer -Credential $credentials -ErrorAction Stop
    
    Write-Host "Connected to $vCenterServer successfully" -ForegroundColor Green
    
    # Get all VMs
    $vms = Get-VM
    
    # Create an array to store snapshot information
    $snapshotInfo = @()
    
    # Loop through each VM to get snapshot details
    foreach ($vm in $vms) {
        $snapshots = Get-Snapshot -VM $vm
        
        if ($snapshots) {
            Write-Host "Processing snapshots for VM: $($vm.Name)" -ForegroundColor Cyan
            
            # Get all snapshot-related events for this VM with a larger sample size
            $snapshotEvents = Get-VIEvent -Entity $vm -MaxSamples 5000 | Where-Object {
                # Focus on Create snapshot events and task events
                ($_.FullFormattedMessage -match "Task: Create virtual machine snapshot" -or
                 $_.FullFormattedMessage -match "Created snapshot" -or
                 $_.EventTypeId -eq "VmBeingSnapshotted")
            }
            
            Write-Host "  Found $($snapshotEvents.Count) snapshot-related events" -ForegroundColor Gray
            
            # Limit the number of events logged to CSV for clarity
            $eventInfo = @()
            foreach ($event in $snapshotEvents | Select-Object -First 20) {
                $eventInfo += [PSCustomObject]@{
                    FullFormattedMessage = $event.FullFormattedMessage
                    CreatedTime = $event.CreatedTime
                    UserName = $event.UserName
                    EventTypeId = $event.EventTypeId
                    ChainId = $event.ChainId
                }
            }
            
            # Export event information to a CSV for reference
            #$eventInfo | Export-Csv -Path ".\SnapshotEvents-$($vm.Name).csv" -NoTypeInformation
            #Write-Host "  Exported event details to SnapshotEvents-$($vm.Name).csv" -ForegroundColor Gray
            
            foreach ($snapshot in $snapshots) {
                $creator = "Unknown"
                $eventFound = $false
                
                Write-Host "  Processing snapshot '$($snapshot.Name)' created on $($snapshot.Created)" -ForegroundColor Yellow
                
                # PRIMARY METHOD: Look for "Task: Create virtual machine snapshot" events
                $createEvents = $snapshotEvents | Where-Object {
                    $_.FullFormattedMessage -match "Task: Create virtual machine snapshot" -and
                    [Math]::Abs(($_.CreatedTime - $snapshot.Created).TotalMinutes) -lt 2
                } | Sort-Object { [Math]::Abs(($_.CreatedTime - $snapshot.Created).TotalMinutes) }
                
                if ($createEvents.Count -gt 0) {
                    $bestEvent = $createEvents[0]  # Get closest match by time
                    $timeDiff = [Math]::Round([Math]::Abs(($bestEvent.CreatedTime - $snapshot.Created).TotalMinutes), 1)
                    
                    if ($bestEvent.UserName -and $bestEvent.UserName -ne "") {
                        $creator = $bestEvent.UserName
                        $eventFound = $true
                        Write-Host "    Found creator from 'Create snapshot' event: $creator (time diff: $timeDiff min)" -ForegroundColor Green
                        Write-Host "    Event message: $($bestEvent.FullFormattedMessage)" -ForegroundColor Gray
                    }
                }
                
                # BACKUP METHOD 1: If not found, try to match by snapshot name if available
                if (-not $eventFound -and $snapshot.Name -ne "Current" -and $snapshot.Name -ne "") {
                    Write-Host "    Looking for events mentioning snapshot name..." -ForegroundColor Yellow
                    
                    $nameEvents = $snapshotEvents | Where-Object {
                        $_.FullFormattedMessage -match [regex]::Escape($snapshot.Name) -and
                        $_.UserName -and $_.UserName -ne ""
                    } | Sort-Object { [Math]::Abs(($_.CreatedTime - $snapshot.Created).TotalMinutes) }
                    
                    if ($nameEvents.Count -gt 0) {
                        $creator = $nameEvents[0].UserName
                        $eventFound = $true
                        $timeDiff = [Math]::Round([Math]::Abs(($nameEvents[0].CreatedTime - $snapshot.Created).TotalMinutes), 1)
                        Write-Host "    Found creator from name-matched event: $creator (time diff: $timeDiff min)" -ForegroundColor Green
                    }
                }
                
                # BACKUP METHOD 2: Time-based correlation with a wider window
                if (-not $eventFound) {
                    Write-Host "    Using time-based correlation with wider window..." -ForegroundColor Yellow
                    
                    # Get all events within 10 minutes of snapshot creation
                    $timeEvents = $snapshotEvents | Where-Object {
                        [Math]::Abs(($_.CreatedTime - $snapshot.Created).TotalMinutes) -lt 10 -and
                        $_.UserName -and $_.UserName -ne ""
                    } | Sort-Object { [Math]::Abs(($_.CreatedTime - $snapshot.Created).TotalMinutes) }
                    
                    if ($timeEvents.Count -gt 0) {
                        $creator = $timeEvents[0].UserName
                        $timeDiff = [Math]::Round([Math]::Abs(($timeEvents[0].CreatedTime - $snapshot.Created).TotalMinutes), 1)
                        Write-Host "    Found creator using time correlation: $creator (time diff: $timeDiff min)" -ForegroundColor Green
                        Write-Host "    Event message: $($timeEvents[0].FullFormattedMessage)" -ForegroundColor Gray
                    }
                }
                
                # Add to snapshot info collection
                $snapshotInfo += [PSCustomObject]@{
                    VMName = $vm.Name
                    SnapshotName = $snapshot.Name
                    Description = $snapshot.Description
                    Created = $snapshot.Created
                    Creator = $creator
                    SizeGB = [math]::Round(($snapshot.SizeGB), 2)
                    PowerState = $vm.PowerState
                    DaysOld = [math]::Round(((Get-Date) - $snapshot.Created).TotalDays, 0)
                }
            }
        }
    }
    
    # Display results
	if ($snapshotInfo.Count -gt 0) {
        Write-Host "`nFound $($snapshotInfo.Count) snapshots across $((($snapshotInfo | Select-Object -Property VMName -Unique).Count)) VMs`n" -ForegroundColor Yellow
        
        # Output the results to console (hide diagnostic fields)
        $snapshotInfo | Select-Object -Property VMName, SnapshotName, Description, Created, Creator, SizeGB, PowerState, DaysOld | Format-Table -AutoSize
        
        # Optional: Export to CSV
        $dateStamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $csvPath = ".\VMSnapshots-$dateStamp.csv"
        $snapshotInfo | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "Results exported to $csvPath" -ForegroundColor Cyan
        
        # Optional: Show snapshots older than 3 days and send email notification
        $oldSnapshots = $snapshotInfo | Where-Object { $_.DaysOld -gt 3 }
        if ($oldSnapshots) {
            Write-Host "`nWARNING: Found snapshots older than 3 days:" -ForegroundColor Red
            $oldSnapshots | Format-Table -AutoSize
            
            # Email notification parameters - update these with your details
					# Create a secure string for the password (do this once)
						#$securePassword = Read-Host -AsSecureString "Enter your Email Account password"
						#$securePassword | ConvertFrom-SecureString | Out-File "email_encrypted.txt"
            # Email notification parameters for Exchange
			$smtpServer = "YourEmailServer"  # Update with your Exchange server, IP or Hostname
            $smtpPort = 587		# Update if needed
            $fromAddress = "EmailUser@YourDomain.com"  # Update with your sender address
            $toAddress = "YourITManagementTeam@YourDomain.com"  # Update with recipient address(es) # Can be multiple recipients separated by commas
			# Email Creds via secure string
			$emailusername = "EmailUser" #The email Username you will authenticate to the email server with.
			$emailsecurePasswordText = Get-Content "email_encrypted.txt" #update with the full folder pather to your text file
			$emailsecurePassword = $emailsecurePasswordText | ConvertTo-SecureString
			$emailCred = New-Object System.Management.Automation.PSCredential($emailusername, $emailsecurePassword)
			
			# Bypass certificate validation (only if needed)
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
			
			# Create the subject line with the count explicitly converted to string
            $snapshotCount = $oldSnapshots.Count
            $emailSubject = "VMware Snapshot Alert: $snapshotCount snapshots older than 3 days"
			
			$emailParams = @{
                SmtpServer = $smtpServer
                Port = $smtpPort
                From = $fromAddress
                To = $toAddress
                Subject = $emailSubject
                Body = $null
                BodyAsHtml = $true
                # Optional: Uncomment for SMTP authentication
                Credential = $emailCred
                UseSSL = $true
            }
            
            # Create an HTML report for the email body
            $htmlHeader = @"
            <style>
                table {
                    border-collapse: collapse;
                    width: 100%;
                    font-family: Arial, sans-serif;
                }
                th, td {
                    text-align: left;
                    padding: 8px;
                    border: 1px solid #ddd;
                }
                th {
                    background-color: #4472C4;
                    color: white;
                }
                tr:nth-child(even) {
                    background-color: #f2f2f2;
                }
                .warning {
                    color: red;
                    font-weight: bold;
                }
                h1, h2 {
                    font-family: Arial, sans-serif;
                }
            </style>
"@
            
            $htmlBody = @"
            <h1>VMware Snapshot Alert</h1>
            <p>The following $($oldSnapshots.Count) snapshots are older than 3 days and should be reviewed:</p>
            <table>
                <tr>
                    <th>VM Name</th>
                    <th>Snapshot Name</th>
                    <th>Description</th>
                    <th>Created</th>
                    <th>Creator</th>
                    <th>Size (GB)</th>
                    <th>Age (Days)</th>
                </tr>
"@
            
            foreach ($snap in $oldSnapshots) {
                $rowColor = if ($snap.DaysOld -gt 14) { ' style="background-color: #FFB6B6;"' } else { "" }
				$createdFormatted = $snap.Created.ToString("dd/MM/yyyy HH:mm:ss")
                $htmlBody += @"
                <tr$rowColor>
                    <td>$($snap.VMName)</td>
                    <td>$($snap.SnapshotName)</td>
                    <td>$($snap.Description)</td>
                    <td>$createdFormatted</td>
                    <td>$($snap.Creator)</td>
                    <td>$($snap.SizeGB)</td>
                    <td>$($snap.DaysOld)</td>
                </tr>
"@
            }
            
            $htmlBody += @"
            </table>
            <p>This report was generated automatically on $(Get-Date -Format "dd/MM/yyyy HH:mm") using live data from vCenter Server: $vCenterServer.</p>
            <p><b>Total snapshot storage consumed: $([math]::Round(($oldSnapshots | Measure-Object -Property SizeGB -Sum).Sum, 2)) GB</b></p>
			<p>INFO: This alert was generated using PowerShell, with the VMware.PowerCLI module and is intended to run daily as a scheduled task. <br>CAUTION: Holding manual VMware snapshots can impact system performance and lead to VM corruption and outages - for extended duration snapshots, please initiate additional backups via protection software that removes the VMware snapshot after a backup (i.e. using VMware data protection framework such as VADP from Commvault).</p> 
			<p><i>For information or changes to this notification please contact Chris Fryer.</i></p>
"@
            
            $emailParams.Body = $htmlHeader + $htmlBody
            
            # Attach the CSV report
            if (Test-Path $csvPath) {
                $emailParams.Attachments = $csvPath
            }
            
            # Send the email alert
            try {
                Send-MailMessage @emailParams
                Write-Host "Snapshot alert email sent." -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to send email alert: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "No snapshots older than 3 days found." -ForegroundColor Green
        }
    } else {
        Write-Host "No snapshots found in the environment." -ForegroundColor Green
    }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
}
finally {
    # Disconnect from vCenter
    if ($global:DefaultVIServer) {
        Disconnect-VIServer -Server $global:DefaultVIServer -Confirm:$false
        Write-Host "Disconnected from vCenter Server" -ForegroundColor Green
    }
}