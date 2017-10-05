# add-securetoken-to-logged-in-user

Adds SecureToken to currently logged-in user, allowing that user to unlock FileVault in macOS High Sierra. Uses credentials from a GUI-created admin account (retrieves from a manually-created System keychain entry), and prompts for current user's password.

This workflow is currently required to authorize programmatically-created user accounts (e.g. Active Directory users created with `createmobileaccount`) to be added to FileVault in macOS High Sierra.

## Credits

- `sysadminctl` SecureToken syntax discovered and formalized in [MacAdmins Slack](https://macadmins.slack.com) #filevault.
- AppleScript password prompt snippet found in [Stack Overflow answer](https://stackoverflow.com/a/17816746) from [scohe001](https://stackoverflow.com/users/2602718/scohe001).
