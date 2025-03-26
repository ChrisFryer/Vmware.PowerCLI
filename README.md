# Vmware.PowerCLI
VMware PowerCLI Projects

The PowerCLI List Snaps Project v2.1
ReadMe file for the Secure Configuration of PowerCLI List Snaps v2.1
Author: Chris Fryer
Date: 23-03-2025

Usage: This email notification and reporting service for VMware Snapshot status has been developed to provide greater situational awareness for IT management teams. By scheduling the script to run every day against each virtual center, IT teams are made aware if a manual snapshot becomes older than 3 days (snapshots older than 14 days will appear red in the report).
Intent: The use of Powershell and vendor libraries (such as VMware.PowerCLI) in this capacity allows for greater customisation and encourages innovation outside of vendor toolsets.


Important: Steps 3,4 and 6,7 need to executed by the same account that will be used in Task Scheduler (e.g. a local or service account)
SETUP Steps
1. Login to you virtual center and create a user (e.g. vsphere.local) 'could also be an AD integrated service account' - and ensure it has permission to the vSphere (note if you have VC's in linked mode, you will need to make sure the account has access to both VC's).
2. Identify the Windows Server you want to schedule the script/s to run from, create a new folder and place the script file in (this will be your working directory).
3. Run the following PowerShell command from the folder you created: >$securePassword = Read-Host -AsSecureString "Enter your vCenter password"
*Enter the password for the user you created that can access the Virtual Center/s
4. Now run this >$securePassword | ConvertFrom-SecureString | Out-File "vcenter_encrypted.txt"
*This will create a file in your working folder (with the script) that encrypts the password for you to call and decrypt when running the script.
5. *For Authenticated Email* Create a user in AD / Exchange and record username/password (for sending emails) - note: An alias email address should be assigned that makes sense for notifications e.g. noreply@YOUR-DOMAIN.COM
6. Run the following PowerShell command from the folder you created: >$securePassword = Read-Host -AsSecureString "Enter your Email Account password"
*Enter the password for the user you created that can send emails from your email server.
7. Now run this >$securePassword | ConvertFrom-SecureString | Out-File "email_encrypted.txt"
*This will create a file in your working folder (with the script) that encrypts the password for you to call and decrypt when running the script.
8. Edit the .PS1 script file and update it with your details:
	a)  $vCenterServer = "IP Address or Hostname HERE"
	b)  $username = "username@vsphere.local"
	c)  $smtpServer = "YourEmailServer" (IP or Hostname)
	d)  $smtpPort = 587 (if needed)
	e)  $fromAddress = "EmailUser@YourDomain.com" (sender address)
	f)  $toAddress = "YourITManagementTeam@YourDomain.com" (Update with multiple recipient or DL - comma separated)
	g)  $emailusername = "EmailUser" (for authentication to the email server)
9. Check your Windows server has the VMware.PowerCLI module for PowerShell installed, by running the command "Import-Module VMware.PowerCLI" - if the command is unknown, then run the command "Install-Module -Name VMware.PowerCLI -Scope AllUsers -Force"
10. Create a batch file in the same folder as your script, which will contain the following details (updating as needed - with your version of powershell and script folder location):
@echo off

"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\Powershell\Snapshot notifications\PowerCLI List Snaps v2.1.ps1"
"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -Command "$csvPath = 'C:\Powershell\Snapshot notifications'; Get-ChildItem -Path $csvPath -Filter 'VMSnapshots-*.csv' | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force"

11. Create the following scheduled task to run daily (at a time where the email will be noticed. e.g. 10:00am)
	a) Under the Actions Tab: Start a Program: Have the Task open the batch file you created.
	b) Ensure the Start in (option) field has the folder location of your powershell script 
	c) ensure the task runs whether the user is logged on or not
	d) ensure a service account or local service user is used
	e) ensure the task runs with highest privileges

TIP: You will need a Batch file and .PS1 script for each vCenter you have.
