#!/bin/zsh

###
#
#            Name:  Add SecureToken to Logged-In User.zsh
#     Description:  Adds SecureToken to currently logged-in user to prepare
#                   system for enabling FileVault. Prompts for password of
#                   SecureToken admin (gets SecureToken Admin Username from Jamf
#                   Pro script parameter) and logged-in user.
#                   https://github.com/mpanighetti/add-securetoken-to-logged-in-user
#          Author:  Mario Panighetti
#         Created:  2017-10-04
#   Last Modified:  2021-01-11
#         Version:  3.4
#
###



########## variable-ing ##########



# Jamf Pro script parameter: "SecureToken Admin Username"
# Local admin account with SecureToken access.
secureTokenAdmin="$5"
# Need a default password value so the initial logic loops will properly fail
# when validating passwords.
targetUserPass="foo"
loggedInUser=$(/usr/bin/stat -f%Su "/dev/console")
macOSVersionMajor=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F . '{print $1}')
macOSVersionMinor=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F . '{print $2}')
macOSVersionBuild=$(/usr/bin/sw_vers -productVersion | /usr/bin/awk -F . '{print $3}')



########## function-ing ##########



# Exits with error if any required Jamf Pro arguments are undefined.
function check_jamf_pro_arguments {
  if [[ -z "$secureTokenAdmin" ]]; then
    echo "❌ ERROR: Undefined Jamf Pro argument, unable to proceed."
    exit 74
  fi
}


# Exits if macOS version does not meet script requirements.
function check_macos_version {
  # Exit with error if macOS < 10.
  if [[ "$macOSVersionMajor" -lt 10 ]]; then
    echo "❌ ERROR: macOS version ($(/usr/bin/sw_vers -productVersion)) incompatible, unable to proceed."
    exit 1
  # Exit if macOS 10 < 10.13.4.
elif [[ "$macOSVersionMajor" -eq 10 ]] && ][[ "$macOSVersionMinor" -lt 13 || ( "$macOSVersionMinor" -eq 13 && "$macOSVersionBuild" -lt 4 ) ]]; then
    echo "SecureToken is only applicable in macOS 10.13.4 or later. No action required."
    exit 0
  fi
}


# Exits if root is the currently logged-in user, or no logged-in user is detected.
function check_logged_in_user {
  if [ "$loggedInUser" = "root" ] || [ -z "$loggedInUser" ]; then
    echo "Nobody is logged in."
    exit 0
  fi
}


# Exits if $loggedInUser already has SecureToken.
function check_securetoken_logged_in_user {
  if [[ $(/usr/sbin/sysadminctl -secureTokenStatus "$loggedInUser" 2>&1) =~ "ENABLED" ]]; then
    echo "$loggedInUser already has a SecureToken. No action required."
    exit 0
  fi
}


# Exits with error if $secureTokenAdmin does not have SecureToken
# (unless running macOS 10.15 or later, in which case exit with explanation).
function check_securetoken_admin {
  if [[ $(/usr/sbin/sysadminctl -secureTokenStatus "$secureTokenAdmin" 2>&1) =~ "DISABLED" ]]; then
    if [[ "$macOSVersionMajor" -gt 10 || ( "$macOSVersionMajor" -eq 10 && "$macOSVersionMinor" -gt 14 ) ]]; then
      echo "⚠️ Neither $secureTokenAdmin nor $loggedInUser has a SecureToken, but in macOS 10.15 or later, a SecureToken is automatically granted to the first user to enable FileVault (if no other users have SecureToken), so this may not be necessary. Try enabling FileVault for $loggedInUser. If that fails, see what other user on the system has SecureToken, and use its credentials to grant SecureToken to $loggedInUser."
      exit 0
    else
      echo "❌ ERROR: $secureTokenAdmin does not have a valid SecureToken, unable to proceed. Please update Jamf Pro policy to target another admin user with SecureToken."
      exit 1
    fi
  else
    echo "✅ Verified $secureTokenAdmin has SecureToken."
  fi
}


# Prompts for local password.
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
    echo "❌ ERROR: A password was not entered for $1, unable to proceed. Please rerun policy; if issue persists, a manual SecureToken add will be required to continue."
    exit 1
  fi
}


# Validates provided password.
function local_account_password_validation {
  passwordVerify=$(/usr/bin/dscl "/Local/Default" authonly "$1" "$2" > "/dev/null" 2>&1; echo $?)
  if [[ "$passwordVerify" -eq 0 ]]; then
    echo "✅ Password successfully validated for $1."
  else
    echo "❌ ERROR: Failed password validation for $1. Please reenter the password when prompted."
  fi
}


# Adds SecureToken to target user.
function securetoken_add {
  /usr/sbin/sysadminctl \
    -adminUser "$1" \
    -adminPassword "$2" \
    -secureTokenOn "$3" \
    -password "$4"

  # Verify successful SecureToken add.
  secureTokenCheck=$(/usr/sbin/sysadminctl -secureTokenStatus "$3" 2>&1)
  if [[ "$secureTokenCheck" =~ "DISABLED" ]]; then
    echo "❌ ERROR: Failed to add SecureToken to $3. Please rerun policy; if issue persists, a manual SecureToken add will be required to continue."
    exit 126
  elif [[ "$secureTokenCheck" =~ "ENABLED" ]]; then
    echo "SecureToken add successful."
  else
    echo "❌ ERROR: Unexpected result, unable to proceed. Please rerun policy; if issue persists, a manual SecureToken add will be required to continue."
    exit 1
  fi
}



########## main process ##########



# Check script prerequisites.
check_jamf_pro_arguments
check_macos_version
check_logged_in_user
check_securetoken_logged_in_user
check_securetoken_admin


# Add SecureToken to $loggedInUser.
while [[ $(/usr/sbin/sysadminctl -secureTokenStatus "$loggedInUser" 2>&1) =~ "DISABLED" ]]; do

  # Get $secureTokenAdmin password.
  echo "$loggedInUser missing SecureToken, prompting for credentials..."
  while [[ $(/usr/bin/dscl "/Local/Default" authonly "$secureTokenAdmin" "$targetUserPass" > "/dev/null" 2>&1; echo $?) -ne 0 ]]; do
    local_account_password_prompt "$secureTokenAdmin" ". User's credentials are needed to grant a SecureToken to $loggedInUser."
    local_account_password_validation "$secureTokenAdmin" "$targetUserPass"
  done
  secureTokenAdminPass="$targetUserPass"

  # Get $loggedInUser password.
  while [[ $(/usr/bin/dscl "/Local/Default" authonly "$loggedInUser" "$targetUserPass" > "/dev/null" 2>&1; echo $?) -ne 0 ]]; do
    local_account_password_prompt "$loggedInUser" " to add SecureToken."
    local_account_password_validation "$loggedInUser" "$targetUserPass"
  done
  loggedInUserPass="$targetUserPass"

  # Add SecureToken using provided credentials.
  securetoken_add "$secureTokenAdmin" "$secureTokenAdminPass" "$loggedInUser" "$loggedInUserPass"

done


# Echo successful result.
echo "✅ Verified SecureToken is enabled for $loggedInUser."



exit 0
