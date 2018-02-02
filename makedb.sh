#!/bin/bash



############################## Settings and Configuration #################

# Old, unencrypted database name
instance_identifier="database-name-here"

# New, encrypted  database name
new_instance_identifier="new-database-name"

# Instance class to spin up for the new database
instance_class="db.m3.2xlarge"

# Security group for the new database
security_group="sg-e123456"

# Param group for the new database
param_group="super-param-group"

# Subnet for the new database
subnet_group="subnet101"

# The date
snap_id_date=`date "+%Y-%m-%d-%H"`

# KMS key to use for encrypting the snapshot made of the unencrypted DB
kms="1231245-21332-ffccca-2c33-324bbcaa23"

# Retention period for the new DB
retpd=14

# IOPS of new DB
iops=3000

#Default AWS Region
AWS_DEFAULT_REGION=us-east-1

# Make the new instance multi-AZ?
az=false

############################# Functions and other misc ######################

function create-database {
  stats="unknown"
  region=$1
  idr=$2
  snr=$3
  dbc=$4
  iops=$5
  az=$6
  
  if [ "$az" == "false" ]; then
    az="no-multi-az"
  else
    az="multi-az"
  fi
  
  og=$7
  sg=$8
  
  aws --region=$region rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier=$idr \
  --db-snapshot-identifier=$snr \
  --db-instance-class $dbc \
  --storage-type="io1" \
  --iops $iops \
  --no-publicly-accessible \
  --$az \
  --option-group-name $og \
  --no-auto-minor-version-upgrade \
  --db-subnet-group-name=$sg
}

function make-snapshot-live {
  instance=$1
  target_status=$2
  region=$3
  aws --region $region rds create-db-snapshot --db-instance-identifier $instance \
  --db-snapshot-identifier $instance-$snap_id_date
  
  status=unknown
  while [[ $status != 0 ]]; do
    status=`aws --region=$region rds describe-db-snapshots --db-snapshot-identifier $instance-$snap_id_date \
    | grep -i creating | wc -l | tee | grep -o '[0-9]\+'`
    echo "not done making the snapshot. Still waiting for completion to be 0. Currently $status"
    aws rds wait db-snapshot-completed --db-snapshot-identifier $instance-$snap_id_date
  done
}

function wait-for-status {
  instance=$1
  target_status=$2
  region=$3
  status=unknown
  while [[ "$status" != "$target_status" ]]; do
    status=`aws --region=$region rds describe-db-instances --db-instance-identifier=$instance \
    | grep DBInstanceStatus \
    | cut -d ":" -f2 \
    | grep -o '[0-9]\+'`
    sleep 60
    echo "still waiting...$instance is reported as $status..."
  done
}

function get-snapshot-id {
  ins=$1
  region=$2
  
  echo $ins is set
  echo $region is set
  
}

##############################################################################################################################

encsuffix=-enc

# Make the initial snapshot of the prod database

make-snapshot-live $instance_identifier 1 $AWS_DEFAULT_REGION

echo "Snapshot Id: $instance-$snap_id_date"

echo "trying to make $instance-$snap_id_date$encsuffix as encrypted copy"


aws rds --region=$AWS_DEFAULT_REGION copy-db-snapshot --source-db-snapshot-identifier $instance-$snap_id_date \
--target-db-snapshot-identifier $instance-$snap_id_date$encsuffix --kms-key-id $kms

status=unknown
while [[ $status != 0 ]]; do
  status=`aws --region=$AWS_DEFAULT_REGION rds describe-db-snapshots --db-snapshot-identifier $instance-$snap_id_date$encsuffix \
  | grep -i creating | wc -l | tee | grep -o '[0-9]\+'`
  echo "not done making the snapshot. Still waiting for completion to be 0. Currently $status"
  aws --region=$region rds describe-db-snapshots --db-snapshot-identifier $instance-$snap_id_date$encsuffix
  
  sleep 60
done

aws rds delete-db-snapshot --db-snapshot-identifier $instance-$snap_id_date

echo "Creating new database: $new_instance_identifier with $instance-$snap_id_date$encsuffix"

# create database region, new db name, snapshot ID, db instance type, storage type, multi-az, option group, subnet group
create-database us-east-1 $new_instance_identifier $instance-$snap_id_date$encsuffix $instance_class $iops $az default:mysql-5-6 $subnet_group

# disable backup retention, apply groups
sleep 120

statusmods="unknown"

while [[ $statusmods != 0 ]]; do
statusmods=`aws rds describe-db-instances --db-instance-id=$new_instance_identifier | grep -i -E "creating|modifying" | wc -l | tee | grep -o '[0-9]\+'`
echo "not done applying and readily available. Still waiting for modification to be 0. Currently $statusmods"
echo "DB may still allow connections at this point. Please try but leave this script running to completion."
echo "Keep in mind that you must reboot the DB in a bit to apply the param group."
sleep 60
done

aws rds --region=$AWS_DEFAULT_REGION modify-db-instance --db-instance-identifier=$new_instance_identifier \
--backup-retention-period $retpd --db-parameter-group-name $param_group \
--vpc-security-group-ids $security_group --apply-immediately

echo "Param and security groups applied. Rebooting and we're done."

sleep 60
statusmods="unknown"
while [[ $statusmods != 0 ]]; do
statusmods=`aws rds describe-db-instances --db-instance-id=$new_instance_identifier | grep -i -E "creating|modifying" | wc -l | tee | grep -o '[0-9]\+'`
aws rds describe-db-instances --db-instance-id=$new_instance_identifier
echo "not done applying and readily available. Still waiting for modification to be 0. Currently $statusmods"
echo "The param group has been applied. Waiting for it to be safe to reboot."
sleep 120
done
