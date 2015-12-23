#!/bin/bash

openssl aes-256-cbc -K $encrypted_82af4a1b80fd_key -iv $encrypted_82af4a1b80fd_iv -in .travis/deploy_key.enc -out .travis/deploy_key -d
echo $DEPLOY_KNOWNHOST >> ~/.ssh/known_hosts
eval `ssh-agent`
chmod 600 .travis/deploy_key
ssh-add .travis/deploy_key
make deploy DEPLOY_DIR=$DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_DIRECTORY
