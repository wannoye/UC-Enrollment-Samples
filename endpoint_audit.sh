#!/bin/bash

input=endpoints.csv
OLDIFS=$IFS
IFS=","
mkdir -p audit
touch audit/end_audit.csv
output=audit/end_audit.csv
count=0
total_devices=$(cat "$input" | wc -l)
total_devices=$(( $total_devices - 1 ))

help() {
   printf "\nAudit Script for Cisco Video Endpoints"
   printf "\nThis script requires an 'endpoints.csv' file containing IPs and credentials to run."
   printf "\nSee the example 'endpoints.csv' template or enrollment template for CSV file format."
   printf "\n\nSyntax: ./end-audit.sh Optional[-h]"
   printf "\n\nOptions:"
   printf "\nh     Print this help dialog"
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
    declare -A -g ports=( [22]="" [80]="" [443]="" )
    
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
    elif [ ${ports[80]} == "80:Up" ]; then
        admin_port="80"
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
                -re "OK\r" {send "bye\r"}
            }
            expect eof
EOF
        )
        expect_return=$?
        ssh_device_name=$(echo "$expect_output" | grep "Welcome" |  sed -n 's/Welcome to//p' | awk '{$1=$1};1' | tr -d '\r')
        auth_error=$(echo "$expect_output" | grep "Permission denied" | awk -F '[:(]' '{print $2}' | awk '{$1=$1};1' | tr -d '\r')
        conn_error=$(echo "$expect_output" | grep "ssh: connect to host" | awk -F '[:]' '{print $3}' | awk '{$1=$1};1' | tr -d '\r')
        pass_prompt=$(echo "$expect_output" | grep "change your password" | tr -d '\r')
        
        if [ -n "$auth_error" ]; then
            ssh_login="$auth_error"
            ssh_device_name="SSH Hostname Not Found"
        
        elif [ -n "$conn_error" ]; then
            ssh_login="$conn_error"
            ssh_device_name="SSH Hostname Not Found"

        elif [ -n "$pass_prompt" ]; then
            ssh_login="Password Change Required"
            ssh_device_name="SSH Hostname Not Found"
        
        elif [ "$expect_return" -gt 0 ]; then
            ssh_login="SSH Login Failed - Return Code: $expect_return"
            ssh_device_name="SSH Hostname Not Found"

        elif [ -n "$expect_output" ] && [ -n "$ssh_device_name" ]; then
            ssh_login="SSH Login Successful"
        
        else
            ssh_login="SSH Login Failed - Undefined Error"
            ssh_device_name="SSH Hostname Not Found"
        fi

    else
        ssh_login="Port 22 is Down"
        ssh_device_name="SSH Hostname Not Found"
    fi 
}

collect_status_xml () {
    if [ "$admin_port" != "Down" ]; then

        if [ "$admin_port" == "443" ]; then
            status_data=$(curl -k -u $2:$3 --connect-timeout 5 https://$1/status.xml 2>&1)

        elif [ "$admin_port" == "80" ]; then
            status_data=$(curl -k -u $2:$3 --connect-timeout 5 http://$1/status.xml 2>&1)
        fi

        status_xml_error=$(echo "$status_data" | grep -i "<title>[0-9]\{3\}" | awk -F '[><]' '{print $3}')
        status_curl_error=$(echo "$status_data" | grep "curl: ([0-9]\{1,2\})")
        status_curl_return=$(echo "$status_curl_error" | awk -F '[()]' '{print $2}')
        status_curl_error_msg=$(echo "$status_curl_error" | awk -F '[:()]' '{print $4}' | awk '{$1=$1};1')
        status_data_wc=$(echo "$status_data" | wc -l)

        if [ -n "$status_xml_error" ]; then
            status_xml="$status_xml_error"
            ui_device_name="UI Hostname Not Found"
            serial_number="Serial Number Not Found"
            product_id="Product ID Not Found"

        elif [ -n "$status_curl_error" ] && [ "$status_curl_return" -gt 0 ]; then
            status_xml="$status_curl_error_msg"
            ui_device_name="UI Hostname Not Found"
            serial_number="Serial Number Not Found"
            product_id="Product ID Not Found"
        

        elif [ "$status_data_wc" -lt 250 ]; then
            status_xml="Status XML Failed - Lines Collected: "$status_data_wc""
            ui_device_name="UI Hostname Not Found"
            serial_number="Serial Number Not Found"
            product_id="Product ID Not Found"
        
        else
            subset_start=$(echo "$status_data" | grep -n "<SystemUnit>" | cut -d':' -f1)
            subset_end=$(echo "$status_data" | grep -n "<\/UserInterface>" | cut -d':' -f1)
            xml_subset=$(echo "$status_data" | sed -n $subset_start,$subset_end'p')
        
            systemunit_start=$(echo "$xml_subset" | grep -n "<SystemUnit>" | cut -d':' -f1)
            systemunit_end=$(echo "$xml_subset" | grep -n "<\/SystemUnit>" | cut -d':' -f1)
            systemunit_subset=$(echo "$xml_subset" | sed -n $systemunit_start,$systemunit_end'p')
        
            userinterface_start=$(echo "$xml_subset" | grep -n "<UserInterface>" | cut -d':' -f1)
            userinterface_end=$(echo "$xml_subset" | grep -n "<\/UserInterface>" | cut -d':' -f1)
            userinterface_subset=$(echo "$xml_subset" | sed -n $userinterface_start,$userinterface_end'p')

            status_xml="Status Data Collected"
            ui_device_name=$(echo "$userinterface_subset" | grep "<Name>" | awk -F '[><]' '{print $3}')
            serial_number=$(echo "$systemunit_subset" | grep "<SerialNumber>" | awk -F '[><]' '{print $3}')
            product_id=$(echo "$systemunit_subset" | grep "<ProductId>" | awk -F '[><]' '{print $3}')

            if [ -z "$ui_device_name" ]; then
                ui_device_name="UI Hostname Not Found"
            fi

            if [ -z "$serial_number" ]; then
                serial_number="Serial Number Not Found"
            fi

            if [ -z "$product_id" ]; then
                product_id="Product ID Not Found"
            fi
        fi
    else
        status_xml="Admin Ports are Down"
        ui_device_name="UI Hostname Not Found"
        serial_number="Serial Number Not Found"
        product_id="Product ID Not Found"
    fi
}

if [ ! -f "$input" ]; then
    printf "\n$input file not found\n"
    help
    exit 9
fi

while getopts ":h" option; do
    case $option in
        h) # Display Help
            help
            exit;;
        ?) # Invalid Option
            printf "\nError - Invalid Option: $1\n"
			help
            exit;;
    esac
done

printf "\nScript ran on $(date)\n\n" >> $output
printf "\nHost IP,UI Hostname,SSH Hostname,Serial Number,Product ID,Status Data,SSH Login,Ping Result,Admin Port,Port Status" >> $output

{
    read
    while IFS=, read -r host user pass; do 
        
        count=$(( $count + 1 ))
        printf "\nProcessing Device: $count of $total_devices - $host\n"

        icmp_check "$host"
        port_check "$host"
        expect_ssh_login "$host" "$user" "$pass"
        collect_status_xml "$host" "$user" "$pass"

        printf "\n$host,$ui_device_name,$ssh_device_name,$serial_number,$product_id,$status_xml,$ssh_login,$ping_result,$admin_port,$port_status" >> $output
    done
} < $input

printf "\n\nEOF\n\n" >> $output
IFS=$OLDIFS
exit
