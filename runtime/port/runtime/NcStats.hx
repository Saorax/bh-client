package port.runtime;

class NcStats {
    public static var lobbyPingMs(default, null):Float = -1;
    public static var udpInPerSecond(default, null):Int = 0;
    public static var udpOutPerSecond(default, null):Int = 0;
    public static var udpLongestGapMs(default, null):Float = 0;
    public static var udpLastAt(default, null):Float = 0;

    static var keepAliveSentAt:Float = -1;
    static var windowStart:Float = 0;
    static var inCount = 0;
    static var outCount = 0;
    static var longestGap:Float = 0;

    static function roll(now:Float):Void {
        if (now - windowStart < 1) return;
        udpInPerSecond = inCount;
        udpOutPerSecond = outCount;
        udpLongestGapMs = longestGap * 1000;
        inCount = outCount = 0;
        longestGap = 0;
        windowStart = now;
    }

    public static function udpIn():Void {
        var now = haxe.Timer.stamp();
        roll(now);
        if (udpLastAt > 0 && now - udpLastAt > longestGap && now - udpLastAt < 5) longestGap = now - udpLastAt;
        udpLastAt = now;
        inCount++;
    }

    public static function udpOut(to:sys.net.Address):Void {
        roll(haxe.Timer.stamp());
        outCount++;
        if (to != null && to.host != serverHost) {
            serverHost = to.host;
            matchServer = "";
            lookUp(to.getHost().toString(), serverHost);
        }
    }

    public static var matchServer(default, null):String = "";
    static var serverHost:Int = 0;

    static final REGIONS = [
        "us-east-1" => "US-E (Virginia)", "us-east-2" => "US-E (Ohio)", "us-west-1" => "US-W (California)",
        "us-west-2" => "US-W (Oregon)", "eu-central-1" => "EU (Frankfurt)", "eu-west-1" => "EU (Ireland)",
        "eu-west-2" => "EU (London)", "eu-west-3" => "EU (Paris)", "sa-east-1" => "BRZ (Sao Paulo)",
        "ap-southeast-1" => "SEA (Singapore)", "ap-southeast-2" => "AUS (Sydney)", "ap-northeast-1" => "JPN (Tokyo)",
        "af-south-1" => "SA (Cape Town)", "me-south-1" => "ME (Bahrain)", "me-central-1" => "ME (UAE)"];

    static function regionOf(name:String, ip:String):String {
        if (name == null || name == "") return ip;
        if (StringTools.endsWith(name, ".compute-1.amazonaws.com")) return REGIONS["us-east-1"];
        for (code => label in REGIONS) if (name.indexOf("." + code + ".") >= 0) return label;
        return name;
    }

    static function lookUp(ip:String, host:Int):Void {
        sys.thread.Thread.create(function() {
            var name = try new sys.net.Host(ip).reverse() catch (_:Dynamic) "";
            if (serverHost != host) return;
            matchServer = regionOf(name, ip);
            NcLog.say("match server " + ip + ": " + matchServer + (name != "" ? " (" + name + ")" : ""));
        });
    }

    public static function tcpOut(bytes:haxe.io.Bytes, length:Int):Void {
        if (length == 4 && bytes.get(0) == 0x2f && bytes.get(1) == 0x44) keepAliveSentAt = haxe.Timer.stamp();
    }

    public static function tcpIn(bytes:haxe.io.Bytes, length:Int):Void {
        if (keepAliveSentAt < 0 || length < 4) return;
        for (i in 0...length - 3) {
            if (bytes.get(i) == 0x2f && bytes.get(i + 1) == 0x44 && bytes.get(i + 2) == 0 && bytes.get(i + 3) == 0) {
                lobbyPingMs = (haxe.Timer.stamp() - keepAliveSentAt) * 1000;
                keepAliveSentAt = -1;
                return;
            }
        }
    }

    public static function inMatch():Bool {
        return udpLastAt > 0 && haxe.Timer.stamp() - udpLastAt < 3;
    }
}
