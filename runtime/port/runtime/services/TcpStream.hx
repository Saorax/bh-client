package port.runtime.services;

import haxe.io.Bytes;

class TcpStream {
    public var connected(default, null):Bool = false;
    public var timeout:Int = 20000;
    public var input(default, null):DataBuffer;
    public var output(default, null):DataBuffer;

    public var tls:Bool = false;
    public var tlsName:Null<String> = null;
    public var tlsStatus(default, null):String = "unknown";

    #if sys
    var socket:Null<sys.net.Socket> = null;
    #end
    #if (sys && hl)
    public var tlsCa:Null<sys.ssl.Certificate> = null;
    var secure:Bool = false;
    #end
    var events:Array<SocketEvent> = [];
    var chunk:Bytes = Bytes.alloc(65536);

    public function new() {
        input = new DataBuffer();
        output = new GuardedBuffer(this);
    }

    public function connect(host:String, port:Int):Void {
        if (connected) shut();
        input.clear();
        output.clear();
        if (port <= 0 || port > 65535) throw new ServiceError(2003, "Invalid socket port number specified.");
        #if (sys && hl)
        if (tls) {
            connectTls(host, port);
            return;
        }
        #end
        #if sys
        var s = new sys.net.Socket();
        try {
            s.setTimeout(timeout / 1000);
            s.connect(new sys.net.Host(host), port);
            s.setFastSend(true);
            socket = s;
            connected = true;
            events.push(Connected);
        } catch (e:Dynamic) {
            try s.close() catch (_:Dynamic) {}
            events.push(IoError("Error #2031: Socket Error. URL: " + host));
        }
        #else
        events.push(IoError("Error #2031: Socket Error. URL: " + host));
        #end
    }

    #if (sys && hl)
    function connectTls(host:String, port:Int):Void {
        var s = new sys.ssl.Socket();
        try {
            s.verifyCert = true;
            if (tlsCa != null) s.setCA(tlsCa);
            s.setHostname(tlsName != null ? tlsName : host);
            s.setTimeout(timeout / 1000);
            s.connect(new sys.net.Host(host), port);
            s.setFastSend(true);
            s.setBlocking(false);
            socket = s;
            secure = true;
            connected = true;
            tlsStatus = "valid";
            events.push(Connected);
        } catch (e:Dynamic) {
            try s.close() catch (_:Dynamic) {}
            tlsStatus = "invalid";
            events.push(IoError("Error #2031: Socket Error. URL: " + host));
        }
    }

    function readTls():Int {
        var received = 0;
        while (true) {
            var n = try socket.input.readBytes(chunk, 0, chunk.length) catch (e:haxe.io.Eof) {
                tlsEof = true;
                0;
            } catch (e:haxe.io.Error) {
                if (e != haxe.io.Error.Blocked) throw e;
                0;
            }
            if (n <= 0) return received;
            input.append(chunk, 0, n);
            received += n;
        }
    }

    var tlsEof:Bool = false;
    #end

    static function wire(what:String, bytes:Bytes, n:Int):Void {
        if (!Wire.on) return;
        port.runtime.NcLog.say("wire " + what + " " + n + " " + bytes.sub(0, n < 64 ? n : 64).toHex());
    }

    public function poll():Array<SocketEvent> {
        #if sys
        if (connected && socket != null) {
            input.compact();
            var received = 0;
            try {
                #if hl
                if (secure) {
                    received = readTls();
                    if (tlsEof) throw new haxe.io.Eof();
                } else
                #end
                while (sys.net.Socket.select([socket], null, null, 0).read.length > 0) {
                    var n = socket.input.readBytes(chunk, 0, chunk.length);
                    if (n <= 0) break;
                    wire("in", chunk, n);
                    port.runtime.NcStats.tcpIn(chunk, n);
                    input.append(chunk, 0, n);
                    received += n;
                }
            } catch (e:Dynamic) {
                if (received > 0) events.push(Data(received));
                received = 0;
                shut();
                events.push(Closed);
            }
            if (received > 0) events.push(Data(received));
        }
        #end
        var out = events;
        events = [];
        return out;
    }

    public function flush():Void {
        if (!connected) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        if (output.length == 0) return;
        #if sys
        try {
            #if hl
            if (secure) socket.setBlocking(true);
            #end
            wire("out", output.contents(), output.length);
            port.runtime.NcStats.tcpOut(output.contents(), output.length);
            socket.output.writeFullBytes(output.contents(), 0, output.length);
            socket.output.flush();
            #if hl
            if (secure) socket.setBlocking(false);
            #end
        } catch (e:Dynamic) {
            output.clear();
            shut();
            events.push(Closed);
            return;
        }
        #end
        output.clear();
    }

    public function close():Void {
        if (!connected) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        shut();
    }

    function shut():Void {
        connected = false;
        #if (sys && hl)
        secure = false;
        tlsEof = false;
        #end
        #if sys
        if (socket != null) {
            try socket.close() catch (_:Dynamic) {}
            socket = null;
        }
        #end
    }
}

private class Wire {
    public static var on = #if sys Sys.getEnv("NC_WIRE") == "1" #else false #end;
}

enum SocketEvent {
    Connected;
    Data(bytes:Int);
    Closed;
    IoError(text:String);
}

private class GuardedBuffer extends DataBuffer {
    var owner:TcpStream;

    public function new(owner:TcpStream) {
        super();
        this.owner = owner;
    }

    override function room(n:Int):Void {
        if (!owner.connected) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        super.room(n);
    }
}
