 [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# Winget Updater

**Effortless, automated updates for your Windows apps.**

Winget Updater takes the headache out of keeping your software up-to-date. It sits on top of the powerful Windows Package Manager (WinGet) to provide a simple, set-and-forget experience.

## Why use Winget Updater?

- **Set and Forget**: you can configure it once to run at startup and/or when you wake up your computer, and never worry about outdated apps again.
- **You are in Control**: a simple menu lets you easily pick which apps should update automatically or manually.
- **Clean & Simple**: you can easily check for available updates without having to manually type in each update request.

## Installation

1. **Download the latest release** from the [Releases tab](../../releases/latest) in the sidebar.
2. Extract the files.
3. Double-click `install-winget-updater.bat`.
   - _Note: This will ask for administrator permissions to set up the automation._
4. Follow the simple on-screen prompts to choose when you want updates to run.
5. _You can now delete the downloaded files._

## Usage

As long as you configured it to run at startup or when you wake up your computer, **you don't need to do anything!** Winget Updater will run automatically. Once per day maximum, it will check for updates, and only bother you when it encounters new applications which you haven't already set to "Run automatically" or "Blocked" from being updated.

If you ever want to check for updates manually or change your settings:

1. Open your Start Menu.
2. Search for **Winget Updater** and run it.
3. _If you press any key at the start of the script, or press E after it has finished, you will be given the option to edit the settings for previously encountered applications._

### Advanced Usage (Command Line)

For power users who prefer the terminal, after installation you can run:

```powershell
& "$env:LOCALAPPDATA\WingetUpdater\winget-updater.ps1"
```

**Command Line Options:**

- `-Silent`: Runs without any popups (perfect for background tasks).
- `-Minimal`: Shows only the most important status messages.
- `-Forced`: Checks for updates even if it has already run today.
- `-NoClear`: Prevents clearing the console when the script starts.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
