#!/bin/bash
input=appliances.csv
OLDIFS=$IFS
IFS=","
mkdir -p audit
touch audit/vos_audit
output=audit/vos_audit
count=0
total_devices=$(cat "$input" | wc -l)
total_devices=$(( $total_devices - 1 ))

help() {
   printf "\nAudit Script for Cisco VOS Appliances"
   printf "\nThis script requires an 'appliances.csv' file containing IPs and credentials to run."
   printf "\nSee the example 'appliances.csv' template or enrollment template for CSV file format."
   printf "\n\nSyntax: ./VOS-Audit.sh Optional[-h]"
   printf "\n\nOptions:"
   printf "\nh     Print this help dialog\n\n"
}

audit_appliances () { 

    expect_output=$(
        # if you need debug,use the -d like this - /usr/bin/expect -d << EOF
        /usr/bin/expect << EOF
        spawn ssh -o ConnectTimeout=10 "$username@$host"
        set timeout 30
        expect {
            "Connection timed out" {exit}
            "RSA key fingerprint" {send "yes\r"; exp_continue}
            "ECDSA key fingerprint" {send "yes\r"; exp_continue}
            "Host key verification failed." {exit}
            "UNIX password: " {send "\x03"; exit}
            "Permission denied" {send "\x03"; exit}
            -re "\[P|p]assword: " {send "$password\r"; exp_continue}
            "admin:" {send "\r"}
        }
        expect "admin:"
        send "show status\r"
        expect "admin:"
        send "show account\r"
        expect "admin:"
        send "show network cluster\r"
        expect "admin:"
        send "show cuc cluster status\r"
        expect "admin:"
        send "utils service list\r"
        expect "admin:"
        send "show version active\r"
        expect "admin:"
        send "exit\r"
        expect eof
EOF
    )
}

if [ ! -f "$input" ]; then
    echo "$input file not found"
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

printf "\nScript ran on $(date)" >> $output
printf "\nvos-audit.sh script executed..."

{
    read
    while IFS=, read -r host username password priv1username priv1password; do

        count=$(( $count + 1 ))
        printf "\n\nProcessing Device: $count of $total_devices - $host"

        audit_appliances
        echo -e "\n\n$expect_output" >> $output

    done
} < $input

printf "\n\nvos-audit.sh script complete.\n\n"
echo -e "\n\nEOF\n\n" >> $output
IFS=$OLDIFS
exit