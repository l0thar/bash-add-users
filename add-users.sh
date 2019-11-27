#!/bin/bash

declare -A USERS_TO_CREATE

function add_admin_group_if_it_doesnt_exist {
    if ! grep -q admin /etc/group; then
        echo "Admin group does not exist... creating"
        addgroup --system admin
    fi
}

function configure_sudoers_file_to_not_require_passwords_for_admins {
    echo -e -n "\nConfiguring /etc/sudoers file..."
    chmod u+w /etc/sudoers
    sed -i -r 's/\%admin ALL\=\(ALL\) ALL/\%admin ALL\=\(ALL\) NOPASSWD\: ALL/' /etc/sudoers
    chmod u-w /etc/sudoers
    visudo -c
    if [ 1 -eq $? ]; then
        visudo
    fi
    echo "done."
}

function load_users_from_file_and_add_to_create_list {
    filename=$1
    while IFS= read -r line; do
            USERS_TO_CREATE[${line%%\:*}]=${line#*\:}
    done < <(grep -vE '^(\s*$|#)' ./public_keys/$filename)
}

function create_user_if_they_dont_already_exist {
    if ! getent passwd $username > /dev/null 2>&1; then
        create_user_and_set_random_password
        set_up_home_and_ssh_directories
        add_public_key_to_authorized_keys_file 
    else
        echo -e "\nUser: $user already exists, skipping."
    fi
}

function create_user_and_set_random_password {
    echo -e "\nCreating user: $username" | cat -v
    password=$(date | md5sum)
    useradd -G admin -s /bin/bash -d /home/$username $username
    (echo "$password"; echo "$password") | passwd $username
    chage -M 90 $username
    chage -I -1 $username
}

function set_up_home_and_ssh_directories {
    echo "Creating /home/$username and /home/$username/.ssh directories"
    mkdir /home/$username
    chown $username:users /home/$username
    su -c "mkdir --mode=700 /home/$username/.ssh" $username
}

function add_public_key_to_authorized_keys_file {
    echo "Adding public key to authorized_key file."
    su -c "echo '$public_key' > /home/$username/.ssh/authorized_keys" $username
}

##### MAIN #####
add_admin_group_if_it_doesnt_exist
configure_sudoers_file_to_not_require_passwords_for_admins

read -p "Do you want to add the US IT users? (y/n): " add_us_it
if [ $add_us_it = "y" ]; then
    load_users_from_file_and_add_to_create_list "us_it"
fi

read -p "Do you want to add the US DBA users? (y/n): " add_us_dbas
if [ $add_us_dbas = "y" ]; then
    load_users_from_file_and_add_to_create_list "us_dbas"
fi

read -p "Do you need to add custom users from a custom_users file? (y/n): " add_custom_users
if [ $add_custom_users = "y" ]; then
    load_users_from_file_and_add_to_create_list "custom_users"
fi

for user in "${!USERS_TO_CREATE[@]}"; do
    username=$user
    public_key=${USERS_TO_CREATE[$user]}

    create_user_if_they_dont_already_exist
done
