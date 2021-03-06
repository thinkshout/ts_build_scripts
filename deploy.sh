#!/bin/bash
set -e

#
# Calls build.sh and git clone on the specified hosting repository;
# uses git to gather changes from host repository in the current build;
# adds changes to host's git repository
#
# Usage: ./scripts/deploy.sh from the profile main directory.
#

ORIGIN=$(pwd)
SKIP=$1
source settings/config.sh

usage()
{
cat << EOF
usage: $0 options

./scripts/deploy.sh # of commits from made directly on host since last push
./scripts/deploy.sh -b <branch>

OPTIONS:
  -h      Show this message
  -b      Branch to checkout (optional)
  -m      Commit message (optional)
  -y      Skip confirmation

EOF
}

confirmpush () {
  echo "Git add & commit completed. Ready to push to Repo at $GITREPO."
  read -r -p "Push? [y/n] " response
  case $response in
    [yY][eE][sS]|[yY])
      true
      ;;
    *)
      false
      ;;
  esac
}

confirmcommitmsg () {
  echo $'\n'
  echo "Review commit message."
  echo $'\n'
  cat $TEMP_BUILD/commitmessage
  echo $'\n'
  read -r -p "Commit message is correct? [y/n] " response
  case $response in
    [yY][eE][sS]|[yY])
      true
      ;;
    *)
      false
      ;;
  esac
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
    read -r -p "Are you sure you want to update libraries? [y/n] " response
    case $response in
      [yY][eE][sS]|[yY])
        true
        ;;
      *)
        false
        ;;
    esac
fi
}

BRANCH=
COMMITMESSAGE=
SKIP_CONFIRMATION=false
while getopts "h:b:m:y" OPTION
do
  case $OPTION in
    h)
      usage
      exit 1
      ;;
    b)
      BRANCH=$OPTARG
      ;;
    m)
      COMMITMESSAGE=$OPTARG
      ;;
    y)
      SKIP_CONFIRMATION=true
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

if [ "x$HOSTTYPE" == "x" ]; then
  usage
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

# Clone the hosting Repo first, as a bad argument can cause this to fail
echo "Cloning $HOSTTYPE Git Repo..."

# If host allows for multidev, check if a branch is specified
if [[ -z $BRANCH ]]; then
  git clone --depth=1 $GITREPO $TEMP_BUILD/$HOSTTYPE
else
  echo "Checkout $BRANCH branch..."
  git clone --depth=1 --branch $BRANCH $GITREPO $TEMP_BUILD/$HOSTTYPE
fi

echo "$HOSTTYPE Clone complete, calling build.sh -y $TEMP_BUILD/drupal..."
./scripts/build.sh -y $TEMP_BUILD/drupal

# Remove the scripts, vendor, & settings folders for security purposes:
rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/scripts
echo "rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/scripts"
rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/settings
echo "rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/settings"
rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/.circleci
echo "rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/.circleci"
rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/.github
echo "rm -rf $TEMP_BUILD/drupal/profiles/$PROJECT/.github"
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

if [[ -z $COMMITMESSAGE ]]; then
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
else
  echo $COMMITMESSAGE >> $TEMP_BUILD/commitmessage
fi

cd $TEMP_BUILD/drupal

if [[ -z $SKIP_CONFIRMATION ]]; then
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
fi

echo "Writing git ls-files -mo to $TEMP_BUILD/changes"
# Checkout files that we don't want removed from the host, like settings.php.
# This function should be defined in the host include script.
if [ "`type -t protectfiles`" = 'function' ]; then
  protectfiles
fi

# Don't bother sending .htaccess changes to Pantheon, since it uses nginx instead of apache
git checkout .htaccess

if [ -z "$(git status --porcelain)" ]; then
  echo "Nothing to commit. Skipping deploy."
else
  # Prepare commit
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
  git diff HEAD^ > $TEMP_BUILD/diff.patch
  echo $'\n'

  if [[ -z $SKIP_CONFIRMATION ]]; then
    if confirmpush; then
      git push
    else
      echo "Changes have not been pushed to Git Repository at $GITREPO."
      echo "To push changes:"
      echo "> cd $TEMP_BUILD/drupal"
      echo "> git push"
    fi
  else
    git push
  fi
fi

echo "Build script complete. Clean up temp files with:"
echo "rm -rf $TEMP_BUILD"
cd $ORIGIN
