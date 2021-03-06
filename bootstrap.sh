#!/bin/bash

PROJECT=$1

[[ -z "$PROJECT" ]] && { echo "Please specify a project name" ; exit 1; }

git mv ts_build.info $PROJECT.info
git mv ts_build.install $PROJECT.install
git mv ts_build.profile $PROJECT.profile
cp vendor/thinkshout/ts_build_scripts/default.config.sh config.sh
cp -R vendor/thinkshout/ts_build_scripts/default.circleci .circleci

sed -i "" "s/ts_build/$PROJECT/g" $PROJECT.info
sed -i "" "s/ts_build/$PROJECT/g" $PROJECT.install
sed -i "" "s/ts_build/$PROJECT/g" $PROJECT.profile
sed -i "" "s/ts_build/$PROJECT/g" config.sh

git add $PROJECT.info
git add $PROJECT.install
git add $PROJECT.profile
git add config.sh

git commit -m "bootstrap $PROJECT"

Echo "Review your new project configuration in ./config.sh."