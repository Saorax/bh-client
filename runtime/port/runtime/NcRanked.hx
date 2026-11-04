package port.runtime;

import bh.platform.RatingExtras;
import bh.platform.RatingTags;
import bh.platform.net.ServerStats;

class NcRanked {
    public static var gain(default, null):Int = 0;
    public static var loss(default, null):Int = 0;
    static inline var KEPT = 50;
    static var history:Dynamic = null;
    static var played:Dynamic = {};
    static var ticks = 0;

    public static function preview(screen:Dynamic, core:GameCore, info:Class_275, size:Int):Void {
        try {
            if (screen == null || core == null || info == null || info.var_9614 == null) return;
            var playlist:Dynamic = size > 1 ? Class_309.PLAYLIST_RANKED2V2 : Class_309.PLAYLIST_RANKED1V1;
            var ladder = size > 1 ? "2v2" : "1v1";
            var me:UInt = core.var_14869;
            var players:Array<Class_276> = [for (i in 0...info.var_9614.length) if (info.var_9614[i] != null) info.var_9614[i]];
            var myTeam:Int = -1;
            for (p in players) if (p.var_12281 == me) myTeam = Std.int(p.team);
            var ours = [for (p in players) if (size > 1 ? Std.int(p.team) == myTeam : p.var_12281 == me) Std.int(p.var_7355)];
            var theirs = [for (p in players) if (size > 1 ? Std.int(p.team) != myTeam : p.var_12281 != me) Std.int(p.var_7355)];
            var mine:Dynamic = ServerStats.card(core, playlist, me);
            var total = Std.int(playlist.var_7388) > 0 ? Std.int(playlist.var_7388) : 10;
            var myGames = mine != null ? Std.int(mine.games) : total;
            gain = loss = 0;
            if (ours.length > 0 && theirs.length > 0) project(average(ours), average(theirs), myGames < total);
            RatingTags.reset();
            for (p in players) {
                var id:UInt = p.var_12281;
                var elo = Std.int(p.var_7355);
                var own = id == me;
                var personal:Dynamic = size > 1 ? (own ? mine : ServerStats.card(core, playlist, id)) : null;
                if (size > 1 && own && personal == null && savedRating() > 0) personal = {rating: savedRating()};
                if (size > 1) NcLog.say("ranked preview: player " + id + (own ? " (you)" : "") + ", team " + p.team + ", ratings " + p.var_7355 + "/"
                    + p.var_2075 + ", personal " + (personal != null ? Std.string(personal.rating) : "none"));
                if (personal != null && Std.int(personal.rating) > 0) elo = Std.int(personal.rating);
                var card:Dynamic;
                if (own) {
                    card = mine != null ? mine : {placement: total, legend: null};
                    card.last = results(ladder);
                    card.legend = legendStats(core, p);
                } else {
                    card = {placement: total, last: [], legend: null, unknown: true};
                }
                var before:Dynamic = {rating: elo, stars: stars(elo), games: own ? myGames : total, team: size > 1 && personal == null};
                if (own && (gain != 0 || loss != 0)) {
                    card.projectWin = gain;
                    card.projectLoss = loss;
                    before.projectWin = gain;
                    before.projectLoss = loss;
                }
                Reflect.setField(RatingTags.before, Std.string(id), before);
                Reflect.setField(RatingTags.cards, Std.string(id), card);
            }
            if (size == 1) {
                var them:UInt = 0;
                for (p in players) if (p.var_12281 != me) them = p.var_12281;
                RatingTags.preview([[screen.mPlayerPreview1.var_4552, me], [screen.mPlayerPreview2.var_4552, them]]);
            } else {
                var order:Array<UInt> = [me];
                for (p in players) if (p.var_12281 != me && Std.int(p.team) == myTeam) order.push(p.var_12281);
                for (p in players) if (Std.int(p.team) != myTeam) order.push(p.var_12281);
                var previews:Array<Dynamic> = [screen.mPlayerPreview1, screen.mPlayerPreview2, screen.mPlayerPreview3, screen.mPlayerPreview4];
                RatingTags.preview([for (i in 0...Std.int(Math.min(order.length, 4))) [previews[i].var_4552, order[i]]]);
            }
        } catch (error:Dynamic) {
            NcLog.say("ranked preview: " + Std.string(error));
        }
    }

    public static function clear():Void {
        try RatingTags.previewGone() catch (_:Dynamic) {}
    }

    public static function after(playlist:Dynamic, result:Dynamic):Void {
        try {
            if (playlist == null || result == null || !playlist.var_9262) return;
            var core:Dynamic = ScreenManager.owner;
            var duo = playlist == Class_309.PLAYLIST_RANKED2V2 || playlist.var_14724 || playlist.var_9243;
            var ladder = duo ? "2v2" : "1v1";
            var personal = [Std.int(result.var_14978), Std.int(result.var_5591), Std.int(result.var_4771)];
            var team = [Std.int(result.var_15315), Std.int(result.var_8734), Std.int(result.var_5272)];
            NcTiers.protect(personal[0], Std.int(result.var_4321));
            NcTiers.protect(personal[1], Std.int(result.var_7830));
            NcTiers.protect(team[0], Std.int(result.var_8103));
            NcTiers.protect(team[1], Std.int(result.var_4691));
            var card = core != null ? ownCard(core.var_14869) : 0;
            var mine = personal, other = duo ? team : null;
            if (duo && (card > 0 && team[1] == card && personal[1] != card || card <= 0 && personal[1] <= 0)) {
                mine = team;
                other = personal;
            }
            NcLog.say("ranked result: " + ladder + ", personal " + personal.join("/") + ", team " + team.join("/") + ", scoreboard "
                + card + ", playlist team " + playlist.var_14724 + "/" + playlist.var_9243);
            var games = mine[2];
            var total = Std.int(playlist.var_7388);
            var before = mine[0];
            var now = mine[1];
            var placing = total > 0 && games < total;
            if (duo) {
                note("2v2", personal);
                note("team", team);
            } else {
                note(ladder, mine);
            }
            if (now <= 0 || duo) {
                RatingExtras.reset();
                return;
            }
            if (!placing && before > 0 && core != null)
                Reflect.setField(RatingTags.after, Std.string(core.var_14869), [before, now, stars(now)]);
            var change:Dynamic = {
                before: placing || before <= 0 ? now : before,
                after: now,
                games: placing ? games : 0,
                placement: total > 0 ? total : 10,
                ladder: ladder,
                last: results(ladder)
            };
            if (other != null && other[1] > 0 && other[1] != now) change.team = {before: other[0] > 0 ? other[0] : other[1], after: other[1]};
            var row:Dynamic = core != null ? ServerStats.card(core, duo ? Class_309.PLAYLIST_RANKED2V2 : Class_309.PLAYLIST_RANKED1V1, core.var_14869) : null;
            if (row != null && Std.int(row.rating) == before && row.wins != null) {
                change.wins = Std.int(row.wins) + (now > before ? 1 : 0);
                change.peak = Std.int(Math.max(Std.int(row.peak), now));
            }
            RatingExtras.preview(change, 0);
        } catch (error:Dynamic) {
            NcLog.say("ranked result: " + Std.string(error));
        }
    }

    public static function scoreboard():Void {
        if (++ticks % 10 != 0) return;
        try {
            var board:Dynamic = ScreenManager.var_6312;
            if (board == null || !board.isActive || board.var_3170 == null) return;
            var core:Dynamic = ScreenManager.owner;
            var playlist:Dynamic = core != null && core.var_6336 != null ? core.var_6336.var_2420 : null;
            if (playlist == null || !playlist.var_9262) return;
            var cards:Dynamic = board.var_3170;
            for (i in 0...Std.int(As3.getProp(cards, "length"))) {
                var entry:Dynamic = As3.index(cards, i);
                var result:Dynamic = entry != null ? entry.var_1515 : null;
                if (result == null) continue;
                var id = Std.string(result.var_14869);
                var before:Dynamic = Reflect.field(RatingTags.before, id);
                if (before == null || Reflect.field(RatingTags.after, id) != null) continue;
                var played = Std.int(result.var_3289);
                var elo = Std.int(result.var_13089);
                before.games = played > 0 ? played - 1 : 0;
                if (played >= Std.int(playlist.var_7388) && elo > 0) {
                    before.rating = elo;
                    before.stars = stars(elo);
                }
            }
        } catch (error:Dynamic) {
            if (ticks < 100) NcLog.say("ranked scoreboard: " + Std.string(error));
        }
    }

    static function note(ladder:String, pair:Array<Int>):Void {
        if (pair[2] > 0) Reflect.setField(played, ladder, pair[2]);
        if (pair[1] > 0) saveRating(ladder, pair[1]);
        if (pair[0] > 0 && pair[1] > 0 && pair[1] != pair[0]) remember(ladder, pair[1] > pair[0] ? "win" : "loss");
    }

    public static function recent(ladder:String):Array<Dynamic> {
        return results(ladder);
    }

    static function savedRating():Int {
        return knownRating("2v2");
    }

    public static function knownRating(ladder:String):Int {
        results(ladder);
        var r:Dynamic = Reflect.field(history, "rating" + ladder);
        return r == null ? 0 : Std.int(r);
    }

    static function saveRating(ladder:String, rating:Int):Void {
        results(ladder);
        Reflect.setField(history, "rating" + ladder, rating);
        try sys.io.File.saveContent(historyFile(), haxe.Json.stringify(history)) catch (e:Dynamic) NcLog.say("ranked results: " + e);
    }

    static function ownCard(me:UInt):Int {
        var board:Dynamic = ScreenManager.var_6312;
        var cards:Dynamic = board != null ? board.var_3170 : null;
        if (cards == null) return 0;
        for (i in 0...Std.int(As3.getProp(cards, "length"))) {
            var entry:Dynamic = As3.index(cards, i);
            var result:Dynamic = entry != null ? entry.var_1515 : null;
            if (result != null && result.var_14869 == me) return Std.int(result.var_13089);
        }
        return 0;
    }

    public static function knownGames(ladder:String):Int {
        var n:Dynamic = Reflect.field(played, ladder);
        return n == null ? -1 : Std.int(n);
    }

    static function legendStats(core:Dynamic, p:Class_276):Dynamic {
        if (p.var_2870 == null) return null;
        var id = Std.int(p.var_2870.var_12012) & 0xFFFF;
        if (id <= 0) return null;
        var table:Dynamic = core.var_12883;
        var s:Dynamic = table != null && id < Std.int(As3.getProp(table, "length")) ? As3.index(table, id) : null;
        return s == null ? {id: id} : {id: id, rating: Std.int(s.var_13089), wins: Std.int(s.var_15171), games: Std.int(s.var_4771)};
    }

    static function historyFile():String {
        return port.runtime.services.Launch.storageDirectory() + "\\ranked-results.json";
    }

    static function results(ladder:String):Array<Dynamic> {
        if (history == null) {
            history = try haxe.Json.parse(sys.io.File.getContent(historyFile())) catch (_:Dynamic) {};
        }
        var list:Array<Dynamic> = Reflect.field(history, ladder);
        if (list == null) return [];
        var newest = list.slice(-12);
        newest.reverse();
        return newest;
    }

    static function remember(ladder:String, result:String):Void {
        results(ladder);
        var list:Array<Dynamic> = Reflect.field(history, ladder);
        if (list == null) Reflect.setField(history, ladder, list = []);
        list.push(result);
        while (list.length > KEPT) list.shift();
        try sys.io.File.saveContent(historyFile(), haxe.Json.stringify(history)) catch (e:Dynamic) NcLog.say("ranked results: " + e);
    }

    static function project(mine:Float, other:Float, placing:Bool):Void {
        var k = (mine >= 2400 ? 10 : 32) * (placing ? 3 : 1);
        var expected = 1 / (1 + Math.pow(10, (other - mine) / 400));
        gain = Math.round(k * (1 - expected));
        loss = Math.round(k * expected);
        if (mine - loss < 200) loss = Std.int(Math.max(0, mine - 200));
    }

    static function stars(elo:Int):Int {
        return elo <= 0 ? 0 : try Std.int(NcTiers.stars(elo)) catch (_:Dynamic) 0;
    }

    static function average(values:Array<Int>):Float {
        var sum = 0.0;
        for (v in values) sum += v;
        return sum / values.length;
    }
}
