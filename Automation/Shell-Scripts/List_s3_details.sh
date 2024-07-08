#!/bin/bash

##Below script list all s3 bucket details with details. 
##This helps us to manage s3 bucket inventory and cleanup unused buckets regularly and be compliant
##It stores all the details to json which can be converetd again to csv.

output_file="s3_list.json"
buckets_info=()

buckets=$(aws s3 ls | awk '{print $3}')

for bucket in $buckets; do
    echo "Started reading bucket details: $bucket"

    #Find the created date of bucket
    creation_date=$(aws s3 ls | grep -w $bucket | awk '{print $1}')

    #Below line consumes more time for execution
    #creation_date=$(aws s3api list-buckets --query "Buckets[?Name=='$bucket'].CreationDate" --output text)

    #Check if bucket is empty
    is_empty=$(aws s3 ls s3://$bucket --recursive | wc -l)
    empty="false"
    if [ "$is_empty" -eq 0 ]; then
        empty="true"
    fi

    #Check if tags are present
    tags_present="false"
    if_cfn=""
    tags=$(aws s3api get-bucket-tagging --bucket $bucket --output json 2>/dev/null)
    if [ $? -eq 0 ]; then
        tags_present="true"

        #check for a specific tag present
        if_cfn=$(echo -e $tags | jq -r '.TagSet[] | select(.Key == "Keyname") | .Value')
    fi

    #Check if last used date of the bucket objects
    last_used_date=""
    if [ "$empty" == "false" ]; then
        last_used_date=$(aws s3api list-objects --bucket $bucket --query 'Contents[].[LastModified]' --output text | sort -r | head -n 1)
    fi

    #Check if bucket is encrypted
    encryption="false"
    encryptiontype=""
    kmskey=""
    
    encryption_output=$(aws s3api get-bucket-encryption --bucket $bucket --output json 2>/dev/null)
    if [ $? -eq 0 ]; then
        encryption="true"

        encryptiontype=$(echo -e $encryption_output | jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm')

        kmskey=$(echo -e $encryption_output |jq -r '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID')
    fi

    #CHeck if the bucket policy present
    policy_present="false"
    HTTPS_PolicyPresent="false"

    PolicyInfo=$(aws s3api get-bucket-policy --bucket $bucket --query Policy --output text 2>/dev/null)
    if [ $? -eq 0 ]; then
        policy="true"

        if echo $PolicyInfo | grep -q "aws:SecureTransport\":\"false\""; then
            HTTPS_PolicyPresent="true"
        fi
    fi

    echo "Collected all details of bucket: $bucket"
    bucket_info=$(jq -n \
    --arg bucketname "$bucket" \
    --arg creation_date "$creation_date" \
    --arg empty "$empty" \
    --arg tags_present "$tags_present" \
    --arg encryption "$encryption" \
    --arg encryptiontype "$encryptiontype" \
    --arg kmskey "$kmskey" \
    --arg policy_present "$policy_present" \
    --arg last_used_date "$last_used_date" \
    --arg if_cfn "$if_cfn" \
    --arg HTTPS_PolicyPresent "$HTTPS_PolicyPresent" \
    '{BucketName: $bucketname, CreatedDate: $creation_date, last_used_date: $last_used_date, encryptiontype: $encryption, kmskey: $kmskey, policy_present: $policy_present, if_cfn: $if_cfn,  HTTPS_PolicyPresent: $HTTPS_PolicyPresent}')

    echo "Json value of $bucket is : $bucket_info"
    buckets_info+=("$bucket_info")
done

jq -n --argjson buckets "$(printf '%s\n' "${buckets_info[@]}" | jq -s '.')" '$buckets' > $output_file
