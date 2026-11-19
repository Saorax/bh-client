package bh.platform.net;

class ServerStats {
    static inline var HUMAN = 2;

    public static function get(query:String):Dynamic {
        try {
            var core:Dynamic = ScreenManager.owner;
            if (core == null || query == null) return null;
            var parts = query.split(":");
            if (parts.length < 2 || parts[0] != "ranked") return null;
            var ladder = parts[1];
            var watching = spectating();
            var user:UInt = parts.length > 2 ? Std.parseInt(parts[2]) : watching ? lobbyLead(core) : core.var_14927;
            if (ladder == "team") return parts.length == 3 && !watching ? teamCard(core, core.var_14927, user) : null;
            return card(core, ladder == "2v2" ? PlaylistType.PLAYLIST_RANKED2V2 : PlaylistType.PLAYLIST_RANKED1V1, user);
        } catch (_:Dynamic) {
            return null;
        }
    }

    public static function spectating():Bool {
        var core:Dynamic = ScreenManager.owner;
        if (core == null) return false;
        var flags = port.runtime.As3.toInt(core.mGameState);
        if ((flags & 32) != 0) flags = port.runtime.As3.toInt(core.mGameStateBeforePause);
        if ((flags & (262144 | 524288)) != 0) return true;
        var people = lobbyPeople(core);
        return people.length > 0 && people.indexOf(port.runtime.As3.toUInt(core.var_14927)) < 0;
    }

    static function lobbyPeople(core:Dynamic):Array<UInt> {
        var out:Array<UInt> = [];
        var members:Dynamic = core.mCustomGameData != null ? core.mCustomGameData.mPlayers : null;
        if (members == null) return out;
        for (i in 0...port.runtime.As3.toInt(port.runtime.As3.getProp(members, "length"))) {
            var member:Dynamic = port.runtime.As3.index(members, i);
            if (member == null || port.runtime.As3.toInt(member.var_12740) != HUMAN) continue;
            var id:UInt = port.runtime.As3.toUInt(member.var_14927);
            if (id != 0) out.push(id);
        }
        return out;
    }

    static function lobbyLead(core:Dynamic):UInt {
        var people = lobbyPeople(core);
        return people.length > 0 ? people[0] : 0;
    }

    public static function row(core:Dynamic, playlist:Dynamic, user:UInt):Dynamic {
        if (core == null || playlist == null) return null;
        return core.mRatingInfo.method_5042("e" + playlist.var_4148 + "u" + user);
    }

    public static function teamKey(a:UInt, b:UInt):String {
        return a < b ? "team:" + a + "-" + b : "team:" + b + "-" + a;
    }

    public static function lobbyTeam(core:Dynamic):String {
        if (core == null) return null;
        var people = lobbyPeople(core);
        var me:UInt = port.runtime.As3.toUInt(core.var_14927);
        if (people.length != 2 || people.indexOf(me) < 0 || people[0] == people[1]) return null;
        return teamKey(people[0], people[1]);
    }

    static function teamRow(core:Dynamic, playlist:Dynamic, a:UInt, b:UInt):Dynamic {
        var r:Dynamic = core.method_4607(a, b, port.runtime.As3.toUInt(playlist.var_4148));
        if (r != null) return r;
        var latest:Dynamic = core.var_13926;
        if (latest == null || port.runtime.As3.toUInt(latest.var_11823) != port.runtime.As3.toUInt(playlist.var_4148)) return null;
        var x:UInt = port.runtime.As3.toUInt(latest.userID);
        var y:UInt = port.runtime.As3.toUInt(latest.userIDTwo);
        return x == a && y == b || x == b && y == a ? latest : null;
    }

    static function teamCard(core:Dynamic, me:UInt, mate:UInt):Dynamic {
        var playlist:Dynamic = PlaylistType.PLAYLIST_RANKED2V2;
        if (playlist == null || me == 0 || mate == 0 || me == mate) return null;
        var key = teamKey(me, mate);
        var r:Dynamic = teamRow(core, playlist, me, mate);
        var rating = r != null ? Std.int(r.eloRating) : 0;
        var games = r != null ? Std.int(r.games) : 0;
        var known = port.runtime.NcRanked.knownGames(key);
        var latest = port.runtime.NcRanked.knownRating(key);
        if (known > games && latest > 0) rating = latest;
        if (known > games) games = known;
        if (r != null) port.runtime.NcTiers.protect(Std.int(r.eloRating), Std.int(r.starRating));
        return {
            team: true,
            rating: rating,
            stars: r != null && rating == Std.int(r.eloRating) ? Std.int(r.starRating) : rating > 0 ? port.runtime.NcTiers.stars(rating) : 0,
            games: games,
            wins: r != null ? Std.int(r.var_9140) : 0,
            peak: r != null ? Std.int(r.bestRating) : 0,
            rank: r != null ? Std.int(r.rank) : 0,
            placement: Std.int(playlist.mPlacementGames) > 0 ? Std.int(playlist.mPlacementGames) : 10,
            season: GameUtil.var_1994 > 0 ? Std.int(GameUtil.var_1994) : null,
            ladder: "2v2",
            last: port.runtime.NcRanked.recent(key),
            legend: null
        };
    }

    public static function card(core:Dynamic, playlist:Dynamic, user:UInt):Dynamic {
        var r:Dynamic = row(core, playlist, user);
        if (r == null) return null;
        var games = Std.int(r.games);
        var rating = Std.int(r.eloRating);
        var solo = playlist != PlaylistType.PLAYLIST_RANKED2V2;
        if (user == core.var_14927) port.runtime.NcTiers.protect(rating, Std.int(r.starRating));
        if (user == core.var_14927) {
            var known = port.runtime.NcRanked.knownGames(solo ? "1v1" : "2v2");
            var latest = port.runtime.NcRanked.knownRating(solo ? "1v1" : "2v2");
            if (known > games && latest > 0) rating = latest;
            if (known > games) games = known;
            if (solo) {
                var legends = 0;
                var table:Dynamic = core.mHeroRatingHash;
                if (table != null) for (i in 0...Std.int(port.runtime.As3.getProp(table, "length"))) {
                    var l:Dynamic = port.runtime.As3.index(table, i);
                    if (l != null) legends += Std.int(l.mGames);
                }
                if (legends > games) games = legends;
            }
        }
        return {
            rating: rating,
            stars: rating != Std.int(r.eloRating) ? port.runtime.NcTiers.stars(rating) : Std.int(r.starRating),
            ladder: solo ? "1v1" : "2v2",
            games: games,
            wins: Std.int(r.var_9140),
            peak: Std.int(r.bestRating),
            rank: Std.int(r.rank),
            placement: Std.int(playlist.mPlacementGames) > 0 ? Std.int(playlist.mPlacementGames) : 10,
            season: GameUtil.var_1994 > 0 ? Std.int(GameUtil.var_1994) : null,
            last: user == core.var_14927 ? port.runtime.NcRanked.recent(solo ? "1v1" : "2v2") : [],
            legend: null
        };
    }
}
