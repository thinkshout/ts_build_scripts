#!/bin/bash
read -p "Are you sure you want to delete your local facing history site and rebuild? " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
    # do dangerous stuff
    ./scripts/build.sh ~/Sites/fh -y
    cd ~/Sites/fh
    drush sql-drop -y
    tbg facing-history
    drush updb -y
    drush pm-disable logs_http salesforce_pull -y
    drush en stage_file_proxy dblog -y
    drush cc all
    drush uli
fi
