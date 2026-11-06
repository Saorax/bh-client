ENTRIES = [
    "StatsOverlay",
    "InputDisplay",
    "PadDisplay",
    "RatingTags",
    "RatingExtras",
    "Setups",
    "LoadoutWindow",
    "HookSites",
    "LobbyScreenMod",
    "OptionsScreenMod",
    "TrainingMenu",
    "DiscordPresenceMod",
    "LoadingBackground",
    "Controllers",
    "TrainingPlayers",
    "PeerTraining",
]

FORBIDDEN = [
    "PrivateServer", "P2PMatch", "P2PConnection", "MatchReport", "HudPing", "RoomNet", "P2PChoice", "Skirmish",
    "StartCover", "Rejoin", "ModCheck",
    "DiscordLogin", "CloudSave", "Friends", "FriendsWindow", "ProfileWindow", "ServerStats", "Moderation",
    "ModerationWindow", "BugReport", "ReplayShare", "SpectateFeed", "ModShare", "PlayerName",
    "Unlocks", "NoStore", "AchievementsWindow", "SaveCopy", "SaveEditorWindow",
    "ContentMods", "ModModes", "ModLanguages", "MusicPacks", "MapArt", "MoveEditor", "TrainingModes",
]

HOOK_STUBS = ["Platform"]

PARTS = {
    "LeaderboardWindow": [
        "art", "waitingArt", "asked", "tierArtState", "NOTCHED", "picture", "tierBanner", "rankName", "notchOf",
        "withNotches", "legendIcon", "avatar", "legendName", "localized", "moniker", "monikerName", "monikerColour",
        "mapName", "mapLevel", "mapThumb", "allLegends",
    ],
    "Ranks": ["tierNumber"],
    "DiscordPresenceMod": [
        "PREF_ENABLED", "PREF_JOIN", "loaded", "enabled", "register", "onSettingsAttached", "readPreference",
        "getPreference", "setPreference", "addStrings", "addSettings", "addSetting",
        "LOG", "SECRET_PREFIX", "allowJoin", "matchStartedAt", "queueRequested", "queueStartedAt", "ART_KEYS", "ART_URL",
        "mapUrls", "buildActivity", "modeName", "participantNames", "currentLegend", "currentHero", "artKey", "mapUrl",
        "legendUrl", "currentMap", "activePlayers", "log", "shorten", "now",
    ],
}

NEVER = [
    "hook-packet-received", "hook-packet-sending-tcp", "hook-packet-sending-udp", "hook-tcp-connect",
    "hook-profile-name-for-slot", "hook-profile-for-slot", "hook-profile-for-slot-2", "hook-controls-profile",
    "hook-keybinds-save-profile", "hook-keybinds-menu-profile", "hook-keybinds-load-profile",
]

STATS_P2P_START = "         var ping:Int = P2PSession.ping;\n"
STATS_P2P_END = "         if((lineOn(4)))\n"
STATS_OFFICIAL = """         var matchPing:Float = port.runtime.NcRtt.matchPingMs();
         var ping:Float = matchPing >= 0 ? matchPing : port.runtime.NcStats.lobbyPingMs;
         if((lineOn(2)))
         {
            parts.push("PING " + (ping >= 0 ? Math.round(ping) + " ms" : "-"));
         }
         if((lineOn(3)) && port.runtime.NcStats.inMatch())
         {
            parts.push("MATCH " + port.runtime.NcStats.udpInPerSecond + "/" + port.runtime.NcStats.udpOutPerSecond + " PER S, GAP " +
               Math.round(port.runtime.NcStats.udpLongestGapMs) + " ms");
            if(port.runtime.NcStats.matchServer != "")
            {
               parts.push("SERVER " + port.runtime.NcStats.matchServer);
            }
         }
"""

PROJECTION_SIDE = (
    '         UiKit.text(g,"ELO RATING",mid,ry + r.height - 4 * sc,12 * sc,port.runtime.As3.toInt(LABEL),'
    'port.runtime.As3.stringParam(UiKit.XBOLD),0,true);\n')

PATCHES = [
    ("LeaderboardWindow", ("all", "PrivateServer.log("), "Platform.log("),
    ("RatingExtras", PROJECTION_SIDE, PROJECTION_SIDE +
     '         if(card.projectWin != null)\n'
     '         {\n'
     '            var gainText:TextField = cast(UiKit.text(g,"WIN +" + card.projectWin,mid - 8 * sc,ry - 34 * sc,15 * sc,0x5BD67A,'
     'port.runtime.As3.stringParam(UiKit.XBOLD)));\n'
     '            gainText.x = mid - gainText.width - 8 * sc;\n'
     '            UiKit.text(g,"LOSS -" + card.projectLoss,mid + 8 * sc,ry - 34 * sc,15 * sc,0xF0646A,'
     'port.runtime.As3.stringParam(UiKit.XBOLD));\n'
     '         }\n'),
    ("RatingExtras", "         panel(g,x,y,w,h,sc);\n         var mid:Float",
     "         if(card.unknown == true)\n         {\n            h = 400 * sc;\n         }\n         panel(g,x,y,w,h,sc);\n         var mid:Float"),
    ("RatingExtras", "         var colW:Float = (w - 2 * pad) / 4;\n",
     "         if(card.unknown == true)\n         {\n            return !incomplete;\n         }\n"
     "         var colW:Float = (w - 2 * pad) / 4;\n"),
    ("RatingExtras", "            teammateLine(g,c.teammate,cx,ry,right,sc);\n", ""),
    ("RatingTags", 'rankLabel(port.runtime.As3.toUInt(b.stars)),"bottom":Std.string(b.rating),"colour":0xFFFFFF,',
     'rankLabel(port.runtime.As3.toUInt(b.stars)),"bottom":(b.team == true ? "TEAM " : "") + Std.string(b.rating),'
     '"gain":b.projectWin,"loss":b.projectLoss,"colour":0xFFFFFF,'),
    ("StatsOverlay", "   import bh.platform.net.Desync;\n   import bh.platform.net.HudPing;\n   import bh.platform.net.P2PSession;\n", ""),
    ("StatsOverlay", ("span", STATS_P2P_START, STATS_P2P_END), STATS_OFFICIAL),
    ("StatsOverlay", "The round trip to the other player in a P2P match (the slowest one with more ",
     "Your round trip to the match server during an online match (the game's own measurement), and to the lobby server outside one."),
    ("StatsOverlay", "players), measured every second.", ""),
    ("StatsOverlay", '"P2P DETAILS"', '"MATCH DETAILS"'),
    ("StatsOverlay", "In a P2P match: the path (direct, or through the server's relay), the input ",
     "In an online match: game packets received and sent each second, and GAP, the longest wait for a packet from the "
     "server in the last second. A big gap is a lag spike."),
    ("StatsOverlay", "delay chosen from the ping, rollbacks so far and the longest one, times this PC waited for a late input, and ", ""),
    ("StatsOverlay", "the desync check (OK, or DESYNC when the two PCs' matches differ), and MODS DIFFER when the other player runs other content mods.", ""),
    ("InputDisplay",
     '         (port.runtime.As3.asType(port.runtime.As3.getProp(cap, "label"), TextField)).textColor = (on) ? UiKit.NAVY_TEXT : UiKit.WHITE;',
     '         var labelField:TextField = cast port.runtime.As3.getProp(cap, "label");\n'
     '         if (labelField != null) labelField.textColor = (on) ? UiKit.NAVY_TEXT : UiKit.WHITE;'),
    ("InputDisplay",
     "         (port.runtime.As3.asType(cap.action, TextField)).textColor = (on) ? UiKit.NAVY_TEXT : UiKit.GREY;",
     "         var actionField:TextField = cast cap.action;\n"
     "         if (actionField != null) actionField.textColor = (on) ? UiKit.NAVY_TEXT : UiKit.GREY;"),
    ("PadDisplay",
     "         (port.runtime.As3.asType(c.t, TextField)).textColor = (on) ? UiKit.NAVY_TEXT : UiKit.GREY;",
     "         var capField:TextField = cast c.t;\n"
     "         if (capField != null) capField.textColor = (on) ? UiKit.NAVY_TEXT : UiKit.GREY;"),
    ("OptionsScreen", "public static var regionPicker:Bool = false;", "public static var regionPicker:Bool = true;"),
    ("OptionsScreen", '["SYSTEM","PREFERENCES","GRAPHICS","SERVERS","PROFILES","CONTROLS","MORE"]',
     '["SYSTEM","PREFERENCES","GRAPHICS","CONTROLS","MORE"]'),
    ("OptionsScreen", "            case 3:\n               buildServers();\n            case 4:\n               buildProfiles();\n"
     "            case 5:\n               buildControls();\n",
     "            case 3:\n               buildControls();\n"),
    ("OptionsScreen", "(tab <= 2 || tab == 4 ?", "(tab <= 2 ?"),
    ("OptionsScreen", "SEARCHED:Array<Dynamic> = [0,1,2,5,6,7,8];", "SEARCHED:Array<Dynamic> = [0,1,2,3,4];"),
    ("OptionsScreen", ("span", "      private function servers():Array<Dynamic>\n", "      private var typed:Dynamic = {};\n"), ""),
    ("OptionsScreen", ("span", '            ["UNLOCK ACHIEVEMENTS",', '         var y:Float = 10;'),
     "            ];\n"
     "         if(ScreenManager.owner.var_3865 != 0)\n"
     "         {\n"
     '            entries.push(["ACCOUNT LINKING","Link this account to your Ubisoft account and your other platforms, '
     "the game's own Account Linking screen.\",function():Void\n"
     "            {\n"
     "               close();\n"
     "               ScreenManager.var_2627.Display();\n"
     "            }]);\n"
     "         }\n"),
    ("LobbySettingsScreen", '["GAME RULES","LOBBY","PRESETS","NETWORK"]', '["GAME RULES","LOBBY","PRESETS"]'),
    ("LobbySettingsScreen", "            case 2:\n               buildPresets();\n            default:\n               buildNetwork();\n",
     "            default:\n               buildPresets();\n"),
    ("LobbySettingsScreen", ("span", "      private static final DELAYS:Array<Dynamic>",
                             "      private function stepper(act:Dynamic, dir:Int):Dynamic"), ""),
    ("Ranks", "         if(rating < 0 || rating >= port.runtime.As3.toInt(VALHALLAN_AT))\n", "         if(rating < 0)\n"),
    ("Ranks", "return stars == 0 ? 0 : 6 - port.runtime.As3.toInt(Class_197.method_1562(stars));",
     "return port.runtime.NcTiers.division(stars);"),
    ("RatingTags", ("span", "         try\n         {\n            return Std.string(Class_197.method_7470(stars)).toUpperCase()",
                    "      private static function stage():Stage"),
     "         return port.runtime.NcTiers.label(stars);\n      }\n\n"),
    ("RatingExtras", ("span", "      public static function tierName(rating:Int):String\n", "      private static function winRate("),
     "      public static function tierName(rating:Int):String\n      {\n         return port.runtime.NcTiers.name(rating);\n      }\n\n"
     "      private static function bannerTier(rating:Int, placing:Bool):String\n      {\n"
     "         return placing ? \"Unranked\" : port.runtime.NcTiers.banner(rating);\n      }\n\n"
     "      private static function toNext(rating:Int):String\n      {\n         return port.runtime.NcTiers.toNext(rating);\n      }\n\n"),
    ("RatingExtras", "var part:Float = (rating >= VALHALLAN ? 1 : (port.runtime.As3.mathMax2(0,rating) % RANK_SPAN) / RANK_SPAN);",
     "var part:Float = port.runtime.NcTiers.part(rating);"),
    ("RatingExtras", ("span", "         if(!(placing) && rating >= VALHALLAN)\n", "         var cacheKey:String"),
     "         if(!(placing))\n         {\n            star = port.runtime.NcTiers.stars(rating);\n"
     "            notch = port.runtime.NcTiers.notch(rating) + 1;\n         }\n"),
    ("RatingExtras", 'UiKit.gotoLabel(notches,"Notch" + notch);', 'UiKit.gotoLabel(notches,"Notch" + (notch - 1));'),
    ("TrainingSettingsScreen", '"Player_BhHitboxTrail","Player_BhFrameData"]],\n           ["NETWORK",["Player_BhOnlinePractice"]]]],',
     '"Player_BhHitboxTrail","Player_BhFrameData"]]]],'),
    ("OptionsScreen", '["UI_Bifrost_DiscordPresence","UI_Bifrost_DiscordJoin"]', '["UI_Bifrost_DiscordPresence"]'),
    ("TrainingSettingsScreen", ',function():Void { TrainingKeys.on = !TrainingKeys.on; }],\n'
     '            ["MOVE EDITOR",function():Void { MoveEditor.open(); }]];',
     ',function():Void { TrainingKeys.on = !TrainingKeys.on; }]];'),
    ("TrainingSettingsScreen", "         if(MoveEditor.shown != null)\n         {\n            return MoveEditor.shown.HandleInput(input);\n"
     "         }\n", ""),
    ("LaunchOptions", ("span", '         if(ModSettings.value("showVersionDefaulted") != true)\n', "         Hooks.launchArgs.add(addSaved);\n"), ""),
    ("DiscordPresenceMod", ("span", "         Hooks.packetSending.add(onPacketSending);\n", "      private static function onSettingsAttached"),
     "      }\n\n"),
    ("DiscordPresenceMod", ("all", "         refresh(true);\n"), ""),
    ("DiscordPresenceMod", "private static var enabled:Bool", "public static var enabled:Bool"),
    ("DiscordPresenceMod", "Show your current Bifrost activity in Discord.", "Show what you are playing on your Discord profile."),
    ("DiscordPresenceMod", '         strings.method_65("UI_Bifrost_DiscordJoin","Allow Discord Joining");\n', ""),
    ("DiscordPresenceMod", '         strings.method_65("UI_Bifrost_DiscordJoin_Tooltip",'
     '"Let Discord friends spectate your open Custom lobby. Off by default.");\n', ""),
    ("DiscordPresenceMod", '         addSetting(screen,list,"UI_Bifrost_DiscordJoin",PREF_JOIN);\n', ""),
    ("DiscordPresenceMod", "PrivateServer.host != null", "false"),
    ("DiscordPresenceMod", "private static function buildActivity()", "public static function buildActivity()"),
    ("DiscordPresenceMod", "var inMatch:Bool = port.runtime.As3.toUInt(core.gameState) == 6;",
     "var inMatch:Bool = Platform.live(core);"),
    ("PostMatchStats", "            else if(to == 3)\n", "            else if(to == 3 && from != 6)\n"),
    ("TrainingSettingsScreen", '         "Player_BhOnlinePractice":"A simulated ping: input delay and rollback as in a P2P match (Bifrost).",\n', ""),
    ("OnlineTraining", ("all", "TrainingModes.PREFIX"), '"BHTraining_"'),
    ("P2PSession", '" Details are in Documents" + port.runtime.NativeString.fromCharCode(92) + Platform.dataFolder() +\n'
     '               port.runtime.NativeString.fromCharCode(92) + "bh-private.txt.");', '" Details are in the game\'s log.");'),
]
