#!/bin/sh

echo Commit hash: ${ghprbActualCommit}
echo Changes in this commit:
export COMMIT_CHANGES=`git diff --name-only --stat origin/master`
echo ${COMMIT_CHANGES}

wget https://raw.githubusercontent.com/KSP-CKAN/CKAN/master/bin/ckan-validate.py -O ckan-validate.py
wget https://raw.githubusercontent.com/KSP-CKAN/CKAN/master/CKAN.schema -O CKAN.schema
chmod a+x ckan-validate.py
./ckan-validate.py ${COMMIT_CHANGES}

# fetch latest ckan.exe
wget -O ckan.exe http://ci.ksp-ckan.org:8080/job/CKAN/lastSuccessfulBuild/artifact/ckan.exe

# create a dummy KSP install
mkdir dummy_ksp
echo Version 0.90.0 > dummy_ksp/readme.txt
mkdir dummy_ksp/GameData

mono --debug ckan.exe ksp add default "`pwd`/dummy_ksp"
mono --debug ckan.exe ksp default default
mono --debug ckan.exe update

for f in ${COMMIT_CHANGES}
do
	mono --debug ckan.exe install -c $f
done
