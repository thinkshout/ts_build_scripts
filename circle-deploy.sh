#!/bin/bash
set -e

if [[ -z $CIRCLECI ]]; then
  echo "Please run this script on Circle CI."
  exit 1
fi

echo "Grabbing source."
source settings/config.sh

if [[ -z "$PANTHEON_SITE" ]]; then
  PANTHEON_SITE=$PROJECT
fi
echo "$PANTHEON_SITE"

export PATH="./vendor/drush/drush:./vendor/pantheon-systems/terminus/bin:./vendor/bin:$PATH"

echo "Configuring this user"
git config --global user.email "dev-team+pantheon@thinkshout.com"
git config --global user.name "ThinkShout Automation"

echo "Grabbing host and adding ssh key."
# Pull the host name out of the full git repo, between @ and :
git_host=$(echo $GITREPO | sed -n "s/^.*@\(.*\):.*$/\1/p")
ssh-keyscan -H -p 2222 "$git_host" >> ~/.ssh/known_hosts

echo "Authorizing Terminus."
terminus auth:login --machine-token=$PANTHEON_TOKEN

echo "Getting branch name"
branch_name=$(terminus branch:list --field=ID -- $PANTHEON_SITE | { grep "^$CIRCLE_BRANCH\$" || test $? = 1; })
if [[ -z "$branch_name" ]]; then
  echo "Pantheon branch $CIRCLE_BRANCH not found. Skipping deploy."
  exit 0
fi

echo "Deploying to Pantheon."
. ./scripts/deploy.sh -b "$CIRCLE_BRANCH" -m "Circle CI automated deployment. Build #$CIRCLE_BUILD_NUM" -y

echo "Copying build artifacts"
if [ -e $TEMP_BUILD/diff.patch ]; then
  cp $TEMP_BUILD/diff.patch ~/artifacts
fi
