#!/bin/bash
input=expressways.csv
OLDIFS=$IFS
IFS=","
mkdir -p audit
touch audit/vcs_audit.csv
output=audit/vcs_audit.csv
count=0
total_devices=$(cat "$input" | wc -l)
total_devices=$(( $total_devices - 1 ))
declare -A warnings

help() {
   printf "\nAudit Script for Cisco VCS / Expressway Devices"
   printf "\nThis script requires an 'expressway.csv' file containing IPs and credentials to run."
   printf "\nSee the example templates or enrollment template for CSV file format."
   printf "\n\nSyntax: ./vcs-audit.sh [-h|-w]"
   printf "\n\nOptions:"
   printf "\nh     Print this help dialog"
   printf "\nw     Only collect device warnings\n\n"
}

icmp_check () {
    ping_output=$(ping -c 2 $1 | grep "received" | awk -F '[ ,]' '{print $5}')

    if [ -z "$ping_output" ]; then
        ping_result="Ping Output Empty"
    
    elif (( "$ping_output" > 0 )); then
        ping_result="ICMP Succeeded"
    
    else
        ping_result="ICMP Failed"
    fi
}

port_check () {
    declare -A -g ports=( [22]="" [443]="" [7443]="" [8443]="" )
    
    for port in ${!ports[@]}; do
        result=$(/opt/bmn/bin/tcpcheck.php $1 $port 2)
        if [ $result -eq 1 ]; then
            ports[$port]="$port:Up"
        else
            ports[$port]="$port:Down"
        fi
    done
    port_status=${ports[@]}

    if [ ${ports[443]} == "443:Up" ]; then
        admin_port="443"
    elif [ ${ports[8443]} == "8443:Up" ]; then
        admin_port="8443"
    elif [ ${ports[7443]} == "7443:Up" ]; then
        admin_port="7443"
    else
        admin_port="Down"
    fi
}

expect_ssh_login () {
    if [ ${ports[22]} == "22:Up" ]; then
        
        expect_output=$(
            /usr/bin/expect << EOF
            spawn ssh -o ConnectTimeout=10 "$2@$1"
            set timeout 30
            expect {
                "Connection timed out" {exit}
                "RSA key fingerprint" {send "yes\r"; exp_continue}
                "ECDSA key fingerprint" {send "yes\r"; exp_continue}
                "current password: " {send "\x03"; exit}
                "Permission denied" {send "\x03"; exit}
                -re "\[P|p]assword: " {send "$3\r"; exp_continue}
                "~ # " {send "\r"}
            }
            expect "~ # "
            send "hostname\r"
            expect "~ # "
            send "exit\r"
            expect eof
EOF
        )
        expect_return=$?
        device_name=$(echo "$expect_output" | sed -n '/hostname/{n;p}' | tr -d '\r')
        auth_error=$(echo "$expect_output" | grep "Permission denied" | awk -F '[:(]' '{print $2}' | awk '{$1=$1};1')
        conn_error=$(echo "$expect_output" | grep "ssh: connect to host" | awk -F '[:]' '{print $3}' | awk '{$1=$1};1')

        if [ -n "$auth_error" ]; then
            device_name="SSH Hostname Not Found"
            ssh_login="$auth_error"
        
        elif [ -n "$conn_error" ]; then
            device_name="SSH Hostname Not Found"
            ssh_login="$conn_error"
        
        elif [ "$expect_return" -gt 0 ]; then
            device_name="SSH Hostname Not Found"
            ssh_login="SSH Login Failed - Return Code: $expect_return"

        elif [ -n "$expect_output" ] && [ -n "$device_name" ]; then
            ssh_login="SSH Login Successful"
        
        else
            device_name="SSH Hostname Not Found"
            ssh_login="SSH Login Failed - Undefined Error"
        fi

    else
        device_name="SSH Hostname Not Found"
        ssh_login="Port 22 is Down"
    fi 
}

collect_history_xml () {
    if [ "$admin_port" != "Down" ]; then

        history_data=$(curl -k -s -S -u $2:$3 --connect-timeout 5 https://$1:$admin_port/history.xml 2>&1 | sed -n 1,15p)
        
        history_xml_error=$(echo "$history_data" | grep -i "<title>[0-9]\{3\}" | awk -F '[><]' '{print $3}')
        history_curl_error=$(echo "$history_data" | grep "curl: ([0-9]\{1,2\})")
        history_curl_return=$(echo "$history_curl_error" | awk -F '[()]' '{print $2}')
        history_curl_error_msg=$(echo "$history_curl_error" | awk -F '[:()]' '{print $4}' | awk '{$1=$1};1')
        vcs=""

        if [ -n "$history_xml_error" ]; then
            history_xml="$history_xml_error"
        
        elif [ -n "$history_curl_error" ] && [ "$history_curl_return" -gt 0 ]; then
            history_xml="$history_curl_error_msg"
        
        else
            vcs=$(echo "$history_data" | head -15 | grep -i 'product="TANDBERG VCS"')
            
            if [ -n "$vcs" ]; then
                history_xml="History Data Collected"
            
            else
                history_xml="History XML Failed - Undefined Error"
            fi
        fi

    else
        history_xml="Admin Ports are Down"
    fi
}

collect_status_xml () {
    if [ "$admin_port" != "Down" ]; then

        status_data=$(curl -k -s -S -u $2:$3 --connect-timeout 5 https://$1:$admin_port/status.xml 2>&1)

        status_xml_error=$(echo "$status_data" | grep -i "<title>[0-9]\{3\}" | awk -F '[><]' '{print $3}')
        status_curl_error=$(echo "$status_data" | grep "curl: ([0-9]\{1,2\})")
        status_curl_return=$(echo "$status_curl_error" | awk -F '[()]' '{print $2}')
        status_curl_error_msg=$(echo "$status_curl_error" | awk -F '[:()]' '{print $4}' | awk '{$1=$1};1')
        status_data_wc=$(echo "$status_data" | wc -l)

        if [ -n "$status_xml_error" ]; then
            status_xml="$status_xml_error"
            serial_number="Serial Number Not Found"
            software_version="Software Version Not Found"

        elif [ -n "$status_curl_error" ] && [ "$status_curl_return" -gt 0 ]; then
            status_xml="$status_curl_error_msg"
            serial_number="Serial Number Not Found"
            software_version="Software Version Not Found"

        elif [ "$status_data_wc" -lt 250 ]; then
            status_xml="Status XML Failed - Lines Collected: "$status_data_wc""
            serial_number="Serial Number Not Found"
            software_version="Software Version Not Found"
        
        else
            software_start=$(echo "$status_data" | grep -n "<Software item=\"1\">" | cut -d':' -f1)
            software_end=$(echo "$status_data" | grep -n "<\/Software>" | cut -d':' -f1)
            software_subset=$(echo "$status_data" | sed -n $software_start,$software_end'p')

            hardware_start=$(echo "$status_data" | grep -n "<Hardware item=\"1\">" | cut -d':' -f1)
            hardware_end=$(echo "$status_data" | grep -n "<\/Hardware>" | cut -d':' -f1)
            hardware_subset=$(echo "$status_data" | sed -n $hardware_start,$hardware_end'p')

            warnings_subset=$(echo "$status_data" | grep "<Warnings item=\"1\">" | awk -F '<Warnings item="1">|</Warnings>' '{print $2}')

            if [ "${ports[22]}" == "22:Down" ]; then
                warnings[$host]=$(echo "$warnings_subset" | sed 's/<\/Warning>/&\'$'\n/g' | sed 's/,/;/g')
            else
                warnings[$device_name]=$(echo "$warnings_subset" | sed 's/<\/Warning>/&\'$'\n/g' | sed 's/,/;/g')
            fi

            status_xml="Status Data Collected"
            software_version=$(echo "$software_subset" | grep "<Version item=\"1\">" | awk -F '[><]' '{print $3}')
            serial_number=$(echo "$hardware_subset" | grep "<SerialNumber item=\"1\">" | awk -F '[><]' '{print $3}')

            if [ -z "$serial_number" ]; then
                serial_number="Serial Number Not Found"
            fi

            if [ -z "$software_version" ]; then
                software_version="Software Version Not Found"
            fi
        fi

    else
        status_xml="Admin Ports are Down"
        serial_number="Serial Number Not Found"
        software_version="Software Version Not Found"
    fi
}

parse_warning_data () {
    printf "\n" >> $output
    for device in ${!warnings[@]}; do
        
        if [ -z "${warnings[$device]}" ]; then
            printf "\n\nNo Warnings Found for $device" >> $output
        
        else
            printf "\n\nWarnings for $device:" >> $output
            
            for warning in "${warnings[$device]}"; do
                formatted_warning=$(echo "$warning" | awk -F '<Reason item=\"[[:digit:]]*\">|</Reason>|<State item=\"[[:digit:]]*\">|</State>' '{print ","$4","$2}')
                printf "\n$formatted_warning" >> $output
            done
        fi
    done
}

collect_warnings() {
    printf "\n'Warnings Only' Mode Activated!\n"
    {
        read
        while IFS=, read -r host vcs_root root_pass vcs_admin admin_pass; do 

            count=$(( $count + 1 ))
            printf "\nProcessing Device: $count of $total_devices - $host\n"
    
            port_check "$host"
            expect_ssh_login "$host" "$vcs_root" "$root_pass"
            collect_status_xml "$host" "$vcs_admin" "$admin_pass"
            if [ "$admin_port" == "Down" ]; then
                printf "\n\n$status_xml to $host" >> $output
            fi
        done
    } < $input

    parse_warning_data

    printf "\n"
    printf "\n\nEOF\n\n" >> $output

    IFS=$OLDIFS
    exit
}

if [ ! -f "$input" ]; then
    printf "\n$input File Not Found\n"
    help
    exit 9
fi

while getopts ":hw" option; do
    case $option in
        h) # Display Help
            help
            exit;;
        w) # Collect Warnings
            collect_warnings
            exit;;
        ?) # Invalid Option
            printf "\nError - Invalid Option: $1\n"
			help
            exit;;
    esac
done

printf "\nScript ran on $(date)\n\n" >> $output
printf "\nHost IP,Hostname,Serial Number,Software Version,Status Data,History Data,SSH Login,Ping Result,Admin Port,Port Status" >> $output

{
    read
    while IFS=, read -r host vcs_root root_pass vcs_admin admin_pass; do 
        count=$(( count + 1 ))
        printf "\nProcessing Device: $count of $total_devices - $host\n"

        icmp_check "$host"
        port_check "$host"
        expect_ssh_login "$host" "$vcs_root" "$root_pass"
        collect_history_xml "$host" "$vcs_admin" "$admin_pass"
        collect_status_xml "$host" "$vcs_admin" "$admin_pass"

        printf "\n$host,$device_name,$serial_number,$software_version,$status_xml,$history_xml,$ssh_login,$ping_result,$admin_port,$port_status" >> $output
    done
} < $input

parse_warning_data

printf "\n"
printf "\n\nEOF\n\n" >> $output

IFS=$OLDIFS
exit
