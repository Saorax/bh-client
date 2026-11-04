package port.runtime.services;

import port.runtime.NcStats;
import haxe.io.Bytes;

class UdpEndpoint {
    public var bound(default, null):Bool = false;
    public var connected(default, null):Bool = false;
    public var receiving(default, null):Bool = false;
    public var localAddress(default, null):String = null;
    public var localPort(default, null):Int = 0;
    public var remoteAddress(default, null):String = null;
    public var remotePort(default, null):Int = 0;

    var closed:Bool = false;
    #if (hl || cpp || neko)
    var socket:Null<sys.net.UdpSocket> = null;
    var remote:Null<sys.net.Address> = null;
    var chunk:Bytes = Bytes.alloc(65536);
    #end

    public function new() {}

    public static var supported(get, never):Bool;

    static function get_supported():Bool {
        #if (hl || cpp || neko)
        return true;
        #else
        return false;
        #end
    }

    public function bind(port:Int = 0, address:String = "0.0.0.0"):Void {
        if (closed || bound) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        if (port < 0 || port > 65535) throw new ServiceError(2003, "Invalid socket port number specified.");
        #if (hl || cpp || neko)
        var s = new sys.net.UdpSocket();
        try {
            s.bind(new sys.net.Host(address), port);
        } catch (e:Dynamic) {
            try s.close() catch (_:Dynamic) {}
            throw new ServiceError(2031, "Socket Error: cannot bind " + address + ":" + port);
        }
        socket = s;
        bound = true;
        var info = s.host();
        localAddress = info.host.toString();
        localPort = info.port;
        #else
        throw new ServiceError(2031, "Socket Error: UDP is not available on this target");
        #end
    }

    public function connect(address:String, port:Int):Void {
        if (closed) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        if (port <= 0 || port > 65535) throw new ServiceError(2003, "Invalid socket port number specified.");
        if (!bound) bind(0, "0.0.0.0");
        #if (hl || cpp || neko)
        remote = new sys.net.Address();
        remote.host = new sys.net.Host(address).ip;
        remote.port = port;
        remoteAddress = address;
        remotePort = port;
        connected = true;
        #end
    }

    public function receive():Void {
        if (closed || !bound) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        receiving = true;
    }

    public function send(bytes:Bytes, offset:Int = 0, length:Int = 0, address:String = null, port:Int = 0):Void {
        if (closed) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        if (length == 0) length = bytes.length - offset;
        if (offset < 0 || length < 0 || offset + length > bytes.length)
            throw new ServiceError(2006, "The supplied index is out of bounds.");
        if (connected && address != null) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        if (!connected && address == null) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        if (!bound) bind(0, "0.0.0.0");
        #if (hl || cpp || neko)
        var to = remote;
        if (!connected) {
            to = new sys.net.Address();
            to.host = new sys.net.Host(address).ip;
            to.port = port;
        }
        try {
            socket.sendTo(bytes, offset, length, to);
            NcStats.udpOut(to);
        } catch (e:Dynamic) {
            throw new ServiceError(2031, "Socket Error: send failed");
        }
        #end
    }

    public function poll():Array<Datagram> {
        var out:Array<Datagram> = [];
        #if (hl || cpp || neko)
        if (!receiving || closed || socket == null) return out;
        var from = new sys.net.Address();
        while (true) {
            var ready = try sys.net.Socket.select([socket], null, null, 0).read.length > 0 catch (_:Dynamic) false;
            if (!ready) break;
            var n = try socket.readFrom(chunk, 0, chunk.length, from) catch (_:Dynamic) -1;
            if (n < 0) break;
            if (connected && (from.host != remote.host || from.port != remote.port)) continue;
            var host = from.getHost();
            out.push({data: chunk.sub(0, n), address: host.toString(), port: from.port});
            NcStats.udpIn();
        }
        #end
        return out;
    }

    public function close():Void {
        if (closed) throw new ServiceError(2002, "Operation attempted on invalid socket.");
        closed = true;
        bound = connected = receiving = false;
        #if (hl || cpp || neko)
        if (socket != null) {
            try socket.close() catch (_:Dynamic) {}
            socket = null;
        }
        #end
    }
}

typedef Datagram = {data:Bytes, address:String, port:Int};
