# UC Enrollment Samples

This is a collection of scripting samples written to audit and assist in the enrollment process for Unified Communications devices.

## "endpoint_audit.sh" Bash Script:

Script created for auditing Cisco video endpoints before enrollment. 
Script status is printed to the terminal, output data is parsed and saved in a .csv file.
The following checks are performed:
 - Confirm Hostname & IP
 - ICMP
 - Ports open: 22, 80, 443
 - SSH access
 - Collected XML data:
     - UI Name
     - Serial number
     - Product ID
     - Device status info

### Requires:

 - An 'endpoints.csv' file containing IPs and credentials to run, see templates folder

### Usage:

```./END-Audit.sh # Optional [-h]```

## "vcs_audit.sh" Bash Script:

Script was written to audit Cisco VCS / Expressway devices before enrollment.
Script status is printed to the terminal, output data is parsed and saved in a .csv file.
An optional perameter was created to only collect device warnings if needed.
The following checks are performed:
 - Confirm Hostname & IP
 - ICMP
 - Ports open: 22, 443, 7443, 8443
 - SSH access
 - Collected XML data:
     - Serial Number
     - Software Version
     - Device status info

### Requires:

 - An 'expressways.csv' file containing IPs and credentials to run, see templates folder

### Usage:

```./vcs-audit.sh # Optional [-h|-w]"```

## "vos_mon.sh" Bash Script:

Script for creating the vos_mon monitoring user on Cisco VOS Appliances.
A privilege level 1 account is created and tested with many errors being accounted for.
Script status is printed to the terminal, a device completion report is saved in a text file.

### Requires:

 - An 'appliances.csv' file containing IPs and credentials to run, see templates folder

### Usage:

```./vos_mon.sh # Optional [-h]```

## "vos-audit.sh" Bash Script:

Script for auditing Cisco VOS appliances using TCL over SSH before enrollment. 
Script status is printed to the terminal, audit information is saved in a text file.
Output is gathered for the following commands:
 - show status
 - show account
 - show network cluster
 - show cuc cluster status
 - utils service list
 - show version active

### Requires:

 - An 'appliances.csv' file containing IPs and credentials to run, see templates folder

### Usage:

```./vos-audit.sh # Optional [-h]```
