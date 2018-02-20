#!/bin/bash

###
#
#            Name:  add-securetoken-to-logged-in-user.sh
#     Description:  Adds SecureToken to currently logged-in user, allowing that
#                   user to unlock FileVault in macOS High Sierra. Uses
#                   credentials from a GUI-created admin account $guiAdmin
#                   (retrieves from a manually-created System keychain entry),
#                   and prompts for current user's password.
#                   https://github.com/mpanighetti/add-securetoken-to-logged-in-user
#          Author:  Mario Panighetti
#         Created:  2017-10-04
#   Last Modified:  2018-02-20
#         Version:  2.0
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
guiAdminPass=$("/usr/bin/sudo" "/usr/bin/security" find-generic-password -wa "$guiAdmin")
# leave these values as-is
loggedInUser=$("/usr/bin/stat" -f%Su "/dev/console")
secureTokenCheck=$("/usr/bin/sudo" "/usr/sbin/sysadminctl" -adminUser "$guiAdmin" -adminPassword "$guiAdminPass" -secureTokenStatus "$loggedInUser" 2>&1)
macosMinor=$("/usr/bin/sw_vers" -productVersion | "/usr/bin/awk" -F . '{print $2}')
macosBuild=$("/usr/bin/sw_vers" -productVersion | "/usr/bin/awk" -F . '{print $3}')



########## function-ing ##########



# exit script if macOS < 10.13.3
macos_check () {
  if [[ "$macosMinor" -ne 13 ]] || [[ "$macosBuild" -lt 3 ]]; then
    "/bin/echo" "❌ ERROR: Mac does not meet script requirements (macOS 10.13.3 or later). Update to the latest compatible macOS build, then run script again."
    exit 70
  fi
}


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
  "/usr/bin/sudo" "/usr/sbin/sysadminctl" \
    -adminUser "$guiAdmin" \
    -adminPassword "$guiAdminPass" \
    -secureTokenOn "$loggedInUser" \
    -password "$loggedInUserPass"
}


securetoken_double_check () {
  secureTokenCheck=$("/usr/bin/sudo" "/usr/sbin/sysadminctl" -adminUser "$guiAdmin" -adminPassword "$guiAdminPass" -secureTokenStatus "$loggedInUser" 2>&1)
  if [[ "$secureTokenCheck" =~ "DISABLED" ]]; then
    "/bin/echo" "❌ ERROR: Failed to add SecureToken to $loggedInUser for FileVault access."
    cred_clear
    exit 126
  else
    "/bin/echo" "✅ Verified SecureToken is enabled for $loggedInUser."
    cred_clear
  fi
}


cred_clear () {
  "/bin/echo" "Removing stored credentials and clearing password variables..."
  "/usr/bin/sudo" "/usr/bin/security" delete-generic-password -a "$guiAdmin"
  unset guiAdminPass
  unset loggedInUserPass
}



########## main process ##########



# verify Mac meets system requirements
macos_check

# add SecureToken to $loggedInUser if missing
if [[ "$secureTokenCheck" =~ "DISABLED" ]]; then
  securetoken_add
  securetoken_double_check
else
  "/bin/echo" "✅ Verified SecureToken is enabled for $loggedInUser."
  cred_clear
fi



exit 0
