#!/bin/bash
set -e

if [[ -z $CIRCLECI ]]; then
  echo "Please run this script on Circle CI."
  exit 1
fi

source settings/config.sh

export PATH="./vendor/drush/drush:./vendor/pantheon-systems/terminus/bin:./vendor/bin:$PATH"

git config --global user.email "dev-team+pantheon@thinkshout.com"
git config --global user.name "ThinkShout Automation"

# Pull the host name out of the full git repo, between @ and :
git_host=$(echo $GITREPO | sed -n "s/^.*@\(.*\):.*$/\1/p")
ssh-keyscan -H -p 2222 "$git_host" >> ~/.ssh/known_hosts

terminus auth:login --machine-token=$PANTHEON_TOKEN

export BRANCH=$CIRCLE_BRANCH
echo "Using branch $BRANCH"
if [ "$BRANCH" == "main" ]; then
  BRANCH="master"
else
  BRANCH=$(terminus branch:list --field=ID -- $PROJECT | { grep "^$BRANCH\$" || test $? = 1; })
fi

if [[ -z "$BRANCH" ]]; then
  echo "Pantheon branch $BRANCH not found. Skipping deploy."
  exit 0
fi

. ./scripts/deploy.sh -b "$BRANCH" -m "Circle CI automated deployment. Build #$CIRCLE_BUILD_NUM" -y

echo "Copying build artifacts"
if [ -e $TEMP_BUILD/diff.patch ]; then
  cp $TEMP_BUILD/diff.patch ~/artifacts
fi
