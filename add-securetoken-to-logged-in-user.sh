#!/bin/bash

###
#
#            Name:  add-securetoken-to-logged-in-user.sh
#     Description:  Adds SecureToken to currently logged-in user, allowing that
#                   user to enable or use FileVault in macOS High Sierra. Uses
#                   credentials from a GUI-created admin account $guiAdmin
#                   (retrieves from a manually-created System keychain entry),
#                   and prompts for current user's password.
#                   https://github.com/mpanighetti/add-securetoken-to-logged-in-user
#          Author:  Mario Panighetti
#         Created:  2017-10-04
#   Last Modified:  2018-05-15
#         Version:  2.2
#
###



########## variable-ing ##########



# replace with username of a GUI-created admin account
# (or any admin user with SecureToken access)
guiAdmin="guiadmin-username"
# This sample script assumes that the $guiAdmin account credentials have
# already been saved in the System keychain in an entry named "$guiAdmin".
# If you want to prompt for this information instead of pulling from the
# keychain, you can copy the osascript from securetoken_add to generate a new
# prompt, and pass the result to $guiAdminPass.
# leave these values as-is
loggedInUser=$("/usr/bin/stat" -f%Su "/dev/console")
macosMinor=$("/usr/bin/sw_vers" -productVersion | "/usr/bin/awk" -F . '{print $2}')
macosBuild=$("/usr/bin/sw_vers" -productVersion | "/usr/bin/awk" -F . '{print $3}')



########## function-ing ##########



# exit script if macOS < 10.13.3
macos_check () {
  if [[ "$macosMinor" -ne 13 ]] || [[ "$macosBuild" -lt 4 ]]; then
    "/bin/echo" "❌ ERROR: Mac does not meet script requirements (macOS 10.13.4 or later). Update to the latest compatible macOS build, then run script again."
    exit 70
  fi
}


# exit script if not runnning as root
if [[ $EUID -ne 0 ]]; then
    "/bin/echo" "❌ ERROR: This script must run as root."
    exit 1
fi


# add SecureToken to $loggedInUser account to allow FileVault access
securetoken_add () {
  # https://stackoverflow.com/a/17816746
  loggedInUserPass=$("/usr/bin/osascript" <<EOT
tell application "System Events"
  with timeout of 86400 seconds
    activate
    set display_text to "$loggedInUser missing SecureToken required for FileVault access. Please enter the user's password."
    repeat
      considering case
        set init_pass to text returned of (display dialog display_text default answer "" with hidden answer)
        set final_pass to text returned of (display dialog "Please verify the password for $loggedInUser." buttons {"OK"} default button 1 default answer "" with hidden answer)
        if (final_pass = init_pass) then
          exit repeat
        else
          set display_text to "Passwords do not match, please try again."
        end if
      end considering
    end repeat
  end timeout
end tell
set myReply to final_pass
EOT
    )
  if [[ "$loggedInUserPass" = "" ]]; then
     "/bin/echo" "❌ ERROR: A password was not entered for $loggedInUser, unable to proceed. Try running the script again; if issue persists, a manual SecureToken add will be required."
     exit 1
  else
    guiAdminPass=$("/usr/bin/security" find-generic-password -wa "$guiAdmin" "/Library/Keychains/System.keychain")
    "/usr/sbin/sysadminctl" \
      -adminUser "$guiAdmin" \
      -adminPassword "$guiAdminPass" \
      -secureTokenOn "$loggedInUser" \
      -password "$loggedInUserPass"
    unset guiAdminPass
    unset loggedInUserPass
  fi


  # verify successful SecureToken add
  secureTokenCheck=$("/usr/sbin/sysadminctl" -secureTokenStatus "$loggedInUser" 2>&1)
  if [[ "$secureTokenCheck" =~ "DISABLED" ]]; then
    "/bin/echo" "❌ ERROR: Failed to add SecureToken to $loggedInUser for FileVault access. Try running the script again; if issue persists, a manual SecureToken add will be required."
    exit 126
  elif [[ "$secureTokenCheck" =~ "ENABLED" ]]; then
    "/bin/echo" "✅ Verified SecureToken is enabled for $loggedInUser."
    cred_clear
  else
    "/bin/echo" "❌ ERROR: Unexpected result, unable to proceed. Try running the script again; if issue persists, a manual SecureToken add will be required."
    exit 1
  fi
}


# delete $guiAdmin credentials from System keychain
cred_clear () {
  "/bin/echo" "Removing stored credentials for $guiAdmin..."
  "/usr/bin/security" delete-generic-password -a "$guiAdmin" "/Library/Keychains/System.keychain"
}



########## main process ##########



# verify Mac meets system requirements
macos_check
root_check


# add SecureToken to $loggedInUser if missing
if [[ $("/usr/sbin/sysadminctl" -secureTokenStatus "$loggedInUser" 2>&1) =~ "DISABLED" ]]; then
  securetoken_add
else
  "/bin/echo" "✅ Verified SecureToken is enabled for $loggedInUser."
  cred_clear
fi



exit 0
