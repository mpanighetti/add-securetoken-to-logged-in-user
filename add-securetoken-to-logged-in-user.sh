#!/bin/bash

###
#
#            Name:  add-securetoken-to-logged-in-user.sh
#     Description:  Adds SecureToken to currently logged-in user. Prompts for
#                   password of SecureToken admin (gets SecureToken Admin
#                   Username from Jamf script parameter) and logged-in user.
#                   https://github.com/mpanighetti/add-securetoken-to-logged-in-user
#          Author:  Mario Panighetti
#         Created:  2017-10-04
#   Last Modified:  2018-11-29
#         Version:  3.0
#
###



########## variable-ing ##########



# local admin account with SecureToken access
# Jamf script parameter "SecureToken Admin Username"
securetokenAdmin="$5"
# need a default password value so the initial logic loops will properly fail when validating password
targetUserPass="foo"
# leave these values as-is
loggedInUser=$("/usr/bin/stat" -f%Su "/dev/console")
macosMinor=$("/usr/bin/sw_vers" -productVersion | "/usr/bin/awk" -F . '{print $2}')
macosBuild=$("/usr/bin/sw_vers" -productVersion | "/usr/bin/awk" -F . '{print $3}')



########## function-ing ##########



#exit with error if any required Jamf arguments are undefined
check_jamf_arguments () {
  jamfArguments=(
    "$securetokenAdmin"
  )
  for argument in "${jamfArguments[@]}"; do
    if [[ "$argument" = "" ]]; then
      "/bin/echo" "❌ ERROR: Undefined Jamf argument, unable to proceed."
      exit 74
    fi
  done
}


# exit if macOS < 10.13.4
check_macos () {
  if [[ "$macosMinor" -lt 13 || ( "$macosMinor" -eq 13 && "$macosBuild" -lt 4 ) ]]; then
    "/bin/echo" "SecureToken is only required in macOS 10.13.4 or later. No action required."
    exit 0
  fi
}


# exit with error if $secureTokenAdmin does not have SecureToken
check_securetoken_admin () {
  if [[ $("/usr/sbin/sysadminctl" -secureTokenStatus "$secureTokenAdmin" 2>&1) =~ "DISABLED" ]]; then
    "/bin/echo" "$secureTokenAdmin does not have a valid SecureToken, unable to proceed. Please update Jamf policy to target another admin user with SecureToken."
    exit 1
  else
    "/bin/echo" "Verified $secureTokenAdmin has SecureToken."
  fi
}


local_account_password_prompt () {
  targetUserPass=$("/usr/bin/osascript" <<EOT
tell application "System Events"
  activate
  set display_text to "Please enter password for user $1. $2"
  set user_password to text returned of (display dialog display_text default answer "" with hidden answer)
end tell
set myReply to user_password
EOT
  )
  if [[ "$targetUserPass" = "" ]]; then
    "/bin/echo" "❌ ERROR: A password was not entered for $1, unable to proceed. Please rerun policy; if issue persists, a manual SecureToken add will be required to continue."
    exit 1
  fi
}


local_account_password_validation () {
  passwordVerify=$("/usr/bin/dscl" /Local/Default authonly "$1" "$2" > "/dev/null" 2>&1; "/bin/echo" $?)
  if [[ "$passwordVerify" -eq 0 ]]; then
    "/bin/echo" "✅ Password successfully validated for $1."
  else
    "/bin/echo" "❌ Failed password validation for $1. Please reenter the password when prompted."
  fi
}


# add SecureToken to target user to allow FileVault access
securetoken_add () {
  "/usr/sbin/sysadminctl" \
    -adminUser "$1" \
    -adminPassword "$2" \
    -secureTokenOn "$3" \
    -password "$4"

  # verify successful SecureToken add
  secureTokenCheck=$("/usr/sbin/sysadminctl" -secureTokenStatus "$3" 2>&1)
  if [[ "$secureTokenCheck" =~ "DISABLED" ]]; then
    "/bin/echo" "❌ ERROR: Failed to add SecureToken to $3 for FileVault access. Please rerun policy; if issue persists, a manual SecureToken add will be required to continue."
    exit 126
  elif [[ "$secureTokenCheck" =~ "ENABLED" ]]; then
    "/bin/echo" "✅ Verified SecureToken is enabled for $3."
  else
    "/bin/echo" "❌ ERROR: Unexpected result, unable to proceed. Please rerun policy; if issue persists, a manual SecureToken add will be required to continue."
    exit 1
  fi
}



########## main process ##########



# exit if any required Jamf arguments are undefined
check_jamf_arguments


# verify Mac is running macOS 10.13.4+
check_macos


# verify $secureTokenAdmin actually has SecureToken
check_securetoken_admin


# add SecureToken to $loggedInUser if missing
while [[ $("/usr/sbin/sysadminctl" -secureTokenStatus "$loggedInUser" 2>&1) =~ "DISABLED" ]]; do

  # get $secureTokenAdmin password
  "/bin/echo" "$loggedInUser missing SecureToken, prompting for credentials..."
  while [[ $("/usr/bin/dscl" "/Local/Default" authonly "$securetokenAdmin" "$targetUserPass" > "/dev/null" 2>&1; "/bin/echo" $?) -ne 0 ]]; do
    local_account_password_prompt "$securetokenAdmin" "User's SecureToken credentials will be used to grant a new SecureToken to $loggedInUser."
    local_account_password_validation "$securetokenAdmin" "$targetUserPass"
  done
  securetokenAdminPass="$targetUserPass"

  # get $loggedInUser password
  while [[ $("/usr/bin/dscl" "/Local/Default" authonly "$loggedInUser" "$targetUserPass" > "/dev/null" 2>&1; "/bin/echo" $?) -ne 0 ]]; do
    local_account_password_prompt "$loggedInUser" "Need to add SecureToken for FileVault access."
    local_account_password_validation "$loggedInUser" "$targetUserPass"
  done
  loggedInUserPass="$targetUserPass"

  # add SecureToken using provided credentials
  securetoken_add "$securetokenAdmin" "$securetokenAdminPass" "$loggedInUser" "$loggedInUserPass"

done



exit 0
