#!/bin/bash

# Copied from http://willwarren.com/2014/07/03/roll-dynamic-dns-service-using-amazon-route53/

# Externalizing the zone ID and CNAME
if [ -z "$1" ]
  then
    echo "The first argument needs to be the Hosted Zone ID, i.e. BJBK35SKMM9OE"
    exit 1
fi

if [ -z "$2" ]
  then
    echo "The second argument needs to be CNAME to update, i.e. example.com"
    exit 1
fi

if [ -z "$3" ]
  then
    echo "The third argument needs to be AWS IAM role that has access to this domain, i.e. your-dns-updater"
    exit 1
fi


# Hosted Zone ID e.g. BJBK35SKMM9OE
ZONEID=$1

# The CNAME you want to update e.g. hello.example.com
RECORDSET=$2

# The IAM user profile to use
IAM_PROFILE=$3

# Force the update
if [ $4 = "1" ];
  then
  echo "Force update is set."
    FORCE_UPDATE=1
fi

# More advanced options below
# The Time-To-Live of this recordset
TTL=300
# Change this if you want
COMMENT="Auto updating @ `date`"
# Change to AAAA if using an IPv6 address
TYPE="A"

# Get the external IP address
IP=`curl -sSk https://wtfismyip.com/text`

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

# Get current dir (stolen from http://stackoverflow.com/a/246128/920350)
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
    # code if found
    echo "IP is still $IP. Exiting" >> "$LOGFILE"
    if [ -z "$FORCE_UPDATE" ]; then
      echo "Exiting..."
      exit 0
    fi
fi

echo "IP has changed to $IP, updating ..."
echo "IP has changed to $IP" >> "$LOGFILE"
# Fill a temp file with valid JSON
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

# Update the Hosted Zone record
aws route53 change-resource-record-sets \
    --profile $IAM_PROFILE \
    --hosted-zone-id $ZONEID \
    --change-batch file://"$TMPFILE" >> "$LOGFILE"
echo "" >> "$LOGFILE"

# Clean up
rm $TMPFILE

# All Done - cache the IP address for next time
echo "$IP" > "$IPFILE"
