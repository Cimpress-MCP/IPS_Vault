#!/bin/bash

cat > /usr/bin/bastion/sync_s3 << 'EOF'
# Copy log files to S3 with server-side encryption enabled.
# Then, if successful, delete log files that are older than a day.
LOG_DIR="/var/log/bastion/"
aws s3 cp $LOG_DIR s3://{BUCKET_NAME}/logs/ --sse --region region --recursive && find $LOG_DIR* -mtime +1 -exec rm {} \;

EOF

chmod 700 /usr/bin/bastion/sync_s3
