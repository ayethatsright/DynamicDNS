#!/bin/bash

# Hosted Zone ID e.g. BJBK35SKMM9OE
ZONEID="XXXXXXXXXXXXX"

# The CNAME you want to update e.g. hello.example.com
RECORDSET="xxx.xxxxxxxxxx.com"

# The Time-To-Live of this recordset
TTL=300
# Comment to include date of the change
COMMENT="Auto updating @ `date`"
# Record Type (Change to AAAA if using IPv6)
TYPE="A"

# Get the external IP address from icanhazip.com (you can use any service you want)
IP=`curl icanhazip.com`

function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# Get current dir
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOGFILE="$DIR/update-route53.log"
IPFILE="$DIR/update-route53.ip"

if ! valid_ip $IP; then
    echo "Invalid IP address: $IP" >> "$LOGFILE"
    exit 1
fi

# Check if the IP has changed
if [ ! -f "$IPFILE" ]
    then
    touch "$IPFILE"
fi

if grep -Fxq "$IP" "$IPFILE"; then
    # if found
    echo "IP is still $IP. Exiting" >> "$LOGFILE"
    exit 0
else
    echo "IP has changed to $IP" >> "$LOGFILE"
    # Fill a temp file with the valid JSON
    TMPFILE=$(mktemp /tmp/temporary-file.XXXXXXXX)
    cat > ${TMPFILE} << EOF
    {
      "Comment":"$COMMENT",
      "Changes":[
        {
          "Action":"UPSERT",
          "ResourceRecordSet":{
            "ResourceRecords":[
              {
                "Value":"$IP"
              }
            ],
            "Name":"$RECORDSET",
            "Type":"$TYPE",
            "TTL":$TTL
          }
        }
      ]
    }
EOF

    # Update the Hosted Zone record via AWS CLI
    aws route53 change-resource-record-sets \
        --hosted-zone-id $ZONEID \
        --change-batch file://"$TMPFILE" >> "$LOGFILE"
    echo "" >> "$LOGFILE"

    # Get rid of the tmp file
    rm $TMPFILE
fi

# Finished updating the IP address - caching the IP address for next time
echo "$IP" > "$IPFILE"
