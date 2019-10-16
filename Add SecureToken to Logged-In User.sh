#!/bin/bash

###
#
#            Name:  Add SecureToken to Logged-In User.sh
#     Description:  Adds SecureToken to currently logged-in user. Prompts for
#                   password of SecureToken admin (gets SecureToken Admin
#                   Username from Jamf Pro script parameter) and logged-in user.
#                   https://github.com/mpanighetti/add-securetoken-to-logged-in-user
#          Author:  Mario Panighetti
#         Created:  2017-10-04
#   Last Modified:  2019-10-16
#         Version:  3.1
#
###



########## variable-ing ##########



# Local admin account with SecureToken access.
# Jamf Pro script parameter: "SecureToken Admin Username"
secureTokenAdmin="$5"
# Need a default password value so the initial logic loops will properly fail
# when validating password.
targetUserPass="foo"
# Leave these values as-is.
loggedInUser=$(/usr/bin/stat -f%Su "/dev/console")
macosMinor=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F . '{print $2}')
macosBuild=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F . '{print $3}')



########## function-ing ##########



# Exit with error if any required Jamf Pro arguments are undefined.
function check_jamf_pro_arguments {
  jamfProArguments=(
    "$secureTokenAdmin"
  )
  for argument in "${jamfProArguments[@]}"; do
    if [[ -z "$argument" ]]; then
      /bin/echo "❌ ERROR: Undefined Jamf Pro argument, unable to proceed."
      exit 74
    fi
  done
}


# Exit if macOS < 10.13.4.
function check_macos {
  if [[ "$macosMinor" -lt 13 || ( "$macosMinor" -eq 13 && "$macosBuild" -lt 4 ) ]]; then
    /bin/echo "SecureToken is only applicable in macOS 10.13.4 or later. No action required."
    exit 0
  fi
}


# Exit if $loggedInUser already has SecureToken.
function check_securetoken_logged_in_user {
  if [[ $(/usr/sbin/sysadminctl -secureTokenStatus "$loggedInUser" 2>&1) =~ "ENABLED" ]]; then
    /bin/echo "$loggedInUser already has a SecureToken. No action required."
    exit 0
  fi
}


# Exit with error if $secureTokenAdmin does not have SecureToken.
function check_securetoken_admin {
  if [[ $(/usr/sbin/sysadminctl -secureTokenStatus "$secureTokenAdmin" 2>&1) =~ "DISABLED" ]]; then
    /bin/echo "❌ ERROR: $secureTokenAdmin does not have a valid SecureToken, unable to proceed. Please update Jamf Pro policy to target another admin user with SecureToken."
    exit 1
  else
    /bin/echo "✅ Verified $secureTokenAdmin has SecureToken."
  fi
}


# Prompt for local password.
function local_account_password_prompt {
  targetUserPass=$(/usr/bin/osascript <<EOT
tell application "System Events"
  activate
  set user_password to text returned of (display dialog "Please enter password for $1$2" default answer "" with hidden answer)
end tell
set myReply to user_password
EOT
  )
  if [[ "$targetUserPass" = "" ]]; then
    /bin/echo "❌ ERROR: A password was not entered for $1, unable to proceed. Please rerun policy; if issue persists, a manual SecureToken add will be required to continue."
    exit 1
  fi
}


# Validate provided password.
function local_account_password_validation {
  passwordVerify=$(/usr/bin/dscl "/Local/Default" authonly "$1" "$2" > "/dev/null" 2>&1; /bin/echo $?)
  if [[ "$passwordVerify" -eq 0 ]]; then
    /bin/echo "✅ Password successfully validated for $1."
  else
    /bin/echo "❌ ERROR: Failed password validation for $1. Please reenter the password when prompted."
  fi
}


# Add SecureToken to target user.
function securetoken_add {
  /usr/sbin/sysadminctl \
    -adminUser "$1" \
    -adminPassword "$2" \
    -secureTokenOn "$3" \
    -password "$4"

  # Verify successful SecureToken add.
  secureTokenCheck=$(/usr/sbin/sysadminctl -secureTokenStatus "$3" 2>&1)
  if [[ "$secureTokenCheck" =~ "DISABLED" ]]; then
    /bin/echo "❌ ERROR: Failed to add SecureToken to $3. Please rerun policy; if issue persists, a manual SecureToken add will be required to continue."
    exit 126
  elif [[ "$secureTokenCheck" =~ "ENABLED" ]]; then
    /bin/echo "SecureToken add successful."
  else
    /bin/echo "❌ ERROR: Unexpected result, unable to proceed. Please rerun policy; if issue persists, a manual SecureToken add will be required to continue."
    exit 1
  fi
}



########## main process ##########



# Check exit conditions before proceeding.
check_jamf_pro_arguments
check_macos
check_securetoken_logged_in_user
check_securetoken_admin


# Add SecureToken to $loggedInUser.
while [[ $(/usr/sbin/sysadminctl -secureTokenStatus "$loggedInUser" 2>&1) =~ "DISABLED" ]]; do

  # Get $secureTokenAdmin password.
  /bin/echo "$loggedInUser missing SecureToken, prompting for credentials..."
  while [[ $(/usr/bin/dscl "/Local/Default" authonly "$secureTokenAdmin" "$targetUserPass" > "/dev/null" 2>&1; /bin/echo $?) -ne 0 ]]; do
    local_account_password_prompt "$secureTokenAdmin" ". User's credentials are needed to grant a SecureToken to $loggedInUser."
    local_account_password_validation "$secureTokenAdmin" "$targetUserPass"
  done
  secureTokenAdminPass="$targetUserPass"

  # Get $loggedInUser password.
  while [[ $(/usr/bin/dscl "/Local/Default" authonly "$loggedInUser" "$targetUserPass" > "/dev/null" 2>&1; /bin/echo $?) -ne 0 ]]; do
    local_account_password_prompt "$loggedInUser" " to add SecureToken."
    local_account_password_validation "$loggedInUser" "$targetUserPass"
  done
  loggedInUserPass="$targetUserPass"

  # Add SecureToken using provided credentials.
  securetoken_add "$secureTokenAdmin" "$secureTokenAdminPass" "$loggedInUser" "$loggedInUserPass"

done


# Echo successful result.
/bin/echo "✅ Verified SecureToken is enabled for $loggedInUser."



exit 0
