#!/bin/bash

. $GITHUB_ACTION_PATH/setup_version.sh

function version {
    echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

function deploy {
    # if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_REGION" ]; then
    #     echo "Error: AWS credentials are not set."
    #     exit 1
    # fi

    # aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
    # aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
    # aws configure set region "$AWS_REGION"

    if [ ! -d "$INPUT_FOLDER" ]; then
        echo "Error: Directory $INPUT_FOLDER does not exist. Nothing to deploy."
        exit 1
    fi
    S3_URL="s3://$INPUT_AWS_BUCKET/$PREFIX/"
    echo "Uploading to $S3_URL"
    aws s3 sync $INPUT_FOLDER $S3_URL || exit 1

    preview_url="https://$INPUT_AWS_BUCKET.s3.amazonaws.com/$PREFIX/index.html"
    echo "preview_url=$preview_url" >> $GITHUB_OUTPUT
}

function s3branchrotate {
    new_list=("$1")
    for b in $(cat $2); do
        [[ $b != "$1" ]] && new_list+=("$b")
    done;
    printf "%s\n" "${new_list[@]}" > $2
}

function cleanup_branch_folders() {
    echo "Cleanup branch folders"
    aws s3 cp s3://$INPUT_AWS_BUCKET/.branches .branches_old
    
    s3branchrotate $escaped_branch_name .branches_old

    lines_count=$(cat .branches_old | wc -l)
    last_branch=$(tail -1 .branches_old)
    head -$INPUT_MAX_BRANCH_DEPLOYED .branches_old > .branches
    aws s3 cp .branches s3://$INPUT_AWS_BUCKET/
    [ "$lines_count" -gt "$INPUT_MAX_BRANCH_DEPLOYED" ] && aws s3 rm --recursive s3://$INPUT_AWS_BUCKET/$last_branch/
}

function cleanup_commit_folders {
    echo "Cleanup commit folders"
    aws s3 ls s3://$INPUT_AWS_BUCKET/$escaped_branch_name/ | awk '$NF ~ /\/$/ { print $NF }' > .commit_versions
    cat .commit_versions  # Debug: print the versions

    oldest_version=$(head -1 .commit_versions)
    versions_count=$(cat .commit_versions | wc -l)
    echo "Oldest version: $oldest_version"
    echo "Versions count: $versions_count"

    if [ "$versions_count" -gt "$INPUT_MAX_COMMIT_PER_BRANCH_DEPLOYED" ]; then
        echo "Removing oldest version: $oldest_version"
        aws s3 rm --recursive s3://$INPUT_AWS_BUCKET/$escaped_branch_name/$oldest_version || echo "Error removing version"
    else
        echo "No need to remove versions."
    fi
}

echo "=== STARTING ==="
echo "GITHUB_REF: $GITHUB_REF"

echo "=== Setting up version ==="
setup_verion
echo "Branch: $BRANCH_NAME"

echo "=== Deploying ==="
deploy

echo "=== Cleanup branch folders ==="
cleanup_branch_folders

echo "=== Cleanup commit folders ==="
cleanup_commit_folders

echo " === FINISHED SUCCESSFULLY ==="
