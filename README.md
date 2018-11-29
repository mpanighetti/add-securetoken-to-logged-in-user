# add-securetoken-to-logged-in-user

Adds SecureToken to currently logged-in user, allowing that user to unlock, enable, or disable FileVault on APFS volumes in macOS High Sierra or later. Prompts for password of SecureToken admin (gets the username from a Jamf script parameter) and logged-in user.

This workflow is currently required to authorize programmatically-created user accounts (that were not already explicitly given a SecureToken) to enable or use FileVault on APFS-formatted startup volumes in macOS High Sierra or later.

## Credits

- `sysadminctl` SecureToken syntax discovered and formalized in [MacAdmins Slack](https://macadmins.slack.com) #filevault.
