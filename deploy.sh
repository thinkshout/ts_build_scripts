#!/bin/bash
set -e

#
# Calls build.sh and git clone on the specified hosting repository;
# uses git to gather changes from host repository in the current build;
# adds changes to host's git repository
#
# Usage: scripts/deploy.sh -b <branch>
#

ORIGIN=$(pwd)
source settings/config.sh

usage()
{
cat << EOF
usage: $0 options

deploy.sh <options>
Copy ./settings/default.config.sh to ./settings/config.sh and add your project configuration.

OPTIONS:
  -h      Show this message
  -d      Source directory for the build.
  -b      Branch to checkout (optional, current branch name will be used otherwise)
  -n      Number of commits made directly on host since last push
  -y      Skip confirmation prompts

EOF
}

confirmpush () {
  echo "Git add & commit completed. Ready to push to $BRANCH branch of $GITREPO."
  if $ASK; then
    read -r -p "Push? [y/n] " response
    case $response in
      [yY][eE][sS]|[yY])
        true
        ;;
      *)
        false
        ;;
    esac
  else
    true
  fi
}

confirmcommitmsg () {
  echo $'\n'
  echo "Review commit message."
  echo $'\n'
  cat $TEMP_BUILD/commitmessage
  echo $'\n'
  if $ASK; then
    read -r -p "Commit message is correct? [y/n] " response
    case $response in
      [yY][eE][sS]|[yY])
        true
        ;;
      *)
        false
        ;;
    esac
  else
    true
  fi
}

librariescheck () {
  git diff --name-status $BUILD_DIR/profiles/$PROJECT/libraries >> $TEMP_BUILD/librariesdiff #--diff-filter=ACMRTUXB
  WORDCOUNT=`cat $TEMP_BUILD/librariesdiff | wc -l`
  if [ $WORDCOUNT -gt 0 ]; then
    echo $'\n'
    echo 'Library files changed:'
    echo $'\n'
    cat $TEMP_BUILD/librariesdiff
    echo $'\n'
    if $ASK; then
      read -r -p "Are you sure you want to update libraries? [y/n] " response
      case $response in
        [yY][eE][sS]|[yY])
          true
          ;;
        *)
          false
          ;;
      esac
    else
      true
    fi
fi
}

BRANCH=
ASK=true
while getopts “h:b:d:n:y” OPTION
do
  case $OPTION in
    h)
      usage
      exit 1
      ;;
    b)
      BRANCH=$OPTARG
      ;;
    n)
      SKIP=$OPTARG
      ;;
    d)
      BUILD_DIR=$OPTARG
      ;;
    y)
      ASK=false
      ;;
    ?)
       usage
       exit 1
       ;;
     esac
done

if [[ -z $GITREPO ]]; then
  echo 'Set $GITREPO in scripts/config.sh'
  exit 1
fi

if [ "x$SKIP" == "x" ]; then
  SKIP=0
fi

if [ ! -f drupal-org.make ]; then
  echo "[error] Run this script from the distribution base path."
  exit 1
fi

case $OSTYPE in
  darwin*)
    TEMP_BUILD=`mktemp -d -t tmpbuild`
    ;;
  *)
    TEMP_BUILD=`mktemp -d`
    ;;
esac

# Identify the automation user
if [ -n "$CI" ]
then
  git config --global user.email "ci@thinkshout.com"
  git config --global user.name "ThinkShout CI Bot"
fi

HOST_DIR="$TEMP_BUILD/$HOSTTYPE"

# If branch isn't explicit, default to current branch.
if [[ -z $BRANCH ]]; then
  BRANCH=$(git symbolic-ref --short -q HEAD)
fi

echo "Checkout $BRANCH branch from $HOSTTYPE..."
git clone --depth=1 --branch $BRANCH $GITREPO $HOST_DIR

if [[ -z $BUILD_DIR ]]; then
  BUILD_DIR="$TEMP_BUILD/drupal"
  echo "Running build.sh -y $BUILD_DIR..."
  scripts/build.sh -y $BUILD_DIR
fi

# Remove the scripts, vendor, & settings folders for security purposes:
rm -rf $BUILD_DIR/profiles/$PROJECT/scripts
echo "rm -rf $BUILD_DIR/profiles/$PROJECT/scripts"
rm -rf $BUILD_DIR/profiles/$PROJECT/settings
echo "rm -rf $BUILD_DIR/profiles/$PROJECT/settings"
rm -rf $BUILD_DIR/profiles/$PROJECT/vendor
echo "rm -rf $BUILD_DIR/profiles/$PROJECT/vendor"

# Remove files used by these scripts:
rm -f $BUILD_DIR/sites/default/config.sh
echo "rm -f $BUILD_DIR/sites/default/config.sh"
rm -f $BUILD_DIR/sites/default/settings_additions.php
echo "rm -f $BUILD_DIR/sites/default/settings_additions.php"
rm -f $BUILD_DIR/profiles/$PROJECT/composer.json
echo "rm -f $BUILD_DIR/profiles/$PROJECT/composer.json"
rm -f $BUILD_DIR/profiles/$PROJECT/composer.lock
echo "rm -f $BUILD_DIR/profiles/$PROJECT/composer.lock"

# Make sure no local settings are committed to pantheon
rm -f $BUILD_DIR/sites/default/local.settings.php
echo "rm -f $BUILD_DIR/sites/default/local.settings.php"

# Remove .git and .gitignore files
rm -rf $BUILD_DIR/profiles/$PROJECT/.git
echo "rm -rf $BUILD_DIR/profiles/$PROJECT/.git"
rm -rf $BUILD_DIR/.git
echo "rm -rf $BUILD_DIR/.git"
find $BUILD_DIR | grep '\.git' | xargs rm -rf
echo "find $BUILD_DIR | grep '\.git' | xargs rm -rf"

# Move the remote .git & .gitignore into the drupal root
mv $HOST_DIR/.git $BUILD_DIR/.git
echo "mv $HOST_DIR/.git $BUILD_DIR/.git"
if [ -f $HOST_DIR/.gitignore ]; then
  mv $HOST_DIR/.gitignore $BUILD_DIR/.gitignore
  echo "mv $HOST_DIR/.gitignore $BUILD_DIR/.gitignore"
fi
# Now let's build our commit message.
# git plumbing functions don't attend properly to --exec-path
# so we end up jumping around the directory structure to make git calls
# First, get the last hosting repo commit date so we know where to start
# our amalgamated commit comments from:
cd $BUILD_DIR
COMMITDATE=`git log -n 1 --skip=$SKIP $BRANCH --format=format:%ci`
cd $ORIGIN

# Git log for commit message
cd $ORIGIN
URLINFO=`cat .git/config | grep url`
BUILDREPO=${URLINFO##*@}

# Now we start building the commit message
echo "Commit generated by ThinkShout's deploy.sh script." > $TEMP_BUILD/commitmessage
echo "Amalgamating the following commits from $BUILDREPO:" >> $TEMP_BUILD/commitmessage

echo "Amalgamating commit comments since: $COMMITDATE"
git log --pretty=format:"%h %s" --no-merges --since="$COMMITDATE" >> $TEMP_BUILD/commitmessage

# Only prompt to edit the commit message if we're asking for input.
if $ASK; then
  if [[ -z $EDITOR ]]; then
    echo "Running vi to customize commit message: close editor to continue script."
    vi $TEMP_BUILD/commitmessage
  else
    echo "Running $EDITOR to customize commit message: close editor to continue script."
    $EDITOR $TEMP_BUILD/commitmessage
  fi
fi

cd $BUILD_DIR

if confirmcommitmsg; then
  echo "Commit message approved."
else
  echo "Commit message not approved."
  exit 1
fi

if librariescheck; then
  echo $'\n'
else
  echo "Libraries updates not approved."
  exit 1
fi

echo "Writing git ls-files -mo to $TEMP_BUILD/changes"
# Checkout files that we don't want removed from the host, like settings.php.
# This function should be defined in the host include script.
protectfiles;

git ls-files -d --exclude-standard > $TEMP_BUILD/deletes
echo "Adding file deletions to GIT"
while read LINE
  do
    echo "Deleted: $LINE";
    git rm "$LINE";
done < $TEMP_BUILD/deletes

git ls-files -mo --exclude-standard > $TEMP_BUILD/changes
echo "Adding new and changed files to GIT"
while read LINE
  do
    echo "Adding $LINE";
    git add "$LINE";
done < $TEMP_BUILD/changes
git status
echo "Committing changes"
git commit --file=$TEMP_BUILD/commitmessage >> /dev/null
git log --max-count=1
echo $'\n'
if confirmpush; then
  git push
else
  echo "Changes have not been pushed to Git Repository at $GITREPO."
  echo "To push changes:"
  echo "> cd $BUILD_DIR"
  echo "> git push"
fi
echo "Build script complete. Clean up temp files with:"
echo "rm -rf $TEMP_BUILD"
cd $ORIGIN
