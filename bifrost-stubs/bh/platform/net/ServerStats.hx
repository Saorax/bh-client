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
            var user:UInt = parts.length > 2 ? Std.parseInt(parts[2]) : watching ? lobbyLead(core) : core.var_14871;
            if (ladder == "team") return parts.length == 3 && !watching ? teamCard(core, core.var_14871, user) : null;
            return card(core, ladder == "2v2" ? Class_309.PLAYLIST_RANKED2V2 : Class_309.PLAYLIST_RANKED1V1, user);
        } catch (_:Dynamic) {
            return null;
        }
    }

    public static function spectating():Bool {
        var core:Dynamic = ScreenManager.owner;
        if (core == null) return false;
        var flags = port.runtime.As3.toInt(core.var_3645);
        if ((flags & 32) != 0) flags = port.runtime.As3.toInt(core.var_13785);
        if ((flags & (262144 | 524288)) != 0) return true;
        var people = lobbyPeople(core);
        return people.length > 0 && people.indexOf(port.runtime.As3.toUInt(core.var_14871)) < 0;
    }

    static function lobbyPeople(core:Dynamic):Array<UInt> {
        var out:Array<UInt> = [];
        var members:Dynamic = core.var_6336 != null ? core.var_6336.var_1780 : null;
        if (members == null) return out;
        for (i in 0...port.runtime.As3.toInt(port.runtime.As3.getProp(members, "length"))) {
            var member:Dynamic = port.runtime.As3.index(members, i);
            if (member == null || port.runtime.As3.toInt(member.var_12698) != HUMAN) continue;
            var id:UInt = port.runtime.As3.toUInt(member.var_14871);
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
        return core.var_11558.method_4997("e" + playlist.var_4137 + "u" + user);
    }

    public static function teamKey(a:UInt, b:UInt):String {
        return a < b ? "team:" + a + "-" + b : "team:" + b + "-" + a;
    }

    public static function lobbyTeam(core:Dynamic):String {
        if (core == null) return null;
        var people = lobbyPeople(core);
        var me:UInt = port.runtime.As3.toUInt(core.var_14871);
        if (people.length != 2 || people.indexOf(me) < 0 || people[0] == people[1]) return null;
        return teamKey(people[0], people[1]);
    }

    static function teamRow(core:Dynamic, playlist:Dynamic, a:UInt, b:UInt):Dynamic {
        var r:Dynamic = core.method_4569(a, b, port.runtime.As3.toUInt(playlist.var_4137));
        if (r != null) return r;
        var latest:Dynamic = core.var_13878;
        if (latest == null || port.runtime.As3.toUInt(latest.var_11782) != port.runtime.As3.toUInt(playlist.var_4137)) return null;
        var x:UInt = port.runtime.As3.toUInt(latest.var_12279);
        var y:UInt = port.runtime.As3.toUInt(latest.var_11749);
        return x == a && y == b || x == b && y == a ? latest : null;
    }

    static function teamCard(core:Dynamic, me:UInt, mate:UInt):Dynamic {
        var playlist:Dynamic = Class_309.PLAYLIST_RANKED2V2;
        if (playlist == null || me == 0 || mate == 0 || me == mate) return null;
        var key = teamKey(me, mate);
        var r:Dynamic = teamRow(core, playlist, me, mate);
        var rating = r != null ? Std.int(r.var_7356) : 0;
        var games = r != null ? Std.int(r.var_7328) : 0;
        var known = port.runtime.NcRanked.knownGames(key);
        var latest = port.runtime.NcRanked.knownRating(key);
        if (known > games && latest > 0) rating = latest;
        if (known > games) games = known;
        if (r != null) port.runtime.NcTiers.protect(Std.int(r.var_7356), Std.int(r.starRating));
        return {
            team: true,
            rating: rating,
            stars: r != null && rating == Std.int(r.var_7356) ? Std.int(r.starRating) : rating > 0 ? port.runtime.NcTiers.stars(rating) : 0,
            games: games,
            wins: r != null ? Std.int(r.var_9108) : 0,
            peak: r != null ? Std.int(r.var_1839) : 0,
            rank: r != null ? Std.int(r.var_4739) : 0,
            placement: Std.int(playlist.var_7390) > 0 ? Std.int(playlist.var_7390) : 10,
            season: Class_55.var_1988 > 0 ? Std.int(Class_55.var_1988) : null,
            ladder: "2v2",
            last: port.runtime.NcRanked.recent(key),
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
