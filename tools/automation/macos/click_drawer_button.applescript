-- Clicks the Flutter drawer (hamburger) button in a running macOS app via Accessibility
-- Usage: osascript tools/automation/macos/click_drawer_button.applescript [process_name]
-- Defaults to "flutter_base_04" if no argument is supplied

on run argv
  set targetProc to "flutter_base_04"
  if (count of argv) > 0 then set targetProc to item 1 of argv

  tell application "System Events"
    if not (exists process targetProc) then error "Process '" & targetProc & "' not running"
    tell process targetProc
      set frontmost to true
      delay 0.2
      -- 1) Try by AXDescription (Semantics label)
      try
        click (first UI element of window 1 whose value of attribute "AXDescription" is "drawer_open")
        return "clicked by AXDescription=drawer_open"
      end try
      -- 2) Try by Name (tooltip/content)
      try
        click (first UI element of window 1 whose name is "Open navigation menu")
        return "clicked by name=Open navigation menu"
      end try
      -- 3) Fallback: first AXButton inside first AXGroup
      try
        set theGroup to first UI element of window 1 whose role is "AXGroup"
        click button 1 of theGroup
        return "clicked first button in AXGroup"
      end try
      error "Drawer button not found via AX"
    end tell
  end tell
end run
