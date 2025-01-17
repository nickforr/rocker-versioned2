#!/bin/bash

# Batch creation of user accounts in RStudio Server
#
# This script reads a list of username and password pairs from the
# `BATCH_USER_CREATION` environment variable and uses this information to create
# or update user accounts when the container starts.
#
# Each pair is of the format `username:password` and is separated from the next
# one by a semicolon, with no intervening whitespace. Usernames may only be up
# to 32 characters long (required by `useradd`). By default, the supplied
# passwords must be in clear-text (later encrypted by `chpasswd`). If the
# password is not specified, it is assumed to be equal to the username.
# 
# If a username already exists, the script will skip that particular account
# creation; otherwise, the user account will be created, the login shell set to
# Bash and the user's home directory created unless it already exists.
#
# By default, a group will be created for each new user with the same name as
# their username. If the groupname already exists, the script will skip the
# group creation. All users will also be added to the `staff` group (same as the
# default `rstudio` user).
#
# Finally, a directory called `.rstudio/monitored/user-settings/user-settings`
# is created in the user's home directory to store initial RStudio preferences.
#
# Users are not allowed to read other users' home directories.

set -e

# Remove spaces
remove_spaces() {
    local var="$*"
    # Remove all spaces
    var=${var//$' '/''}
    echo -e "$var"
    return 0
}

function create_user() {
    local username=$1
    local password=$2

    echo "Processing user '${username}'."

    if id -u "$username" >/dev/null 2>&1; then
        echo "${username} user already exists. Nothing else to do."
    else
        useradd -s /bin/bash -m "$username"
        # invalid user name
        if [ "$?" == 3 ]; then
            echo "Failed to create user '${username}'."
            return
        fi

        if [ -z "$password" ]; then
            echo "Password not provided. Setting it equals to username."
            password=${username}
        fi
        echo "${username}:${password}" | chpasswd

        usermod -a -G staff "${username}"

        mkdir -p "/home/${username}/.rstudio/monitored/user-settings"
        printf "alwaysSaveHistory='0' \
        \nloadRData='0' \
        \nsaveAction='0'" \
            >"/home/${username}/.rstudio/monitored/user-settings/user-settings"

        chown -R "${username}:${username}" "/home/${username}"
        # Prevent other users, but the owner, from accessing a home directory
        chmod 0700 "/home/${username}"
    fi

    # If shiny server installed, make the user part of the shiny group
    if [ -x "$(command -v shiny-server)" ]; then
        adduser "${username}" shiny
    fi

    echo "Done with user ${username}."
}

if [ -n "$BATCH_USER_CREATION" ]; then
    echo "Requested creation of multiple user accounts in batch mode."

    BATCH_USER_CREATION=$(remove_spaces "$BATCH_USER_CREATION")

    for user in $(echo "$BATCH_USER_CREATION" | tr ';' ' '); do
        IFS=: read -r username password <<<"${user}"

        if [ -z "$username" ]; then
            echo "Failed to create user: username undefined"
            continue
        else
            create_user "$username" "$password" || true
        fi
    done
    echo "Finished creation of multiple user accounts in batch mode."
fi
