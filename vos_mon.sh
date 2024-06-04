#!/bin/bash
input=appliances.csv
OLDIFS=$IFS
IFS=","
mkdir -p audit
touch audit/vos_mon_out
output=audit/vos_mon_out
count=0
total_devices=$(cat "$input" | wc -l)
total_devices=$(( $total_devices - 1 ))

help() {
   printf "\nScript for Creating the vos_mon account on Cisco VOS Appliances"
   printf "\nThis script requires an 'appliances.csv' file containing IPs and credentials to run."
   printf "\nSee the example 'appliances.csv' template or enrollment template for CSV file format."
   printf "\n\nSyntax: ./vos_mon.sh Optional[-h]"
   printf "\n\nOptions:"
   printf "\nh     Print this help dialog"
}

create_priv1_account () { 

    expect_output=$(
        # /usr/bin/expect -d << EOF # To Debug
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
        send "set account name $priv1username\r"
        expect {
            "level :" {send "1\r"; exp_continue}
            "Account name already exists" {send "exit\r"; exit}
            "Incomplete command entered" {send "exit\r"; exit}
            "account creation failed\r\nadmin:" {send "exit\r"; exit}
            "No) :" {send "yes\r"; exp_continue}
            "$priv1username]" {send "\r"; exp_continue}
            "password :" {send "$priv1password\r"; exp_continue}
            "confirm :" {send "$priv1password\r"; exp_continue}
            "admin:" {send "\r"}
        }
        expect "admin:"
        send "set password change-at-login disable $priv1username\r"
        expect "admin:"
        send "exit\r"
        expect eof
EOF
    )
}

test_priv1_account () { 

    expect_output=$(
        # /usr/bin/expect -d << EOF # To Debug
        /usr/bin/expect << EOF
        spawn ssh -o ConnectTimeout=10 "$priv1username@$host"
        set timeout 30
        expect {
            "Connection timed out" {exit}
            "RSA key fingerprint" {send "yes\r"; exp_continue}
            "ECDSA key fingerprint" {send "yes\r"; exp_continue}
            "Host key verification failed." {exit}
            "UNIX password: " {send "\x03"; exit}
            "Permission denied" {send "\x03"; exit}
            -re "\[P|p]assword: " {send "$priv1password\r"; exp_continue}
            "admin:" {send "\r"}
        }
        expect "admin:" 
        send "show myself\r"
        expect "admin:"
        send "exit\r"
        expect eof
EOF
    )
}

parse_expect_output () {
    test_account=0

    printf "\n$expect_output\n" >> $output

    priv1_login=$(echo "$expect_output" | grep "$priv1username@$host")
    priv4_login=$(echo "$expect_output" | grep "$username@$host")

    conn_error=$(echo "$expect_output" | grep "ssh: connect to host" | awk -F '[:]' '{print $3}' | awk '{$1=$1};1' | tr -d '\r')
    hostkey_error=$(echo "$expect_output" | grep "Host key verification failed" | tr -d '\r')
    pwreset_error=$(echo "$expect_output" | grep "UNIX password:" | tr -d '\r')
    login_permdenied_error=$(echo "$expect_output" | grep "Permission denied" | awk -F '[,]' '{print $1}' | tr -d '\r')

    acctexists_error=$(echo "$expect_output" | grep "Account name already exists" | tr -d '\r')
    insuffpriv_error=$(echo "$expect_output" | grep "Incomplete command entered" | tr -d '\r')
    badpw_error=$(echo "$expect_output" | grep "BAD PASSWORD" | awk -F '[:-]' '{print $1 $3}' | tr -d '\r')
    created_success=$(echo "$expect_output" | grep "Account successfully created"| awk -F '[.]' '{print $1}'  | tr -d '\r')

    tested_success=$(echo "$expect_output" | grep "Machine Name" | tr -d '\r')

    if [ -n "$conn_error" ]; then
        login_status="$host\tERROR\t$conn_error"

    elif [ -n "$hostkey_error" ]; then
        sshkeygen=$(echo "$expect_output" | grep "ssh-keygen -R")
        login_status="$host\tERROR\t$hostkey_error\n\t\t\t\tFix with: $sshkeygen"

    elif [ -n "$login_permdenied_error" ]; then

        if [ -n "$priv1_login" ]; then
            login_status="$host\tERROR\t$priv1username $login_permdenied_error"

        elif [ -n "$priv4_login" ]; then
            login_status="$host\tERROR\t$username $login_permdenied_error"
        fi

    elif [ -n "$insuffpriv_error" ]; then
        login_status="$host\tERROR\t$username does not have permission to create the account"

    elif [ -n "$badpw_error" ]; then
        login_status="$host\tERROR\t$priv1username - $badpw_error"

    elif [ -n "$acctexists_error" ]; then
            login_status="$host\tINFO\t$priv1username $acctexists_error"
            test_account=1

    elif [ -n "$tested_success" ]; then
        login_status="$host\tSUCCESS\t$priv1username Account successfully tested"

    elif [ -n "$pwreset_error" ]; then

        if [ -n "$priv1_login" ]; then
            login_status="$host\tERROR\t$priv1username password change required"

        elif [ -n "$priv4_login" ]; then
            login_status="$host\tERROR\t$username password change required"
        fi

    elif [ -n "$created_success" ]; then
        login_status="$host\tSUCCESS\t$priv1username $created_success"
        test_account=1

    else
        login_status="$host\tERROR\tUnspecified Error: Check Output"
    fi
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

printf "\nScript ran on $(date)\n\n" >> $output
printf "\nvos_mon.sh script executed..."

{
    read
    while IFS=, read -r host username password priv1username priv1password; do

        count=$(( $count + 1 ))
        pw_length=$(printf "$priv1password" | wc -c)

        if [ "$pw_length" -lt 6 ]; then
            login_status="$host\tERROR\tPriv1 password does not meet length requirement"
            test_account=0
        else
            create_priv1_account
            parse_expect_output
        fi

        printf "\n\n$count of $total_devices:\t$login_status"

        if [ "$test_account" -eq 1 ]; then
            test_priv1_account
            parse_expect_output
            printf "\n\t\t$login_status"
        fi
    done
} < $input

printf "\n\nvos_mon.sh script complete.\n\n"
echo -e "\n\nEOF\n\n" >> $output
IFS=$OLDIFS
exit