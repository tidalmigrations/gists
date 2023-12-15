# Get the CPU count
$cpu_count = (Get-WmiObject -Class Win32_ComputerSystem).NumberOfLogicalProcessors

# Get the CPU name
$cpu_name = (Get-WmiObject -Class Win32_Processor).Name

# Get the hostname
$hostname = $env:COMPUTERNAME

# Get the operating system
$os = (Get-WmiObject -Class Win32_OperatingSystem).Caption

# Get the operating system version
$os_version = (Get-WmiObject -Class Win32_OperatingSystem).Version

# Print the information in CSV format
Write-Output "CPU Count,CPU Name,Hostname,Operating System,Operating System Version"
Write-Output "$cpu_count,`"$cpu_name`",$hostname,$os,$os_version"
