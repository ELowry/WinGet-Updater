[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# Winget Updater

**Effortless, automated updates for your Windows apps.**

Winget Updater takes the headache out of keeping your software up-to-date. It sits on top of the powerful Windows Package Manager (WinGet) to provide a simple, set-and-forget experience.

## Why use Winget Updater?

- **Set and Forget**: you can configure it once to run at startup and/or when you wake up your computer, and never worry about outdated apps again.
- **You are in Control**: a simple menu lets you easily pick which apps should update automatically or manually.
- **Clean & Simple**: you can easily check for available updates without having to manually type in each update request.

## Installation

### Option 1: Installer

1. **Download the latest version of `WingetUpdaterSetup.exe`** from the [Releases tab](../../releases/latest).
2. Run the installer.
3. Choose your automation settings (Run at Startup / Wake) during setup.
4. That's it!

### Option 2: Portable / Zip

1. **Download the latest version of `WinGet-Updater.zip`** from the [Releases tab](../../releases/latest).
2. Extract the files.
3. Double-click `install-winget-updater.bat`.
   > [!NOTE]
   > This will ask for administrator permissions to set up the automation.
4. Follow the simple on-screen prompts to choose your automation settings (Run at Startup / Wake).
   > [!IMPORTANT]
   > You can now delete the downloaded files.

## Usage

As long as you configured it to run at startup or when you wake up your computer, **you don't need to do anything!** Winget Updater will run automatically. Once per day maximum, it will check for updates, and only bother you when it encounters new applications which you haven't already set to "Run automatically" or "Blocked" from being updated.

If you ever want to check for updates manually or change your settings:

1. Open your Start Menu.
2. Search for **Winget Updater** and run it.
   > [!TIP]
   > If you press E during the short delay at the start of the script or after it has finished, you will be given the option to edit the settings for previously encountered applications.

### Advanced Usage (command line)

For power users who prefer the terminal, after installation you can run:

```powershell
& "$env:LOCALAPPDATA\WingetUpdater\winget-updater.ps1"
```

**Command Line Options:**

- `-Minimal`: Shows only the most important status messages.
  - _Enabled by default during scheduled runs._
- `-Silent`: Runs without any popups unless the script encounters unknown apps.
- `-NoClear`: Prevents clearing the console when the script starts.

### Customizing Update Options

You can configure specific [update options](https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade#options) for individual applications (e.g., `--interactive`, `--location`, `--force`, etc.). This is useful for apps that require special handling or user input during updates.

- When prompted to choose an action for an update, select **[O]ptions**.
- In the "Edit Mode" (press `E` during startup/exit), select an app and choose **[O]ptions**.

> [!NOTE]
> The `--accept-source-agreements` and `--accept-package-agreements` flags are included by default.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
