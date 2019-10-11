#!/bin/bash
set -e

#
# Build the distribution using the same process used on Drupal.org
#
# Usage: ./scripts/build.sh [-y] <DESTINATION_PATH> <DB_USER> <DB_PASS> <DB_NAME> from the
# profile main directory. If any of the db params are excluded, the install
# profile will not be run, just built.
#

source settings/config.sh

confirm () {
  read -r -p "${1:-Are you sure? [y/N]} " response
  case $response in
    [yY][eE][sS]|[yY])
      true
      ;;
    *)
      false
      ;;
  esac
}

# Figure out directory real path.
realpath () {
  TARGET_FILE=$1

  cd `dirname $TARGET_FILE`
  TARGET_FILE=`basename $TARGET_FILE`

  while [ -L "$TARGET_FILE" ]
  do
    TARGET_FILE=`readlink $TARGET_FILE`
    cd `dirname $TARGET_FILE`
    TARGET_FILE=`basename $TARGET_FILE`
  done

  PHYS_DIR=`pwd -P`
  RESULT=$PHYS_DIR/$TARGET_FILE
  printf $RESULT
}

usage() {
  printf "Usage: ./scripts/build.sh [-y] <DESTINATION_PATH> <DB_USER> <DB_PASS> <DB_NAME>" >&2
  printf "Use -y to skip deletion confirmation" >&2
  printf "Install profile will only be run if db credentials are provided" >&2
  exit 1
}

DESTINATION=$1
DBUSER=$2
DBPASS=$3
DB=$4
ASK=true

while getopts ":y" opt; do
  case $opt in
    y)
      DESTINATION=$2
      DBUSER=$3
      DBPASS=$4
      DB=$5
      ASK=false
      ;;
    \?)
      printf "Invalid option: -$OPTARG" >&2
      usage
      ;;
  esac
done

if [ "x$DESTINATION" == "x" ]; then
  usage
fi

if [ ! -f drupal-org.make ]; then
  printf "[error] Run this script from the distribution base path."
  exit 1
fi

DESTINATION=$(realpath $DESTINATION)

case $OSTYPE in
  darwin*)
    TEMP_BUILD=`mktemp -d -t tmpdir`
    ;;
  *)
    TEMP_BUILD=`mktemp -d`
    ;;
esac
# Drush make expects destination to be empty.
rmdir $TEMP_BUILD

if [ -d $DESTINATION ]; then
  printf "Removing existing destination: $DESTINATION\n"
  if $ASK; then
    confirm && chmod -R 777 $DESTINATION && rm -rf $DESTINATION
    if [ -d $DESTINATION ]; then
      printf "Aborted.\n"
      exit 1
    fi
  else
    chmod -R 777 $DESTINATION && rm -rf $DESTINATION
  fi
  printf "Existing directories removed.\n"
fi

# Build the profile.
printf "Building the profile...\n"
drush make --no-core --contrib-destination --no-gitinfofile --concurrency=8 drupal-org.make tmp

# Resolve duplicate directory issue for ckeditor/plugins/youtube.
if [ $YOUTUBE_PLUGIN ]; then
  mv youtube tmp/modules/contrib/ckeditor/plugins/youtube/
  git checkout youtube
fi

# Build the distribution and copy the profile in place.
printf "Building the distribution...\n"
drush make --no-gitinfofile drupal-org-core.make $TEMP_BUILD
printf "Moving to destination...\n"
if [ -d tmp/profiles ]; then
  printf "Moving included distribution to its own profile directory...\n"
  cp -r tmp/profiles/ $TEMP_BUILD/profiles
  rm -rf tmp/profiles
fi

# Create the profile directory
if [ ! -z "$PROJECT" ]; then
  mkdir -p $TEMP_BUILD/profiles/$PROJECT
fi

# check for a distro name, otherwise the project name is the install profile.
if [ "x$DISTRO" == "x" ]; then
  PROFILE=$PROJECT
  cp -r tmp/* $TEMP_BUILD/profiles/$PROJECT
else
  PROFILE=$DISTRO
  # Our Project isn't actually a profile, so we need to explicitly create directory:
  cp -r tmp $TEMP_BUILD/profiles/$PROJECT
fi

rm -rf tmp
cp -a . $TEMP_BUILD/profiles/$PROJECT

# Execute build customizations
if [ "`type -t postbuild`" = 'function' ]; then
    echo "Executing postbuild commands..."
    cd $TEMP_BUILD
    postbuild
    cd -
fi
mv $TEMP_BUILD $DESTINATION

# set permissions on the sites/default directory
chmod 755 $DESTINATION/sites/default

# Inculde copies of the settings files that were used to build the site, for reference
SETTINGS_SITE="$DESTINATION/profiles/$PROJECT/settings"

cp $SETTINGS_SITE/*.php $DESTINATION/sites/default/
printf "Copied all settings files into place.\n"

# run the install profile
SETTINGS="$SETTINGS_SITE/settings_additions.php"
if [ $DBUSER  ] && [ $DBPASS ] && [ $DB ] ; then
  # If bash receives an error status, it will halt execution. Setting +e to tell
  # bash to continue even if error.
  set +e
  cd $DESTINATION
  printf "Running $PROFILE install profile...\n"
  drush si $PROFILE --site-name="$SITENAME" --db-url=mysql://$DBUSER:$DBPASS@localhost/$DB -y
  # Copy settings_additions.php if found
  printf "$SETTINGS\n"
  if [ -f $SETTINGS ]; then
    # ensure permissions on the sites/default directory allow writing
    # installation process will leave sites/default with 555 permissions
    chmod 755 $DESTINATION/sites/default
    printf "Appending settings_additions.php to settings.php \n"
    chmod 664 $DESTINATION/sites/default/settings.php
    cat $SETTINGS >> $DESTINATION/sites/default/settings.php
    chmod 444 $DESTINATION/sites/default/settings.php
  fi
  set -e
else
  printf "Skipping install profile and using default.settings.php\n"
  if [ ! -f $DESTINATION/sites/default/settings.php ]; then
    cp $DESTINATION/sites/default/default.settings.php $DESTINATION/sites/default/settings.php
  fi
  # Appending settings_additions.php to settings.php
  if [ -f $SETTINGS ]; then
    printf "Appending settings_additions.php to settings.php\n"
    cat $SETTINGS >> $DESTINATION/sites/default/settings.php
  fi
fi

# uncomment RewriteBase in project's .htaccess file
# necessary for Drupal sites running on a machine configured using ThinkShout standards
# see https://github.com/thinkshout/ts_recipes/tree/master/brew-lamp-dev-envt
# see https://github.com/thinkshout/ts_recipes/blob/master/environment_setup.sh
cd $DESTINATION
sed -i '' 's/# RewriteBase \/$/RewriteBase \//g' ./.htaccess
if [ "x$DISTRO" == "x$PROFILE" ]; then
  # remove the $PROJECT build directory, as it is not actually a profile.
  rm -rf profiles/$PROJECT
fi
printf "\nBuild script complete.\n"
