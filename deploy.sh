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
SKIP=$1
source settings/config.sh


usage()
{
cat << EOF
usage: $0 options

deploy.sh <# of commits made directly on host since last push>
Copy ./scripts/default.config.sh to ./config.sh and add your project configuration.

OPTIONS:
  -h      Show this message
  -b      Branch to checkout (optional, current branch name will be used otherwise)
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
  git diff --name-status $TEMP_BUILD/drupal/profiles/$PROJECT/libraries >> $TEMP_BUILD/librariesdiff #--diff-filter=ACMRTUXB
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
while getopts “h:b:y” OPTION
do
  case $OPTION in
    h)
      usage
      exit 1
      ;;
    b)
      BRANCH=$OPTARG
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


# If branch isn't explicit, default to current branch.
if [[ -z $BRANCH ]]; then
  BRANCH=$(git symbolic-ref --short -q HEAD)
fi

echo "Checkout $BRANCH branch from $HOSTTYPE..."
git clone --depth=1 --branch $BRANCH $GITREPO $TEMP_BUILD/$HOSTTYPE

echo "$HOSTTYPE Clone complete, calling build.sh -y $TEMP_BUILD/drupal..."
echo "DEPLOY FROM $BRANCH"
scripts/build.sh -y $TEMP_BUILD/drupal

# Remove the scripts, vendor, & settings folders for security purposes:
rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/scripts
echo "rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/scripts"
rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/settings
echo "rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/settings"
rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/vendor
echo "rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/vendor"

# Remove files used by these scripts:
rm -f $TEMP_BUILD/drupal/sites/default/config.sh
echo "rm -f $TEMP_BUILD/drupal/sites/default/config.sh"
rm -f $TEMP_BUILD/drupal/sites/default/settings_additions.php
echo "rm -f $TEMP_BUILD/drupal/sites/default/settings_additions.php"
rm -f $TEMP_BUILD/drupal/profiles/$PROJECT/composer.json
echo "rm -f $TEMP_BUILD/drupal/profiles/$PROJECT/composer.json"
rm -f $TEMP_BUILD/drupal/profiles/$PROJECT/composer.lock
echo "rm -f $TEMP_BUILD/drupal/profiles/$PROJECT/composer.lock"

# Make sure no local settings are committed to pantheon
rm -f $TEMP_BUILD/drupal/sites/default/local.settings.php
echo "rm -f $TEMP_BUILD/drupal/sites/default/local.settings.php"

# Remove .git and .gitignore files
rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/.git
echo "rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/.git"
rm -rf $TEMP_BUILD/drupal/.git
echo "rm -rf $TEMP_BUILD/drupal/.git"
find $TEMP_BUILD/drupal | grep '\.git' | xargs rm -rf
echo "find $TEMP_BUILD/drupal | grep '\.git' | xargs rm -rf"

# Move the remote .git & .gitignore into the drupal root
mv $TEMP_BUILD/$HOSTTYPE/.git $TEMP_BUILD/drupal/.git
echo "mv $TEMP_BUILD/$HOSTTYPE/.git $TEMP_BUILD/drupal/.git"
if [ -f $TEMP_BUILD/$HOSTTYPE/.gitignore ]; then
  mv $TEMP_BUILD/$HOSTTYPE/.gitignore $TEMP_BUILD/drupal/.gitignore
  echo "mv $TEMP_BUILD/$HOSTTYPE/.gitignore $TEMP_BUILD/drupal/.gitignore"
fi
# Now let's build our commit message.
# git plumbing functions don't attend properly to --exec-path
# so we end up jumping around the directory structure to make git calls
# First, get the last hosting repo commit date so we know where to start
# our amalgamated commit comments from:
cd $TEMP_BUILD/drupal
COMMIT=`git rev-list HEAD --timestamp --max-count=1 --skip=$SKIP`
cd $ORIGIN
FILTER=" *"
COMMITDATEUNIX=${COMMIT%%$FILTER}
COMMITDATE=`date -r $COMMITDATEUNIX '+%m/%d/%Y %H:%M:%S'`

# Git log for commit message
cd $ORIGIN
URLINFO=`cat .git/config | grep url`
BUILDREPO=${URLINFO##*@}

# Now we start building the commit message
echo "Commit generated by ThinkShout's deploy.sh script." > $TEMP_BUILD/commitmessage
echo "Amalgamating the following commits from $BUILDREPO:" >> $TEMP_BUILD/commitmessage

echo "Amalgamating commit comments since: $COMMITDATE"
git log --pretty=format:"%h %s" --since="$COMMITDATE" >> $TEMP_BUILD/commitmessage

if [[ -z $EDITOR ]]; then
  echo "Running vi to customize commit message: close editor to continue script."
  vi $TEMP_BUILD/commitmessage
else
  echo "Running $EDITOR to customize commit message: close editor to continue script."
  $EDITOR $TEMP_BUILD/commitmessage
fi

cd $TEMP_BUILD/drupal

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
  echo "> cd $TEMP_BUILD/drupal"
  echo "> git push"
fi
echo "Build script complete. Clean up temp files with:"
echo "rm -rf $TEMP_BUILD"
cd $ORIGIN
