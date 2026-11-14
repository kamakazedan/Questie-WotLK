# Questie for WoW 3.3.5a (Wrath of the Lich King)

A port of [Questie](https://github.com/Questie/Questie) v12.9.0 and its database addon QuestieDB v1.1.1
to the 3.3.5a client (build 12340, interface 30300), the client used by AzerothCore and TrinityCore
servers. QuestieDB is trimmed to the Wrath of the Lich King data.

## Install

1. Download this repository (**Code → Download ZIP**) and unpack it.
2. Copy **both** folders, `Questie` and `QuestieDB`, into `World of Warcraft\Interface\AddOns\`.
   Questie gets all of its quest, NPC, item and object data from QuestieDB and does not work without it.
   The folder names must stay exactly `Questie` and `QuestieDB` (the ZIP puts them inside
   `Questie-WotLK-main\`; copy the two folders out of it).
3. If you used another Questie build on this client before, delete its folders first. Should you get Lua
   errors at login after that, delete its old settings too:
   `WTF\Account\<account>\SavedVariables\Questie.lua` and
   `WTF\Account\<account>\<realm>\<character>\SavedVariables\Questie.lua`.

## Using it

- `/questie` opens the options window. **Interface → AddOns → Questie** has a button that opens it as well.
- `/questie help` lists the other commands (`/questie journey`, `/questie tracker`, `/questie minimap`, ...).
- Questie puts its button on the minimap and in the top-right corner of the world map.

Working on 3.3.5a:

- Available quests, quest givers and turn-ins on the world map and minimap
- Quest objective icons (creatures, items, objects) with tooltips, and the lines along NPC patrol paths
  on the world map
- Questie's quest tracker, which replaces the default watch frame
- Quest progress in creature and item tooltips
- Questie Journey (quest history and database search)
- Auto-accept and auto-turn-in options
- Quest icons on nameplates and on the target frame
- Sharing quest progress with party members who run this version
- Holiday event quests, read from the in-game calendar

## Differences from Questie on newer clients

The 3.3.5a client lacks many of the functions newer clients give addons. Questie works around most of
them, but some things work differently:

- **Collapsed quest log headers:** if a quest under a collapsed zone header in the quest log stops
  updating, expand that header.
- **Nameplate icons are matched by name.** Nameplates on this client do not say which NPC they belong
  to, only its name, so another NPC with the same name as a quest target gets the icon too. The icon on
  the target frame is exact.
- **Turned-in quests are recognized by title and NPC**, as the client does not report quest IDs when a
  quest is turned in. Two quests with the same title from the same NPC could be mixed up.
- **Waypoint lines** (NPC patrol paths) are drawn on the world map but not on the minimap.
- **Party sharing** uses Questie's older message format. The newer compressed messages and the "yell"
  broadcasts to nearby players are off.
- **Reputation requirements** are looked up by English faction names. On a client in another
  language, quests that need a certain reputation may be shown or hidden incorrectly.
- Map icons are not hidden in map areas you have not explored yet.
- Options are in the Ace3 options window rather than in the newer Blizzard settings panel.
- Race sound choices for races added after Wrath (Goblin, Worgen, Pandaren) play nothing.

## Testing status

Every Lua file passes a Lua 5.1 syntax check, and the code was scanned for calls to functions the
3.3.5a client does not have. Questie was also run in a simulated 3.3.5a client (a mock of the game's
API and widgets) through login, a relog with saved settings, the world map, tooltips, nameplates,
quest progress, accepting, turning in and abandoning quests, auto-accept, party sharing, the tracker,
the options window and the Journey. Testing in the real game has started, and the errors found so
far are fixed. If you see Lua errors, turn on error display with `/console scriptErrors 1` (or use
BugGrabber/BugSack) and report the full error text.

## For maintainers

- `Questie/Compat335/` is the compatibility layer and loads before everything else. It provides
  Questie's own versions of newer APIs (`C_Map`, `C_QuestLog`, `C_Calendar`, the completed-quest list,
  item loading, quest IDs at quest NPCs, ...) in the `QuestieCompat335` table instead of as globals,
  so other 3.3.5a addons that test for those globals are not misled. Files that use them start with
  e.g. `local C_Map = QuestieCompat335.C_Map`.
- `Questie/Compat335/QuestEvents335.lua` creates the quest turn-in and removal events the client
  does not fire.
- `Questie/Compat335/ZoneData335.lua` holds the 3.3.5a world map zone geometry used by HereBeDragons.
- `QuestieDB/Compat335.lua` is QuestieDB's counterpart.
- Most changes elsewhere are marked with `3.3.5a` comments. Icons were converted to TGA, as this client
  reads neither PNG files nor the uncompressed BLP format newer clients use.
- `Questie/Libs/LibUIDropDownMenu` is a thin wrapper around the client's own dropdown menus, and
  Krowi_WorldMapButtons was removed (Questie places its own world map button).

## Credits

- [Questie](https://github.com/Questie/Questie) and QuestieDB by the Questie team, licensed under the
  GNU GPL v3 (see `Questie/LICENSE.md` and `QuestieDB/LICENSE.md`). This port is under the same license.
- HereBeDragons by Nevcairiel, adapted here for the 3.3.5a world map.
- The 3.3.5a zone geometry comes from AstrolabeQH in
  [QuestHelper-WotLK](https://github.com/kamakazedan/QuestHelper-WotLK).
- Ace3, LibStub, CallbackHandler, LibDataBroker, LibDBIcon and LibSharedMedia by their authors.
