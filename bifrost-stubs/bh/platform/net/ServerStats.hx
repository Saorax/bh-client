package bh.platform.net;

class ServerStats {
    public static function get(query:String):Dynamic {
        try {
            var core:Dynamic = ScreenManager.owner;
            if (core == null || query == null) return null;
            var parts = query.split(":");
            if (parts.length < 2 || parts[0] != "ranked") return null;
            var ladder = parts[1];
            var user:UInt = parts.length > 2 ? Std.parseInt(parts[2]) : core.var_14871;
            if (ladder == "team") return null;
            if (ladder == "2v2" && parts.length == 2) {
                var team:Dynamic = teamCard(core);
                if (team != null) return team;
            }
            return card(core, ladder == "2v2" ? Class_309.PLAYLIST_RANKED2V2 : Class_309.PLAYLIST_RANKED1V1, user);
        } catch (_:Dynamic) {
            return null;
        }
    }

    public static function row(core:Dynamic, playlist:Dynamic, user:UInt):Dynamic {
        if (core == null || playlist == null) return null;
        return core.var_11558.method_4997("e" + playlist.var_4137 + "u" + user);
    }

    static function teamCard(core:Dynamic):Dynamic {
        var playlist:Dynamic = core.var_6336 != null ? core.var_6336.var_2424 : null;
        var r:Dynamic = playlist != null && playlist.var_9262 && playlist.var_14727 ? core.var_13878 : null;
        if (r == null) return null;
        var rating = Std.int(r.var_7356);
        var latest = port.runtime.NcRanked.knownRating("team");
        var games = Std.int(r.var_7328);
        if (port.runtime.NcRanked.knownGames("team") > games && latest > 0) {
            rating = latest;
            games = port.runtime.NcRanked.knownGames("team");
        }
        port.runtime.NcTiers.protect(Std.int(r.var_7356), Std.int(r.starRating));
        return {
            rating: rating,
            stars: rating != Std.int(r.var_7356) ? port.runtime.NcTiers.stars(rating) : Std.int(r.starRating),
            games: games,
            wins: Std.int(r.var_9108),
            peak: Std.int(r.var_1839),
            rank: Std.int(r.var_4739),
            placement: Std.int(playlist.var_7390) > 0 ? Std.int(playlist.var_7390) : 10,
            season: Class_55.var_1988 > 0 ? Std.int(Class_55.var_1988) : null,
            ladder: "2v2",
            last: port.runtime.NcRanked.recent("team"),
            legend: null
        };
    }

    public static function card(core:Dynamic, playlist:Dynamic, user:UInt):Dynamic {
        var r:Dynamic = row(core, playlist, user);
        if (r == null) return null;
        var games = Std.int(r.var_7328);
        var rating = Std.int(r.var_7356);
        var solo = playlist != Class_309.PLAYLIST_RANKED2V2;
        if (user == core.var_14871) port.runtime.NcTiers.protect(rating, Std.int(r.starRating));
        if (user == core.var_14871) {
            var known = port.runtime.NcRanked.knownGames(solo ? "1v1" : "2v2");
            var latest = port.runtime.NcRanked.knownRating(solo ? "1v1" : "2v2");
            if (known > games && latest > 0) rating = latest;
            if (known > games) games = known;
            if (solo) {
                var legends = 0;
                var table:Dynamic = core.var_12884;
                if (table != null) for (i in 0...Std.int(port.runtime.As3.getProp(table, "length"))) {
                    var l:Dynamic = port.runtime.As3.index(table, i);
                    if (l != null) legends += Std.int(l.var_4768);
                }
                if (legends > games) games = legends;
            }
        }
        return {
            rating: rating,
            stars: rating != Std.int(r.var_7356) ? port.runtime.NcTiers.stars(rating) : Std.int(r.starRating),
            ladder: solo ? "1v1" : "2v2",
            games: games,
            wins: Std.int(r.var_9108),
            peak: Std.int(r.var_1839),
            rank: Std.int(r.var_4739),
            placement: Std.int(playlist.var_7390) > 0 ? Std.int(playlist.var_7390) : 10,
            season: Class_55.var_1988 > 0 ? Std.int(Class_55.var_1988) : null,
            last: user == core.var_14871 ? port.runtime.NcRanked.recent(solo ? "1v1" : "2v2") : [],
            legend: null
        };
    }
}
