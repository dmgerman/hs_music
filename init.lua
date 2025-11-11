--- Music control spoon for Hammerspoon.
-- Provides utilities for controlling music playback across various music applications.
--
-- @author dmg
-- @module hs_music

local obj = {}
obj.__index = obj

--- Metadata about the spoon.
obj.name = "hs_music"
obj.version = "0.1"
obj.author = "Daniel M German <dmg@turingmachine.org>"
obj.homepage = "https://github.com/Hammerspoon/Spoons"
obj.license = "MIT"

--- Configuration attributes.
-- @field alertDuration (number): Duration in seconds for track info alerts (default: 5)
obj.alertDuration = 5

--- Logger for debugging.
local logger = hs.logger.new(obj.name)

--- Sends a command to the currently playing music application.
--
-- @param command (string): The command to send (e.g., "playpause", "next", "previous")
-- @return (boolean): true if command was sent, false otherwise
function obj:sendMusicAppCommand(command)
  if not command or command == "" then
    logger:e("Invalid command: " .. tostring(command))
    return false
  end

  local success = pcall(function()
    hs.osascript.applescript(string.format(
      'tell application "Music" to %s',
      command
    ))
  end)

  if not success then
    logger:w("Failed to send command: " .. command)
  end

  return success
end

--- Sets the volume level of the Music app via accessibility API.
-- Recursively collects all sliders and adjusts the second one (volume slider).
-- Clamps the input to 0–100 range.
--
-- @param level (number): Volume level as a percentage (0-100)
--
-- @details
-- - Requires Accessibility permissions to be enabled for Music app
-- - The second slider in the UI hierarchy is assumed to be the volume control
-- - Shows alerts for success/failure and if app is not running
--
-- @return (boolean): Implicitly returns nil
function obj:changeMusicAppVolume(level)
    -- clamp to 0–100 range
    if level < 0 then level = 0 end
    if level > 100 then level = 100 end

    local app = hs.application.get("Music")
    if not app then
        hs.alert("Music app not running")
        return
    end

    local axApp = hs.axuielement.applicationElement(app)
    if not axApp then
        hs.alert("Accessibility not available for Music")
        return
    end

    -- recursively collect all sliders
    local sliders = {}
    local function collectSliders(element)
        if not element or not element:attributeValue("AXChildren") then return end
        for _, child in ipairs(element:attributeValue("AXChildren")) do
            if child:attributeValue("AXRole") == "AXSlider" then
                table.insert(sliders, child)
            end
            collectSliders(child)
        end
    end

    collectSliders(axApp)

    if #sliders < 2 then
        hs.alert(string.format("Found %d slider(s), but expected at least 2", #sliders))
        return
    end

    -- The *second* slider is the volume
    local volumeSlider = sliders[2]
    local normalized = level / 100.0

    -- set the new value
    local ok = volumeSlider:setAttributeValue("AXValue", normalized)
    if ok then
        hs.alert(string.format("Music volume set to %d%%", level))
    else
        hs.alert("Failed to set Music volume")
    end
end



--- Gets the current volume level of the Music app via accessibility API.
-- Recursively collects all sliders and reads the value of the second one (volume slider).
-- Converts the normalized value (0.0–1.0) to a percentage (0–100).
--
-- @return (number or nil): Volume as a percentage (0-100), or nil if unavailable
--
-- @details
-- - Requires Accessibility permissions to be enabled for Music app
-- - The second slider in the UI hierarchy is assumed to be the volume control
-- - Shows alerts for errors and current volume when successfully read
--
-- @note
-- Returns nil if Music app is not running, accessibility is unavailable, or read fails
function obj:getMusicAppVolume()
    local app = hs.application.get("Music")
    if not app then
        hs.alert("Music app not running")
        return nil
    end

    local axApp = hs.axuielement.applicationElement(app)
    if not axApp then
        hs.alert("Accessibility not available for Music")
        return nil
    end

    -- collect all sliders
    local sliders = {}
    local function collectSliders(element)
        if not element or not element:attributeValue("AXChildren") then return end
        for _, child in ipairs(element:attributeValue("AXChildren")) do
            if child:attributeValue("AXRole") == "AXSlider" then
                table.insert(sliders, child)
            end
            collectSliders(child)
        end
    end

    collectSliders(axApp)

    if #sliders < 2 then
        hs.alert(string.format("Found %d slider(s), expected at least 2", #sliders))
        return nil
    end

    -- The second slider is the volume control
    local volumeSlider = sliders[2]
    local value = volumeSlider:attributeValue("AXValue")

    if value then
        local percent = math.floor(value * 100)
        hs.alert(string.format("Music volume: %d%%", percent))
        return percent
    else
        hs.alert("Could not read Music volume")
        return nil
    end
end



--- Plays or pauses the current track.
--
-- @return (boolean): true if successful, false otherwise
function obj:toggleMusicAppPlayPause()
  return self:sendMusicAppCommand("playpause")
end

--- Plays the next track.
--
-- @return (boolean): true if successful, false otherwise
function obj:nextMusicAppTrack()
  return self:sendMusicAppCommand("next track")
end

--- Plays the previous track.
--
-- @return (boolean): true if successful, false otherwise
function obj:previousMusicAppTrack()
  return self:sendMusicAppCommand("previous track")
end

--- Gets the currently playing track information (name, artist, album).
-- Checks if Music app is running and currently playing before retrieving info.
--
-- @return (string or nil): Formatted string "TrackName - Artist [Album]" if playing, nil otherwise
function obj:getMusicAppCurrentTrack()
  local script = [[
    tell application "Music"
      if it is running and player state is playing then
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        return trackName & " - " & trackArtist & " [" & trackAlbum & "]"
      else
        return "Not playing"
      end if
    end tell
  ]]

  local ok, result = hs.osascript.applescript(script)
  if ok and result and result ~= "Not playing" then
    return result
  end

  return nil
end

--- Gets the current artist name.
--
-- @return (string or nil): Artist name, or nil if unavailable
function obj:getMusicAppCurrentArtist()
  local success, result = pcall(function()
    return hs.osascript.applescript(
      'tell application "Music" to artist of current track'
    )
  end)

  if success and result and type(result) == "string" then
    return result
  end

  return nil
end

--- Shows current track information in an alert.
--
-- @return (boolean): true if successful, false otherwise
--
-- @details
-- - Displays formatted track info: "TrackName - Artist [Album]"
-- - Uses the `alertDuration` attribute (default: 5 seconds)
-- - Customize duration by setting: `music.alertDuration = 3`
function obj:showMusicAppCurrentTrack()
  local track = self:getMusicAppCurrentTrack()

  if not track then
    hs.alert.show("No track currently playing", self.alertDuration)
    return false
  end

  hs.alert.show(track, self.alertDuration)
  return true
end

--- Initializes the spoon with hotkey bindings.
--
-- @param hotkeys (table): Hotkey configuration table with keys for modifiers
-- @details
-- - hotkeys.togglePlayPause: Hotkey for play/pause
-- - hotkeys.nextTrack: Hotkey for next track
-- - hotkeys.previousTrack: Hotkey for previous track
-- - hotkeys.showTrack: Hotkey to show current track
--
-- @return (hs_music): Returns self for chaining
function obj:init(hotkeys)
  hotkeys = hotkeys or {}

  if hotkeys.togglePlayPause then
    hs.hotkey.bind(hotkeys.togglePlayPause.mods, hotkeys.togglePlayPause.key, function()
      self:toggleMusicAppPlayPause()
    end)
  end

  if hotkeys.nextTrack then
    hs.hotkey.bind(hotkeys.nextTrack.mods, hotkeys.nextTrack.key, function()
      self:nextMusicAppTrack()
    end)
  end

  if hotkeys.previousTrack then
    hs.hotkey.bind(hotkeys.previousTrack.mods, hotkeys.previousTrack.key, function()
      self:previousMusicAppTrack()
    end)
  end

  if hotkeys.showTrack then
    hs.hotkey.bind(hotkeys.showTrack.mods, hotkeys.showTrack.key, function()
      self:showMusicAppCurrentTrack()
    end)
  end

  return self
end

return obj
