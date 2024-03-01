#!/bin/bash

# Extract the archive
tar -xf file/archive.tar

# Remove empty files
find . -type f -empty -delete

# Append .log extension to remaining files
find . -type f -exec mv {} {}.log \;

# Create new archive
tar -cf /new/archive.tar .


#!/bin/bash

# SSH connection setup
ssh -i ~/.ssh/custom_keys/private_key -c aes256-cbc -X -C alex@example.com
 