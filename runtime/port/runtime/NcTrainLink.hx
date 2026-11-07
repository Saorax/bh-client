package port.runtime;

import bh.platform.net.P2PSession;
import bh.platform.net.PeerTraining;
import bh.platform.net.TrainingSync;

typedef Invite = {id:String, name:String, at:Float};

class NcTrainLink {
    static inline var CONTROL = 0;
    static inline var GAME = 1;
    static inline var PROTOCOL = 1;
    static inline var INVITE_MS = 30000.0;
    static inline var START_GRACE_MS = 5000.0;
    static inline var JOIN_MS = 15000.0;
    static inline var CLOSE_MS = 2000.0;
    static inline var PUMP_MS = 100.0;
    static inline var ACCEPT_MS = 1000.0;
    static inline var STEAM_OK = 1;
    static inline var LINK_CONNECTED = 3;
    static inline var LINK_CLOSED_BY_PEER = 4;
    static inline var LINK_PROBLEM = 5;

    static var opened = false;
    static var udp:sys.net.UdpSocket = null;
    static var udpPeer:sys.net.Address = null;
    static var udpRole = "";
    static var auto = false;
    static var autoDone = false;

    public static var partner:String = null;
    public static var partnerName = "";
    static var state = "idle";
    static var invitedAt = 0.0;
    static var startedAt = 0.0;
    static var joinedAt = 0.0;
    static var menuPaused = false;
    static var closing:Map<String, Float> = new Map();
    static var invites:Array<Invite> = [];
    static var friendCache:Array<{id:String, name:String, playing:Bool, online:Bool}> = [];
    static var friendsAt = -1e9;
    static var note = "";
    static var pumpedAt = -1e9;
    static var acceptedAt = -1e9;
    static var linkState = -1;
    static var linkUp = false;
    static var heard:Map<String, Bool> = new Map();
    static var incoming:Map<String, Int> = new Map();

    static function now():Float {
        return haxe.Timer.stamp() * 1000;
    }

    static function open():Void {
        if (opened) return;
        opened = true;
        auto = false;
        bh.platform.Hooks.pauseMenuPausing.add(pauseMenuOpened);
        bh.mods.lobbyscreen.TrainingSettingsScreen.online = window();
        var spec = Sys.getEnv("NC_TRAIN_UDP");
        if (spec != null && spec != "") {
            var parts = spec.split(":");
            try {
                udp = new sys.net.UdpSocket();
                udp.bind(new sys.net.Host("127.0.0.1"), Std.parseInt(parts[0]));
                udp.setBlocking(false);
                udpPeer = new sys.net.Address();
                udpPeer.host = new sys.net.Host("127.0.0.1").ip;
                udpPeer.port = Std.parseInt(parts[1]);
                udpRole = parts.length > 2 ? parts[2] : "";
                NcLog.say("online training: local UDP link " + spec);
                auto = Sys.getEnv("NC_TRAIN_AUTO") == "1";
            } catch (e:Dynamic) {
                udp = null;
                NcLog.say("online training: no local UDP link (" + e + ")");
            }
        }
    }

    static function sendRaw(channel:Int, data:haxe.io.Bytes):Int {
        if (partner == null) return -1;
        if (udp != null) {
            var out = haxe.io.Bytes.alloc(data.length + 1);
            out.set(0, channel);
            out.blit(1, data, 0, data.length);
            try udp.sendTo(out, 0, out.length, udpPeer) catch (_:Dynamic) {}
            return STEAM_OK;
        }
        return NcSteam.send(partner, data, channel, channel == CONTROL);
    }

    static function control(message:Dynamic, ?to:String):Int {
        var keep = partner;
        if (to != null) partner = to;
        message.v = PROTOCOL;
        var result = sendRaw(CONTROL, haxe.io.Bytes.ofString(haxe.Json.stringify(message)));
        if (result != STEAM_OK) NcLog.say("online training: sending " + message.t + " failed, Steam result " + result);
        partner = keep;
        return result;
    }

    static function received(from:String, channel:Int, data:haxe.io.Bytes):Void {
        if (channel == GAME) {
            if (state == "running" && from == partner) {
                var b = new flash.utils.ByteArray();
                for (i in 0...data.length) b.writeByte(data.get(i));
                b.position = 0;
                P2PSession.pipeReceived(b);
            }
            return;
        }
        var m:Dynamic = try haxe.Json.parse(data.toString()) catch (_:Dynamic) null;
        if (m == null) return;
        if (m.v != PROTOCOL) {
            NcLog.say("online training: " + from + " runs another version (protocol " + m.v + ")");
            if (m.t == "invite") control({t: "decline", why: "different Official versions"}, from);
            return;
        }
        switch (m.t) {
            case "invite":
                if (state != "idle") {
                    control({t: "decline", why: "busy"}, from);
                    closeSoon(from);
                    return;
                }
                invites = invites.filter(i -> i.id != from);
                invites.push({id: from, name: Std.string(m.name), at: now()});
                say(Std.string(m.name) + " invites you to online training: Training settings, Online Training tab");
                if (auto && udp != null) accept(from);
            case "cancel":
                invites = invites.filter(i -> i.id != from);
            case "decline":
                if (state == "inviting" && from == partner) {
                    say(partnerName + " declined" + (m.why != null ? " (" + m.why + ")" : ""));
                    reset();
                } else if (state == "accepting" && from == partner) {
                    say("Couldn't join " + partnerName + (m.why != null ? ": " + m.why : ""));
                    reset();
                }
            case "accept":
                if (state == "inviting" && from == partner) {
                    start(m.records);
                } else if (from != partner) {
                    control({t: "decline", why: "the invite expired"}, from);
                    closeSoon(from);
                }
            case "start":
                if (state == "accepting" && from == partner) begin(m.records, m.room, m.seed, m.level);
            case "map":
                if (state == "running" && from == partner) {
                    say(partnerName + " changed the map");
                    begin(m.records, m.room, m.seed, m.level);
                }
            case "bye":
                if (from == partner && state != "idle") {
                    say(partnerName + " left online training");
                    reset();
                }
        }
    }

    static function poll():Void {
        if (udp != null) {
            var buf = haxe.io.Bytes.alloc(4096);
            var from = new sys.net.Address();
            for (_ in 0...256) {
                var n = try udp.readFrom(buf, 0, buf.length, from) catch (_:Dynamic) -1;
                if (n <= 0) break;
                if (partner == null && udpRole != "") partner = "udp";
                received("udp", buf.get(0), buf.sub(1, n - 1));
            }
            return;
        }
        if (!NcSteam.open()) return;
        var at = now();
        if (at - pumpedAt >= PUMP_MS) {
            pumpedAt = at;
            NcSteam.pump();
            watchLink();
        }
        var id:String;
        while ((id = NcSteam.request()) != null) {
            NcLog.say("online training: Steam asked about a link from " + friendName(id) + ", state " + state);
            if (isFriend(id)) {
                var accepted = NcSteam.accept(id);
                heardFrom(id, "Steam's request, accepted " + accepted);
            } else {
                NcSteam.close(id);
                NcLog.say("online training: refused a link from someone not on your friends list (" + friendCache.length + " friends known)");
            }
        }
        if (at - acceptedAt >= ACCEPT_MS) {
            acceptedAt = at;
            for (f in friends(true)) if (f.id != partner && NcSteam.accept(f.id)) heardFrom(f.id, "found by checking friends");
        }
        for (channel in [CONTROL, GAME]) {
            for (_ in 0...256) {
                var m = NcSteam.receive(channel);
                if (m == null) break;
                received(m.from, channel, m.data);
            }
        }
    }

    static function heardFrom(id:String, how:String):Void {
        if (heard.exists(id)) return;
        heard.set(id, true);
        for (f in friendCache) if (f.id == id) NcLog.say("online training: Steam link from " + f.name + " (" + how + ")");
    }

    static function linkName(state:Int):String {
        return switch (state) {
            case 0: "none";
            case 1: "connecting";
            case 2: "finding a route";
            case 3: "connected";
            case 4: "closed by them";
            case 5: "problem on this PC";
            default: "state " + state;
        }
    }

    static function friendName(id:String):String {
        for (f in friendCache) if (f.id == id) return f.name;
        return "someone";
    }

    static function watchIncoming():Void {
        for (id in heard.keys()) {
            if (id == partner) continue;
            var current = NcSteam.connection(id);
            if (incoming.get(id) == current) continue;
            incoming.set(id, current);
            NcLog.say("online training: Steam link from " + friendName(id) + ": " + linkName(current) + " [" + NcSteam.link(id) + "]; " + NcSteam.status());
        }
    }

    static function watchLink():Void {
        if (udp != null) return;
        watchIncoming();
        if (partner == null) return;
        var current = NcSteam.connection(partner);
        if (current == linkState) return;
        linkState = current;
        if (current == LINK_CONNECTED) linkUp = true;
        var broken = current == LINK_CLOSED_BY_PEER || current == LINK_PROBLEM;
        NcLog.say("online training: Steam link to " + partnerName + ": " + linkName(current)
            + (broken ? " [" + NcSteam.link(partner) + "]; " + NcSteam.status() : ""));
        if (broken && state == "inviting") {
            say("Couldn't reach " + partnerName + ": they need the latest Official open");
            reset();
        }
    }

    public static function tick():Void {
        try step() catch (e:Dynamic) NcLog.say("online training: " + e + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
    }

    static function step():Void {
        open();
        if (state == "idle") PeerTraining.stopIfIdle();
        try poll() catch (e:Dynamic) NcLog.say("online training: " + e);
        if (state == "inviting" && now() - invitedAt > INVITE_MS) {
            say(udp != null || linkUp ? partnerName + " didn't answer"
                : "Couldn't reach " + partnerName + ": they need Official open, on the same version");
            control({t: "cancel"});
            reset();
            autoDone = false;
        }
        if (state == "accepting" && now() - joinedAt > JOIN_MS) {
            say(partnerName + " didn't start the training: the invite may have expired");
            reset();
        }
        var live = invites.filter(i -> now() - i.at < INVITE_MS);
        if (live.length != invites.length) invites = live;
        closeDue();
        watchPauseMenu();
        if (state == "leaving") leaving();
        if (state == "running" && now() - startedAt > START_GRACE_MS && !bh.platform.OnlineTraining.active) {
            control({t: "bye"});
            say("online training ended");
            reset();
        }
        if (udp != null && PeerTraining.notReady() == null) PeerTraining.offlineId(udpRole == "host" ? 1 : 2);
        if (auto && udp != null && !autoDone && udpRole == "host" && state == "idle" && PeerTraining.notReady() == null) {
            autoDone = true;
            partner = "udp";
            invite("udp", "local test");
        }
        if (auto && udp != null && state == "idle" && invites.length > 0 && PeerTraining.notReady() == null) accept(invites[0].id);
    }

    public static function report():String {
        var line = state + " with " + (partnerName == "" ? "-" : partnerName) + ", invites " + invites.length + "; "
            + PeerTraining.describe();
        if (P2PSession.pipe != null)
            line += "; P2P " + P2PSession.pathName + ", ping " + P2PSession.ping + ", delay " + P2PSession.inputDelay
                + ", rollbacks " + P2PSession.rollbackCount + ", deepest " + P2PSession.deepestRollback + ", waits "
                + P2PSession.waitCount + (P2PSession.peerLost ? ", peer lost" : "");
        NcLog.say("online training report: " + line);
        return line;
    }

    static function isFriend(id:String):Bool {
        for (f in friends(false)) if (f.id == id) return true;
        return false;
    }

    static function friends(playingOnly:Bool):Array<{id:String, name:String, playing:Bool, online:Bool}> {
        if (now() - friendsAt > 5000) {
            friendsAt = now();
            friendCache = NcSteam.friends();
        }
        return playingOnly ? friendCache.filter(f -> f.playing) : friendCache;
    }

    static function myName():String {
        var me = udp != null ? null : NcSteam.me();
        return me != null && me.name != "" ? me.name : "Player " + PeerTraining.myId();
    }

    public static function invite(id:String, name:String):Void {
        if (state != "idle") return;
        var why = PeerTraining.notReady();
        if (why != null) {
            say("Can't invite: " + why);
            return;
        }
        partner = id;
        partnerName = name;
        state = "inviting";
        invitedAt = now();
        var sent = control({t: "invite", name: myName()});
        if (sent != STEAM_OK) {
            say("Couldn't send the invite to " + name + " (Steam result " + sent + ")");
            reset();
            return;
        }
        NcLog.say("online training: Steam at invite: " + (udp != null ? "local link" : NcSteam.status()));
        say("Invited " + name + " to online training");
    }

    public static function accept(id:String):Void {
        var why = PeerTraining.notReady();
        var from = invites.filter(i -> i.id == id);
        if (from.length == 0) return;
        if (why != null) {
            say("Can't accept yet: " + why);
            return;
        }
        invites = invites.filter(i -> i.id != id);
        partner = id;
        partnerName = from[0].name;
        state = "accepting";
        joinedAt = now();
        var mine = PeerTraining.localRecords(null).filter((r:Dynamic) -> Std.int(r[0]) != 3);
        control({t: "accept", records: mine});
        say("Joining " + partnerName + "'s online training...");
    }

    public static function decline(id:String):Void {
        invites = invites.filter(i -> i.id != id);
        control({t: "decline"}, id);
        closeSoon(id);
    }

    public static function cancel():Void {
        NcLog.say("online training: cancelled while " + state + " with " + partnerName);
        if (state == "inviting") control({t: "cancel"});
        reset();
    }

    static function start(guest:Array<Dynamic>):Void {
        var local:Array<Dynamic> = PeerTraining.localRecords(null);
        var mine = local.filter((r:Dynamic) -> Std.int(r[0]) != 3);
        var bots = local.filter((r:Dynamic) -> Std.int(r[0]) == 3);
        if (mine.length != 1 || guest == null || guest.length != 1) {
            say("Online training couldn't start (players don't match)");
            control({t: "decline", why: "players don't match"});
            reset();
            return;
        }
        var records = mine.concat(guest).concat(bots);
        var room = 1 + Std.random(0x3FFFFFFF);
        var seed = Std.random(0x3FFFFFFF);
        var level = PeerTraining.levelId();
        control({t: "start", records: records, room: room, seed: seed, level: level});
        begin(records, room, seed, level);
    }

    static function begin(records:Array<Dynamic>, room:Dynamic, seed:Dynamic, level:Dynamic):Void {
        pending = {records: records, room: Std.int(room), seed: Std.int(seed), level: Std.int(level)};
        state = "leaving";
        leftAt = now();
        outAt = -1;
        PeerTraining.leaveMatch();
    }

    static var pending:Dynamic = null;
    static var leftAt = 0.0;
    static var outAt = -1.0;

    static function leaving():Void {
        if (PeerTraining.inMatch()) {
            outAt = -1;
            if (now() - leftAt > 15000) {
                fail("the Training match didn't close");
            } else if (Std.int(now() - leftAt) % 1500 < 20) {
                PeerTraining.leaveMatch();
            }
            return;
        }
        if (outAt < 0) outAt = now();
        if (now() - outAt < 500) return;
        P2PSession.register();
        P2PSession.pipe = {name: udp != null ? "local link" : "Steam", send: sendGame};
        state = "running";
        startedAt = now();
        try {
            PeerTraining.apply(null, pending.records);
            if (!PeerTraining.launch(null, pending.room, pending.seed, pending.level)) throw "the level isn't known";
            say("Online training with " + partnerName);
        } catch (e:Dynamic) {
            NcLog.say("online training: could not start: " + e + haxe.CallStack.toString(haxe.CallStack.exceptionStack()));
            fail("it couldn't start");
        }
        pending = null;
    }

    static function fail(why:String):Void {
        say("Online training stopped: " + why);
        control({t: "bye"});
        reset();
    }


    static function sendGame(id:Dynamic, body:flash.utils.ByteArray):Void {
        var at = body.position;
        body.position = 0;
        var out = haxe.io.Bytes.alloc(body.length);
        for (i in 0...body.length) out.set(i, body.readUnsignedByte());
        body.position = at;
        sendRaw(GAME, out);
    }

    static function reset():Void {
        if (partner != null && udp == null) NcLog.say("online training: closing the Steam link to " + partnerName + " [" + NcSteam.link(partner) + "]");
        if (P2PSession.pipe != null && !bh.platform.OnlineTraining.active) P2PSession.pipe = null;
        if (partner != null) closeSoon(partner);
        state = "idle";
        partner = null;
        partnerName = "";
        linkState = -1;
        linkUp = false;
        heard = new Map();
        incoming = new Map();
        menuPaused = false;
    }

    static function pauseMenuOpened(core:Dynamic):Bool {
        if (state != "running" || !TrainingSync.usable) return false;
        if (!TrainingSync.paused) {
            TrainingSync.pauseKey(core, "F7", 0);
            menuPaused = TrainingSync.paused;
            NcLog.say("online training: pause menu opened, " + (menuPaused ? "paused for both" : "the pause didn't take"));
        }
        return true;
    }

    static function watchPauseMenu():Void {
        if (!menuPaused) return;
        var menu:Dynamic = ScreenManager.var_4794;
        if (menu != null && menu.isActive) return;
        menuPaused = false;
        if (state != "running" || !TrainingSync.usable || !TrainingSync.paused) return;
        var app:Dynamic = GameApp.mainInstance;
        TrainingSync.pauseKey(app.game, "F7", 0);
        NcLog.say("online training: pause menu closed, playing again");
    }

    static function closeSoon(id:String):Void {
        if (udp == null) closing.set(id, now() + CLOSE_MS);
    }

    static function closeDue():Void {
        var due = [for (id => at in closing) if (now() >= at) id];
        for (id in due) {
            closing.remove(id);
            if (id != partner) NcSteam.close(id);
        }
    }

    static function say(text:String):Void {
        note = text;
        NcLog.say("online training: " + text);
        try bh.platform.DummyDrift.show(text, 4000) catch (_:Dynamic) {}
    }

    public static function signature():String {
        return state + "|" + partnerName + "|" + invites.length + "|" + friends(true).length + "|" + note;
    }

    static var avatars:Map<String, flash.display.BitmapData> = new Map();
    static var avatarAsked:Map<String, Float> = new Map();

    static function avatar(id:String):flash.display.BitmapData {
        if (avatars.exists(id)) return avatars.get(id);
        if (udp != null || (avatarAsked.exists(id) && now() - avatarAsked.get(id) < 2000)) return null;
        avatarAsked.set(id, now());
        var a = NcSteam.avatar(id);
        if (a == null) return null;
        var bd = new flash.display.BitmapData(a.width, a.height, true, 0);
        for (y in 0...a.height) for (x in 0...a.width) {
            var i = (y * a.width + x) * 4;
            bd.setPixel32(x, y, (a.rgba.get(i + 3) << 24) | (a.rgba.get(i) << 16) | (a.rgba.get(i + 1) << 8) | a.rgba.get(i + 2));
        }
        avatars.set(id, bd);
        return bd;
    }

    static var provider:Dynamic = null;

    static function window():Dynamic {
        if (provider == null) provider = {
            friends: function():Array<Dynamic> {
                var list:Array<Dynamic> = [];
                for (f in friends(false)) if (f.playing || f.online)
                    list.push({id: f.id, name: f.name, playing: f.playing, online: f.online, avatar: avatar(f.id)});
                if (udp != null) list.push({id: "udp", name: "Local test", playing: true, online: true, avatar: null});
                return list;
            },
            incoming: function():Array<Dynamic> {
                return [for (i in invites) ({id: i.id, name: i.name, avatar: avatar(i.id)} : Dynamic)];
            },
            state: function():String return state,
            partner: function():String return partner,
            note: function():String return note,
            signature: function():String {
                var s = signature() + "|" + PeerTraining.currentMap();
                for (f in friendCache) s += avatars.exists(f.id) ? "a" : "-";
                return s;
            },
            invite: function(id:String, name:String):Void invite(id, name),
            cancel: function():Void cancel(),
            accept: function(id:String):Void accept(id),
            decline: function(id:String):Void decline(id),
            maps: function():Array<Dynamic> return state == "running" ? PeerTraining.maps() : [],
            currentMap: function():String return PeerTraining.currentMap(),
            pickMap: function(level:Dynamic):Void pickMap(Std.int(level))
        };
        return provider;
    }

    public static function pickMap(level:Int):Void {
        if (state != "running") return;
        var records:Array<Dynamic> = PeerTraining.currentRecords();
        var room = 1 + Std.random(0x3FFFFFFF);
        var seed = Std.random(0x3FFFFFFF);
        control({t: "map", records: records, room: room, seed: seed, level: level});
        say("Changing the map...");
        begin(records, room, seed, level);
    }

    public static function openWindow():Void {
        open();
        bh.mods.lobbyscreen.TrainingSettingsScreen.openOnline();
    }
}
