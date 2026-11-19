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

    public static function preview(screen:Dynamic, core:GameCore, info:MatchPreviewCard, size:Int):Void {
        try {
            if (screen == null || core == null || info == null || info.playerList == null) return;
            var playlist:Dynamic = size > 1 ? PlaylistType.PLAYLIST_RANKED2V2 : PlaylistType.PLAYLIST_RANKED1V1;
            var ladder = size > 1 ? "2v2" : "1v1";
            var me:UInt = core.var_14927;
            var players:Array<MatchPreviewPlayer> = [for (i in 0...info.playerList.length) if (info.playerList[i] != null) info.playerList[i]];
            var myTeam:Int = -1;
            for (p in players) if (p.userID == me) myTeam = Std.int(p.team);
            var ours = [for (p in players) if (size > 1 ? Std.int(p.team) == myTeam : p.userID == me) Std.int(p.eloRating)];
            var theirs = [for (p in players) if (size > 1 ? Std.int(p.team) != myTeam : p.userID != me) Std.int(p.eloRating)];
            var mine:Dynamic = ServerStats.card(core, playlist, me);
            var total = Std.int(playlist.mPlacementGames) > 0 ? Std.int(playlist.mPlacementGames) : 10;
            var myGames = mine != null ? Std.int(mine.games) : total;
            gain = loss = 0;
            if (ours.length > 0 && theirs.length > 0) project(average(ours), average(theirs), myGames < total);
            RatingTags.reset();
            for (p in players) {
                var id:UInt = p.userID;
                var elo = Std.int(p.eloRating);
                var own = id == me;
                var personal:Dynamic = size > 1 ? (own ? mine : ServerStats.card(core, playlist, id)) : null;
                if (size > 1 && own && personal == null && savedRating() > 0) personal = {rating: savedRating()};
                if (size > 1) NcLog.say("ranked preview: player " + id + (own ? " (you)" : "") + ", team " + p.team + ", ratings " + p.eloRating + "/"
                    + p.var_2084 + ", personal " + (personal != null ? Std.string(personal.rating) : "none"));
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
            var playing = Lambda.exists(players, p -> p.userID == me);
            if (size == 1) {
                var first:UInt = me;
                var them:UInt = 0;
                if (!playing && players.length > 1) {
                    first = players[1].userID;
                    them = players[0].userID;
                } else {
                    for (p in players) if (p.userID != me) them = p.userID;
                }
                RatingTags.preview([[screen.mPlayerPreview1.mComponentMovieClip, first], [screen.mPlayerPreview2.mComponentMovieClip, them]]);
            } else {
                var lead:UInt = !playing && players.length > 0 ? players[0].userID : me;
                var leadTeam = !playing && players.length > 0 ? Std.int(players[0].team) : myTeam;
                var order:Array<UInt> = [lead];
                for (p in players) if (p.userID != lead && Std.int(p.team) == leadTeam) order.push(p.userID);
                for (p in players) if (Std.int(p.team) != leadTeam) order.push(p.userID);
                var previews:Array<Dynamic> = [screen.mPlayerPreview1, screen.mPlayerPreview2, screen.mPlayerPreview3, screen.mPlayerPreview4];
                RatingTags.preview([for (i in 0...Std.int(Math.min(order.length, 4))) [previews[i].mComponentMovieClip, order[i]]]);
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
            if (playlist == null || result == null || !playlist.mbRanked) return;
            var core:Dynamic = ScreenManager.owner;
            var duo = playlist == PlaylistType.PLAYLIST_RANKED2V2 || playlist.var_14783 || playlist.var_9275;
            var ladder = duo ? "2v2" : "1v1";
            var personal = [Std.int(result.mOldElo), Std.int(result.mNewElo), Std.int(result.mGames)];
            var team = [Std.int(result.mOldTeamElo), Std.int(result.mNewTeamElo), Std.int(result.var_5282)];
            NcTiers.protect(personal[0], Std.int(result.mNewStarRating));
            NcTiers.protect(personal[1], Std.int(result.mOldStarRating));
            NcTiers.protect(team[0], Std.int(result.mNewTeamStarRating));
            NcTiers.protect(team[1], Std.int(result.mOldTeamStarRating));
            var card = core != null ? ownCard(core.var_14927) : 0;
            var mine = personal, other = duo ? team : null;
            if (duo && (card > 0 && team[1] == card && personal[1] != card || card <= 0 && personal[1] <= 0)) {
                mine = team;
                other = personal;
            }
            NcLog.say("ranked result: " + ladder + ", personal " + personal.join("/") + ", team " + team.join("/") + ", scoreboard "
                + card + ", playlist team " + playlist.var_14783 + "/" + playlist.var_9275);
            var games = mine[2];
            var total = Std.int(playlist.mPlacementGames);
            var before = mine[0];
            var now = mine[1];
            var placing = total > 0 && games < total;
            if (duo) {
                note("2v2", personal);
                var pair = ServerStats.lobbyTeam(core);
                if (pair != null) note(pair, team);
            } else {
                note(ladder, mine);
            }
            if (now <= 0 || duo) {
                RatingExtras.reset();
                return;
            }
            if (!placing && before > 0 && core != null)
                Reflect.setField(RatingTags.after, Std.string(core.var_14927), [before, now, stars(now)]);
            var change:Dynamic = {
                before: placing || before <= 0 ? now : before,
                after: now,
                games: placing ? games : 0,
                placement: total > 0 ? total : 10,
                ladder: ladder,
                last: results(ladder)
            };
            if (other != null && other[1] > 0 && other[1] != now) change.team = {before: other[0] > 0 ? other[0] : other[1], after: other[1]};
            var row:Dynamic = core != null ? ServerStats.card(core, duo ? PlaylistType.PLAYLIST_RANKED2V2 : PlaylistType.PLAYLIST_RANKED1V1, core.var_14927) : null;
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
            var board:Dynamic = ScreenManager.screenScoreboard;
            if (board == null || !board.isActive || board.mPodiums == null) return;
            var core:Dynamic = ScreenManager.owner;
            var playlist:Dynamic = core != null && core.mCustomGameData != null ? core.mCustomGameData.var_2435 : null;
            if (playlist == null || !playlist.mbRanked) return;
            var cards:Dynamic = board.mPodiums;
            for (i in 0...Std.int(As3.getProp(cards, "length"))) {
                var entry:Dynamic = As3.index(cards, i);
                var result:Dynamic = entry != null ? entry.mPostgameData : null;
                if (result == null) continue;
                var id = Std.string(result.var_14927);
                var before:Dynamic = Reflect.field(RatingTags.before, id);
                if (before == null || Reflect.field(RatingTags.after, id) != null) continue;
                var played = Std.int(result.var_3302);
                var elo = Std.int(result.mRating);
                before.games = played > 0 ? played - 1 : 0;
                if (played >= Std.int(playlist.mPlacementGames) && elo > 0) {
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
        var board:Dynamic = ScreenManager.screenScoreboard;
        var cards:Dynamic = board != null ? board.mPodiums : null;
        if (cards == null) return 0;
        for (i in 0...Std.int(As3.getProp(cards, "length"))) {
            var entry:Dynamic = As3.index(cards, i);
            var result:Dynamic = entry != null ? entry.mPostgameData : null;
            if (result != null && result.var_14927 == me) return Std.int(result.mRating);
        }
        return 0;
    }

    public static function knownGames(ladder:String):Int {
        var n:Dynamic = Reflect.field(played, ladder);
        return n == null ? -1 : Std.int(n);
    }

    static function legendStats(core:Dynamic, p:MatchPreviewPlayer):Dynamic {
        if (p.var_2885 == null) return null;
        var id = Std.int(p.var_2885.var_12053) & 0xFFFF;
        if (id <= 0) return null;
        var table:Dynamic = core.mHeroRatingHash;
        var s:Dynamic = table != null && id < Std.int(As3.getProp(table, "length")) ? As3.index(table, id) : null;
        return s == null ? {id: id} : {id: id, rating: Std.int(s.mRating), wins: Std.int(s.var_15231), games: Std.int(s.mGames)};
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
