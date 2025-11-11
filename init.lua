--- Music control spoon for Hammerspoon.
-- Provides utilities for controlling music playback using hs.itunes.
--
-- @author dmg
-- @module hs_music

local obj = {}
obj.__index = obj

--- Metadata about the spoon.
obj.name = "hs_music"
obj.version = "0.2"
obj.author = "Daniel M German <dmg@turingmachine.org>"
obj.homepage = "https://github.com/Hammerspoon/Spoons"
obj.license = "MIT"

--- Configuration attributes.
-- @field alertDuration (number): Duration in seconds for track info alerts (default: 5)
obj.alertDuration = 5

-- @field trackFormat (string): Format string for displaying track info
-- Available placeholders: {name}, {artist}, {album}
-- Default: "{name} - {artist} [{album}]"
obj.trackFormat = "Track: {name}\nArtist: {artist}\nAlbum: {album}"

-- @field maxAlbumSkipAttempts (number): Maximum number of track skips when trying to reach next album (default: 20)
obj.maxAlbumSkipAttempts = 20

-- @field albumSkipDelay (number): Delay in seconds between track skips during album navigation (default: 0.3)
obj.albumSkipDelay = 0.3

--- Helper to ensure Music is running, show alert if not.
--
-- @return (boolean): true if Music is running, false otherwise (alert shown on failure)
function obj:_ensureMusicRunning()
  if not hs.itunes.isRunning() then
    hs.alert.show("Music app is not running")
    return false
  end
  return true
end

--- Helper to format track info using the configured trackFormat attribute.
--
-- @param name (string): Track name
-- @param artist (string): Artist name
-- @param album (string): Album name
-- @return (string): Formatted track info string
function obj:_formatTrackInfo(name, artist, album)
  if not name then
    return nil
  end

  name = name or "Unknown"
  artist = artist or "Unknown"
  album = album or "Unknown"

  local formatted = self.trackFormat
    :gsub("{name}", name)
    :gsub("{artist}", artist)
    :gsub("{album}", album)

  return formatted
end

--- Plays or pauses the current track.
--
-- @return (boolean): true if successful, false otherwise
function obj:togglePlayPause()
  if not self:_ensureMusicRunning() then
    return false
  end
  hs.itunes.playpause()
  return true
end

--- Plays the next track.
--
-- @return (boolean): true if successful, false otherwise
function obj:nextTrack()
  if not self:_ensureMusicRunning() then
    return false
  end
  hs.itunes.next()
  return true
end

--- Plays the previous track.
--
-- @return (boolean): true if successful, false otherwise
function obj:previousTrack()
  if not self:_ensureMusicRunning() then
    return false
  end
  hs.itunes.previous()
  return true
end

--- Gets the currently playing track information (name, artist, album).
-- Formatted according to the trackFormat attribute.
--
-- @return (string or nil): Formatted track info if playing, nil otherwise
function obj:getCurrentTrack()
  if not self:_ensureMusicRunning() then
    return nil
  end

  local name = hs.itunes.getCurrentTrack()
  if not name then
    return nil
  end

  local artist = hs.itunes.getCurrentArtist()
  local album = hs.itunes.getCurrentAlbum()

  return self:_formatTrackInfo(name, artist, album)
end

--- Gets the current artist name.
--
-- @return (string or nil): Artist name, or nil if unavailable
function obj:getCurrentArtist()
  if not self:_ensureMusicRunning() then
    return nil
  end

  return hs.itunes.getCurrentArtist()
end

--- Shows current track information in an alert.
--
-- @return (boolean): true if successful, false otherwise
--
-- @details
-- - Displays track info formatted according to trackFormat attribute
-- - Uses the `alertDuration` attribute (default: 5 seconds)
-- - Customize format: `music.trackFormat = "{artist} - {name}"`
-- - Customize duration: `music.alertDuration = 3`
function obj:showCurrentTrack()
  if not self:_ensureMusicRunning() then
    return false
  end

  local name = hs.itunes.getCurrentTrack()
  if not name then
    hs.alert.show("No track currently playing", self.alertDuration)
    return false
  end

  local artist = hs.itunes.getCurrentArtist()
  local album = hs.itunes.getCurrentAlbum()

  local trackInfo = self:_formatTrackInfo(name, artist, album)
  hs.alert.show(trackInfo, self.alertDuration)
  return true
end

--- Sets the volume level of the Music app.
-- Clamps the input to 0–100 range.
--
-- @param level (number): Volume level as a percentage (0-100)
--
-- @return (number or nil): The new volume level if successful, nil otherwise
function obj:setVolume(level)
  if not self:_ensureMusicRunning() then
    return nil
  end

  -- clamp to 0–100 range
  if level < 0 then level = 0 end
  if level > 100 then level = 100 end

  hs.itunes.setVolume(level)
  hs.alert(string.format("Music volume set to %d%%", level))
  return level
end

--- Gets the current volume level of the Music app.
--
-- @return (number or nil): Volume as a percentage (0-100), or nil if unavailable
function obj:getVolume()
  if not self:_ensureMusicRunning() then
    return nil
  end

  local volume = hs.itunes.getVolume()
  if volume then
    hs.alert(string.format("Music volume: %d%%", volume))
    return volume
  end

  hs.alert("Could not read Music volume")
  return nil
end

--- Adjusts the volume by a given percentage amount.
-- Gets the current volume, adds the delta, and clamps to 0–100 range.
--
-- @param delta (number): The percentage amount to adjust volume by (can be negative)
--
-- @return (number or nil): The new volume level if successful, nil otherwise
function obj:adjustVolume(delta)
  if not self:_ensureMusicRunning() then
    return nil
  end

  local currentVolume = hs.itunes.getVolume()
  if not currentVolume then
    hs.alert("Could not read Music volume")
    return nil
  end

  local newVolume = currentVolume + delta
  return self:setVolume(newVolume)
end

--- Helper to skip to a new album in the specified direction asynchronously.
-- Calls onAlbumFound when target album is reached.
-- Respects the maxAlbumSkipAttempts attribute.
--
-- @param direction (string): "next" or "previous"
-- @param onAlbumFound (function): Callback when new album is found
-- @return (boolean): true if skip initiated, false if Music not running
function obj:_skipToNewAlbum(direction, onAlbumFound)
  if not self:_ensureMusicRunning() then
    return false
  end

  local startAlbum = hs.itunes.getCurrentAlbum()
  local attempts = 0
  local skipFunc = (direction == "next") and hs.itunes.next or hs.itunes.previous
  local directionLabel = (direction == "next") and "next album" or "previous album"

  local function checkAlbumChange()
    attempts = attempts + 1
    local currentAlbum = hs.itunes.getCurrentAlbum()

    if currentAlbum ~= startAlbum then
      onAlbumFound(currentAlbum)
      return
    end

    if attempts >= self.maxAlbumSkipAttempts then
      hs.alert.show("Skipped " .. attempts .. " tracks, no " .. directionLabel .. " found")
      return
    end

    skipFunc()
    hs.timer.doAfter(self.albumSkipDelay, checkAlbumChange)
  end

  skipFunc()
  hs.timer.doAfter(self.albumSkipDelay, checkAlbumChange)
  return true
end

--- Helper to seek to the first track of the current album by skipping backward.
-- Continues backward until we'd leave the album, then goes forward once.
-- Uses maxAlbumSkipAttempts and albumSkipDelay attributes.
--
-- @param targetAlbum (string): The album name to stay within
function obj:_seekToFirstTrackCurrentAlbum(targetAlbum)
  local seekAttempts = 0
  local function seekTrack()
    seekAttempts = seekAttempts + 1
    hs.itunes.previous()
    local currentAlbum = hs.itunes.getCurrentAlbum()

    if currentAlbum ~= targetAlbum then
      -- Hit the boundary, go forward one step to land on first track
      hs.itunes.next()
      hs.alert.show("Skipped to album: " .. (hs.itunes.getCurrentAlbum() or "Unknown"))
      return
    end

    if seekAttempts >= self.maxAlbumSkipAttempts then
      -- Reached attempt limit while still in the same album
      hs.alert.show("Reached attempt limit while seeking within album")
      return
    end

    hs.timer.doAfter(self.albumSkipDelay, seekTrack)
  end

  hs.timer.doAfter(self.albumSkipDelay, seekTrack)
end

--- Skips to the next album asynchronously.
-- Uses callbacks to avoid blocking Hammerspoon. Shows alert when done or if no next album exists.
-- Respects the maxAlbumSkipAttempts attribute.
--
-- @return (boolean): true if skip initiated, false if Music not running
function obj:nextAlbum()
  return self:_skipToNewAlbum("next", function(album)
    hs.alert.show("Skipped to album: " .. (album or "Unknown"))
  end)
end

--- Skips to the previous album and positions at the first track asynchronously.
-- Uses callbacks to avoid blocking Hammerspoon. Shows alert when done or if no previous album exists.
-- Respects the maxAlbumSkipAttempts attribute.
--
-- @return (boolean): true if skip initiated, false if Music not running
function obj:previousAlbum()
  return self:_skipToNewAlbum("previous", function(album)
    self:_seekToFirstTrackCurrentAlbum(album)
  end)
end

--- Initializes the spoon with hotkey bindings.
--
-- @param hotkeys (table): Hotkey configuration table with keys for modifiers
-- @details
-- - hotkeys.togglePlayPause: Hotkey for play/pause
-- - hotkeys.nextTrack: Hotkey for next track
-- - hotkeys.previousTrack: Hotkey for previous track
-- - hotkeys.showTrack: Hotkey to show current track
-- - hotkeys.nextAlbum: Hotkey to skip to next album
-- - hotkeys.previousAlbum: Hotkey to skip to previous album
--
-- @return (hs_music): Returns self for chaining
function obj:init(hotkeys)
  hotkeys = hotkeys or {}

  local hotkeyMaps = {
    togglePlayPause = self.togglePlayPause,
    nextTrack = self.nextTrack,
    previousTrack = self.previousTrack,
    showTrack = self.showCurrentTrack,
    nextAlbum = self.nextAlbum,
    previousAlbum = self.previousAlbum
  }

  for key, func in pairs(hotkeyMaps) do
    if hotkeys[key] then
      hs.hotkey.bind(hotkeys[key].mods, hotkeys[key].key, function()
        func(self)
      end)
    end
  end

  return self
end

return obj
