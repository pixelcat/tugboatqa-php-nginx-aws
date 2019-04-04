#!/usr/bin/env bash

REPO_NAME=${1}
PROJECT_BASEDIR=/var/lib/tugboat

# check out patient-api project.
cd /var/lib
echo "Checking out project ${REPO_NAME} with branch 'master'."
git clone git@bitbucket.org:speareducation/${REPO_NAME} ${PROJECT_BASEDIR}
cd ${PROJECT_BASEDIR}

BRANCH_AVAILABLE=$(git branch -r | grep "${TUGBOAT_BITBUCKET_SOURCE}")
# Check for similar branch to the currently checked out one.
if [ "x${BRANCH_AVAILABLE}" != "x" ]; then
  echo "Checking out branch ${TUGBOAT_BITBUCKET_SOURCE}"
  # if the branch is available, check it out.
  git checkout ${TUGBOAT_BITBUCKET_SOURCE}
  if [ "x${TUGBOAT_BITBUCKET_DESTINATION}" != "x" ]; then
  echo "Merging branch ${TUGBOAT_BITBUCKET_DESTINATION} into ${TUGBOAT_BITBUCKET_SOURCE}."
    # Merge the destination branch.
    git merge ${TUGBOAT_BITBUCKET_DESTINATION}
  fi
fi

echo "Done."
