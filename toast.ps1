<#
.SYNOPSIS
    Creates a Windows toast notification with customizable options and using BurntToast module.
.DESCRIPTION
    This script creates a Windows toast notification with a customizable image, title, message, 
    and options for snooze and reminder functionality.
.PARAMETER Title
    The title text for the notification.
.PARAMETER Message
    The message text for the notification.
.PARAMETER ImagePath
    The path to the image to be displayed. Defaults to 'C:\ws\emacs.png'.
.PARAMETER EnableSnooze
    Whether to enable snooze functionality. Default is $true.
.PARAMETER ReminderMode
    Whether to use reminder mode for the notification. Default is $true.
.PARAMETER AppId
    Specify appid (see Get-StartApps)
.EXAMPLE
    .\toast.ps1 "Hello World" "This is a test notification"
.EXAMPLE
    .\toast.ps1 -Title "Meeting" -Message "Team meeting in 5 minutes" -EnableSnooze $true
#>

param (
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Title,
    
    [Parameter(Mandatory=$true, Position=1)]
    [string]$Message,
    
    [Parameter(Mandatory=$false)]
    [string]$ImagePath = "C:\ws\emacs.png",
    
    [Parameter(Mandatory=$false)]
    [bool]$EnableSnooze = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$ReminderMode = $true,

    [Parameter(Mandatory=$false)]
    [string]$AppID = "Microsoft.Windows.PowerShell"
)

function Send-BTToast {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ImagePath,
        
        [Parameter(Mandatory=$true)]
        [string]$Title,
        
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [bool]$EnableSnooze = $true,
        
        [Parameter(Mandatory=$false)]
        [bool]$ReminderMode = $true,

        [Parameter(Mandatory=$false)]
        [string]$AppID = "Microsoft.Windows.PowerShell"
    )
    
    # Create the image for the notification
    $icon = New-BTImage -Source $ImagePath -AppLogoOverride
    
    # Create the text elements
    $text1 = New-BTText -Text $Title
    $text2 = New-BTText -Text $Message
    
    # Create binding with the elements
    $binding = New-BTBinding -Children @($text1, $text2) -AppLogoOverride $icon
    
    # Create the visual element
    $visual = New-BTVisual -BindingGeneric $binding
    
    # Define action variable
    $action = $null
    
    # Check if snooze is enabled
    if ($EnableSnooze) {
        # Create snooze options
        $5min = New-BTSelectionBoxItem -Id 5 -Content '5 minutes'
        $10min = New-BTSelectionBoxItem -Id 10 -Content '10 minutes'
        $1hour = New-BTSelectionBoxItem -Id 60 -Content '1 heure'
        $4hours = New-BTSelectionBoxItem -Id 240 -Content '4 heures'
        $items = $5min, $10min, $1hour, $4hours
        
        # Create selection box for snooze times
        $selectionBox = New-BTInput -Id 'SnoozeTime' -DefaultSelectionBoxItemId 10 -Items $items
        
        # Create buttons
        $snoozeButton = New-BTButton -Snooze -Id 'SnoozeTime' -Content "Rapelle-moi encore"
        $dismissButton = New-BTButton -Dismiss -Content "Ok"
        
        # Create action with snooze functionality
        $action = New-BTAction -Buttons $snoozeButton,$dismissButton -Inputs $selectionBox
    }
    else {
        # Create dismiss button only
        $dismissButton = New-BTButton -Dismiss -Content "Ok"
        
        # Create action without snooze functionality
        $action = New-BTAction -Buttons $dismissButton
    }
    
    # Set scenario based on ReminderMode parameter
    $scenario = if ($ReminderMode) { "Reminder" } else { "Default" }
    
    # Create the content
    $content = New-BTContent -Visual $visual -Actions $action -Duration Long -Scenario $scenario

    # A little bit hardcore but...
    New-BTAppId -AppId $AppID
    
    # Submit the notification
    Submit-BTNotification -Content $content -AppID $AppID
}

# Call the function with provided parameters
Send-BTToast -ImagePath $ImagePath -Title $Title -Message $Message -EnableSnooze $EnableSnooze -ReminderMode $ReminderMode -AppID $AppID