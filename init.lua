--- Music control spoon for Hammerspoon.
-- Provides utilities for controlling Apple Music playback using hs.itunes
-- (transport, volume, album navigation), plus an album-library feature
-- that searches Music from a curated list and starts playback.
--
-- The album-library API is built around four entry points:
--   * `playAlbum(band, album)` - search and play a specific album
--   * `playRandomAlbum([path])` - pick a random entry from the list and play it
--   * `chooseAlbum([path])` - show an hs.chooser of the list to pick interactively
--   * `addCurrentAlbum([path])` - append the currently playing album to the list
--
-- All three drive Music's UI: focus the search field (⌘F), paste
-- "Band, Album", submit, walk the accessibility tree to find the first
-- card in the "Albums" results section, then click the play overlay that
-- appears on hover.
--
-- The list file (`albumListPath`, default `~/.hammerspoon/albums.txt`) has
-- one entry per line in the form `Band|Album`. Blank lines, lines whose
-- first character is `#`, and lines without a `|` are ignored.
--
-- @author dmg
-- @module hs_music

local obj = {}
obj.__index = obj

--- Metadata about the spoon.
obj.name = "hs_music"
obj.version = "0.3"
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

-- @field albumListPath (string): Path to the file used by playRandomAlbum. Each line is "Title|Band".
obj.albumListPath = os.getenv("HOME") .. "/.hammerspoon/albums.txt"

-- @field activateDelay (number): Delay in seconds after activating Music before driving the search field.
obj.activateDelay = 0.4

-- @field searchOpenDelay (number): Delay in seconds after sending ⌘F before pasting the query.
obj.searchOpenDelay = 0.2

-- @field pasteSubmitDelay (number): Delay in seconds between paste and Return.
obj.pasteSubmitDelay = 0.1

-- @field clipboardRestoreDelay (number): Delay in seconds before restoring the saved clipboard.
obj.clipboardRestoreDelay = 0.4

-- @field resultsRenderDelay (number): Delay in seconds after submit before the first scan attempt.
obj.resultsRenderDelay = 1.0

-- @field albumClickRetries (number): Max number of scan attempts before giving up.
obj.albumClickRetries = 12

-- @field albumClickRetryInterval (number): Delay in seconds between scan attempts.
obj.albumClickRetryInterval = 0.4

-- @field axWalkMaxDepth (number): Max depth for AX walks over the Music window.
obj.axWalkMaxDepth = 16

-- @field hoverPlayDelay (number): Delay after mouse hover for Music's play overlay to render.
obj.hoverPlayDelay = 0.4

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
  if obj:isMusicPlaying() then
    music:togglePlayPause()
    hs.itunes.previous()
    music:togglePlayPause()
  else
    hs.itunes.previous()
  end
  return true
end

--- Checks if music is currently playing.
--
-- @return (boolean): true if music is playing, false otherwise
function obj:isMusicPlaying()
  local ok, result = hs.osascript.applescript([[
    if application "Music" is running then
      tell application "Music" to get player state
    else
      return "not running"
    end if
  ]])

  if not ok then
    hs.alert.show("Warning: Could not check music status")
    return false
  end
  print("Status music is playing: ", result)
  return result == "playing"
end

--- Plays the current track.
-- 
-- @return (boolean): true if successful, false otherwise
function obj:play()
  if not self:_ensureMusicRunning() then
    return false
  end

  local ok, result = hs.osascript.applescript([[
    tell application "Music" to play
    tell application "Music" to get player state
  ]])

  if not ok then
    hs.alert.show("Warning: Could not play music")
    return false
  end

  if result ~= "kPSP" then
    hs.alert.show("Warning: Music play command issued but status is: " .. result)
  end

  return true
end

--- Stops playing music.
--- This is much worse than toggling play. The current song is no longer
--  active and playing will restart in the next song
-- 
-- @return (boolean): true if successful, false otherwise
function obj:stop()
  if not self:_ensureMusicRunning() then
    return false
  end

  local ok, result = hs.osascript.applescript([[
    tell application "Music" to stop
    tell application "Music" to get player state
  ]])

  if not ok then
    hs.alert.show("Warning: Could not stop music")
    return false
  end

  if result ~= "stopped" then
    hs.alert.show("Warning: Music stop command issued but status is: " .. result)
  end

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

--- Reads a file of album entries, returning only valid "Band|Album" lines.
-- Skips blanks, lines whose first character is "#", and lines without a "|".
-- Returns nil silently if the file cannot be opened; callers should decide
-- whether that condition deserves an alert.
--
-- @param path (string): Absolute path to the album list file
-- @return (table or nil): Array of trimmed valid lines, or nil if the file cannot be opened
function obj:_readAlbumLines(path)
  local f = io.open(path, "r")
  if not f then return nil end

  local lines = {}
  for raw in f:lines() do
    if raw:sub(1, 1) ~= "#" then
      local line = raw:match("^%s*(.-)%s*$")
      if line ~= "" and line:find("|", 1, true) then
        table.insert(lines, line)
      end
    end
  end
  f:close()
  return lines
end

--- Parses a "Band|Album" line into its parts.
-- Callers should pass only validated lines (see _readAlbumLines).
--
-- @param line (string): A single album entry
-- @return (string, string): band, album
function obj:_parseAlbumLine(line)
  return line:match("^(.-)%s*|%s*(.+)$")
end

--- Drives Music's search field by pasting from the clipboard.
-- Sends ⌘F to focus the search field (works from any view), pastes the query
-- via ⌘V, presses Return, and restores the prior clipboard contents.
--
-- @param query (string): The text to put in the search field
function obj:_driveSearchField(query)
  hs.eventtap.keyStroke({"cmd"}, "f", 0)

  hs.timer.doAfter(self.searchOpenDelay, function()
    local saved = hs.pasteboard.getContents()
    hs.pasteboard.setContents(query)
    hs.eventtap.keyStroke({"cmd"}, "v", 0)

    hs.timer.doAfter(self.pasteSubmitDelay, function()
      hs.eventtap.keyStroke({}, "return", 0)
      hs.timer.doAfter(self.clipboardRestoreDelay, function()
        if saved then
          hs.pasteboard.setContents(saved)
        end
      end)
    end)
  end)
end

--- Gets Music's main standard window element.
--
-- @param app (hs.application): The Music application
-- @return (axuielement or nil): The main window, or nil if not found
function obj:_getMainWindow(app)
  local ax = hs.axuielement.applicationElement(app)
  if not ax then return nil end
  for _, w in ipairs(ax:attributeValue("AXWindows") or {}) do
    if w:attributeValue("AXSubrole") == "AXStandardWindow" then
      return w
    end
  end
  return nil
end

--- Finds the "Albums" section list under root.
-- Music renders it as AXList with subrole AXSectionList and description "Albums".
--
-- @param root (axuielement): The subtree to walk
-- @return (axuielement or nil): The Albums section AXList
function obj:_findAlbumsSection(root)
  local found
  local function walk(e, depth)
    if found or depth > self.axWalkMaxDepth then return end
    if (e:attributeValue("AXDescription") or "") == "Sidebar" then return end
    if e:attributeValue("AXRole") == "AXList"
      and e:attributeValue("AXSubrole") == "AXSectionList"
      and e:attributeValue("AXDescription") == "Albums" then
      found = e
      return
    end
    for _, c in ipairs(e:attributeValue("AXChildren") or {}) do
      walk(c, depth + 1)
    end
  end
  walk(root, 0)
  return found
end

--- Finds the first real album card inside the Albums section, and its title
-- button. Album cards are AXGroups whose AXDescription is the album name;
-- AXGroups without a description are section header/wrappers and are skipped.
-- The first AXButton in the group is the album-title button (second is artist).
--
-- @param section (axuielement): The Albums AXSectionList
-- @return (axuielement or nil, axuielement or nil): card group, title button
function obj:_firstAlbumCard(section)
  for _, child in ipairs(section:attributeValue("AXChildren") or {}) do
    if child:attributeValue("AXRole") == "AXGroup"
      and (child:attributeValue("AXDescription") or "") ~= "" then
      local titleButton
      for _, gc in ipairs(child:attributeValue("AXChildren") or {}) do
        if gc:attributeValue("AXRole") == "AXButton" then
          titleButton = gc
          break
        end
      end
      return child, titleButton
    end
  end
  return nil, nil
end

--- Locates the first card in the Albums section, hovers over its artwork to
-- reveal Music's play-overlay button, then clicks it after a short delay.
--
-- @param app (hs.application): The Music application
-- @return (boolean): true if a click was scheduled, false otherwise
function obj:_clickFirstAlbumResult(app)
  local main = self:_getMainWindow(app)
  if not main then
    print("[hs_music] could not get Music main window")
    return false
  end

  local section = self:_findAlbumsSection(main)
  if not section then
    print("[hs_music] Albums section not found")
    return false
  end

  local card = self:_firstAlbumCard(section)
  if not card then
    print("[hs_music] Albums section has no card groups")
    return false
  end

  -- The play-overlay shows over the artwork (upper portion of the card).
  -- Aim there rather than the geometric center, which sits over title text.
  local frame = card:attributeValue("AXFrame")
  if not frame or not frame.w or frame.w <= 0 then
    print("[hs_music] album card has no frame")
    return false
  end
  local point = { x = frame.x + frame.w / 2, y = frame.y + frame.w / 2 }

  local albumName = card:attributeValue("AXDescription") or "?"
  print(string.format("[hs_music] hover @ (%.0f, %.0f) for album %q",
    point.x, point.y, albumName))
  hs.mouse.absolutePosition(point)
  hs.timer.doAfter(self.hoverPlayDelay, function()
    hs.eventtap.leftClick(point)
  end)
  return true
end

--- Retries _clickFirstAlbumResult until results render or attempts are exhausted.
--
-- @param app (hs.application): The Music application
-- @param attemptsLeft (number): Remaining attempts
function obj:_clickFirstAlbumResultWithRetry(app, attemptsLeft)
  if self:_clickFirstAlbumResult(app) then return end
  if attemptsLeft <= 1 then
    hs.alert.show("Music: no album found in results")
    return
  end
  hs.timer.doAfter(self.albumClickRetryInterval, function()
    self:_clickFirstAlbumResultWithRetry(app, attemptsLeft - 1)
  end)
end

--- Searches Apple Music for a specific album and starts playback.
-- Music is launched if necessary and brought to the foreground. The query
-- "Band, Album" is pasted into Music's search field (the clipboard is
-- saved and restored). After the results render, the spoon locates the
-- first card in the "Albums" section by walking Music's accessibility
-- tree and triggers playback by hovering the artwork (so Music renders
-- its play overlay) then clicking it.
--
-- @param band (string): The band/artist name (required)
-- @param album (string): The album title (required)
-- @return (boolean): true if a search was issued, false on missing args or Music launch failure
function obj:playAlbum(band, album)
  if not band or band == "" or not album or album == "" then
    hs.alert.show("playAlbum: band and album are required")
    return false
  end

  local app = hs.application.get("com.apple.Music") or hs.application.get("Music")
  if not app then
    hs.application.launchOrFocus("Music")
    app = hs.application.get("com.apple.Music") or hs.application.get("Music")
  end
  if not app then
    hs.alert.show("Could not launch Music")
    return false
  end

  app:activate()
  hs.alert.show("Searching: " .. band .. " — " .. album, 3)

  hs.timer.doAfter(self.activateDelay, function()
    self:_driveSearchField(band .. ", " .. album)
    local firstScanDelay = self.searchOpenDelay + self.pasteSubmitDelay + self.resultsRenderDelay
    hs.timer.doAfter(firstScanDelay, function()
      self:_clickFirstAlbumResultWithRetry(app, self.albumClickRetries)
    end)
  end)
  return true
end

--- Reads the album list file and returns sorted "Band|Album" entries as choices.
-- Sort is alphabetical by band (case-insensitive), then album.
--
-- @param filePath (string): Path to the album list file
-- @return (table or nil): Array of choice tables {text, band, album}, or nil on error
function obj:_buildAlbumChoices(filePath)
  local lines = self:_readAlbumLines(filePath)
  if not lines then return nil end

  local choices = {}
  for _, line in ipairs(lines) do
    local band, album = self:_parseAlbumLine(line)
    if band and album then
      table.insert(choices, {
        text = band .. " — " .. album,
        band = band,
        album = album,
      })
    end
  end

  table.sort(choices, function(a, b)
    local ba, bb = a.band:lower(), b.band:lower()
    if ba ~= bb then return ba < bb end
    return a.album:lower() < b.album:lower()
  end)
  return choices
end

--- Shows an hs.chooser of all albums in the list and plays the selected one.
--
-- @param filePath (string, optional): Path to the album list. Defaults to self.albumListPath.
-- @return (boolean): true if the chooser was shown, false on file errors
function obj:chooseAlbum(filePath)
  filePath = filePath or self.albumListPath
  if not filePath then
    hs.alert.show("No album list file configured (set music.albumListPath)")
    return false
  end

  local choices = self:_buildAlbumChoices(filePath)
  if not choices or #choices == 0 then
    hs.alert.show("No valid album lines in: " .. filePath)
    return false
  end

  local chooser = hs.chooser.new(function(choice)
    if choice then
      self:playAlbum(choice.band, choice.album)
    end
  end)
  chooser:choices(choices)
  chooser:show()
  return true
end

--- Appends the currently playing album to the album list file.
-- Reads the current band/album via hs.itunes, skips if already present
-- (case-insensitive band+album match), otherwise appends "Band|Album".
-- Creates the file if it does not exist and ensures the file ends with a
-- newline before the new entry.
--
-- @param filePath (string, optional): Path to the album list. Defaults to self.albumListPath.
-- @return (boolean): true if a new entry was written, false otherwise
function obj:addCurrentAlbum(filePath)
  filePath = filePath or self.albumListPath
  if not filePath then
    hs.alert.show("No album list file configured (set music.albumListPath)")
    return false
  end
  if not self:_ensureMusicRunning() then return false end

  local band = hs.itunes.getCurrentArtist()
  local album = hs.itunes.getCurrentAlbum()
  if not band or band == "" or not album or album == "" then
    hs.alert.show("No track is currently playing")
    return false
  end

  local lband, lalbum = band:lower(), album:lower()
  for _, line in ipairs(self:_readAlbumLines(filePath) or {}) do
    local b, a = self:_parseAlbumLine(line)
    if b and a and b:lower() == lband and a:lower() == lalbum then
      hs.alert.show("Already in list: " .. band .. " — " .. album)
      return false
    end
  end

  local existing = ""
  local fr = io.open(filePath, "r")
  if fr then
    existing = fr:read("*a") or ""
    fr:close()
  end
  if #existing > 0 and existing:sub(-1) ~= "\n" then
    existing = existing .. "\n"
  end

  local fw = io.open(filePath, "w")
  if not fw then
    hs.alert.show("Could not write " .. filePath)
    return false
  end
  fw:write(existing .. band .. "|" .. album .. "\n")
  fw:close()
  hs.alert.show("Added: " .. band .. " — " .. album)
  return true
end

--- Picks a random album from a file and plays it via playAlbum.
--
-- File format (`albumListPath`, default `~/.hammerspoon/albums.txt`):
--   * One entry per line, `Band|Album`
--   * Lines whose first character is `#` are ignored (comments)
--   * Blank lines and lines without `|` are ignored
--
-- @param filePath (string, optional): Path to the album list. Defaults to self.albumListPath.
-- @return (boolean): true if a search was issued, false on configuration/file errors
function obj:playRandomAlbum(filePath)
  filePath = filePath or self.albumListPath
  if not filePath then
    hs.alert.show("No album list file configured (set music.albumListPath)")
    return false
  end

  local lines = self:_readAlbumLines(filePath)
  if not lines or #lines == 0 then
    hs.alert.show("No valid album lines in: " .. filePath)
    return false
  end

  local band, album = self:_parseAlbumLine(lines[math.random(#lines)])
  return self:playAlbum(band, album)
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
-- - hotkeys.randomAlbum: Hotkey to search a random album from `albumListPath`
--
-- @return (hs_music): Returns self for chaining
function obj:init(hotkeys)
  hotkeys = hotkeys or {}

  math.randomseed(os.time())

  local hotkeyMaps = {
    togglePlayPause = self.togglePlayPause,
    nextTrack = self.nextTrack,
    previousTrack = self.previousTrack,
    showTrack = self.showCurrentTrack,
    nextAlbum = self.nextAlbum,
    previousAlbum = self.previousAlbum,
    randomAlbum = self.playRandomAlbum
  }

  for key, func in pairs(hotkeyMaps) do
    if hotkeys[key] then
      local descriptions = {
        togglePlayPause = "Toggle music play/pause [Music]",
        nextTrack = "Next music track [Music]",
        previousTrack = "Previous music track [Music]",
        showTrack = "Show current track [Music]",
        nextAlbum = "Next album [Music]",
        previousAlbum = "Previous album [Music]",
        randomAlbum = "Search random album in Music [Music]"
      }
      hs.hotkey.bind(hotkeys[key].mods, hotkeys[key].key, descriptions[key] or ("Music control [Music]"), function()
        func(self)
      end)
    end
  end

  return self
end

return obj
