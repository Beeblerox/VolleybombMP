package net;

import haxe.Http;
import haxe.Json;
import haxe.Resource;
import haxe.Timer;
import haxe.ds.IntMap;
import openfl.utils.ByteArray;
import peer.Peer;
import peer.PeerEvent;
import peer.PeerOptions;

class Connection {
	
	public static var instance(default, null):Connection;
	
	//
	
	static inline var PING_HEADER = -120;
	static inline var PONG_HEADER = -121;
	
	public static function fetchIceServers(onSuccess:Dynamic->Void, ?onFailed:String->Void):Http {
		var http = new Http(Resource.getString('LobbyURL') + '/iceServers');
		http.onData = function(data:String) {
			onSuccess(Json.parse(data));
		};
		http.onError = function(error:String) {
			if (onFailed == null)
				trace(error);
			else
				onFailed(error);
		};
		http.request();
		return http;
	}
	
	//
	
	public var autoPing(default, null):Bool;
	public var pingTimeout:Float = 1; // in seconds
	public var onPingCB:Float->Void;
	public var lastLatency(default, null):Float = -1; // in seconds
	
	/**
		The minimum milliseconds to delay listeners to simulate latency for testing.
	**/
	public var minDelay:Int = 0;
	/**
		The maximum milliseconds to delay listeners to simulate latency for testing.
	**/
	public var maxDelay:Int = 0;
	
	public var rReady(default, null):Bool = false;
	public var uReady(default, null):Bool = false;
	public var destroyed(default, null):Bool = false;
	public var onDestroyedCB:Void->Void;
	
	/**
	   TCP-like channel.
	**/
	var r:Peer;
	/**
	   UDP-like channel.
	**/
	var u:Peer;
	
	var listeners:IntMap<ByteArray->Void> = new IntMap<ByteArray->Void>();
	
	public function new(offer:ConnectionSignal, iceServers:Dynamic, onSignalReady:ConnectionSignal->Void, onReady:Void->Void, autoPing:Bool = true) {
		var baseOptions:PeerOptions = {
			initiator: offer == null,
			trickle: false
		}
		if (iceServers != null) {
			baseOptions.config = { iceServers: iceServers };
			#if forceRelay
			baseOptions.config.iceTransportPolicy = "relay";
			#end
		}
		
		var rOptions = Reflect.copy(baseOptions);
		rOptions.channelName = 'reliable';
		
		var uOptions = Reflect.copy(baseOptions);
		uOptions.channelName = 'unreliable';
		uOptions.channelConfig = { ordered: false, maxRetransmits: 0 };
		
		r = new Peer(rOptions);
		r.on(PeerEvent.SIGNAL, function(rSignal) {
			u = new Peer(uOptions);
			u.on(PeerEvent.SIGNAL, function(uSignal) {
				onSignalReady({ r: rSignal, u: uSignal });
			});
			u.on(PeerEvent.CONNECT, function() {
				uReady = true;
				if (rReady && uReady) {
					instance = this;
					this.onReady();
					onReady();
				}
			});
			u.on(PeerEvent.DATA, onData);
			u.on(PeerEvent.CLOSE, onUClosed);
			u.on(PeerEvent.ERROR, onUErrror);
			if (offer != null)
				u.signal(offer.u);
		});
		r.on(PeerEvent.CONNECT, function() rReady = true);
		r.on(PeerEvent.DATA, onData);
		r.on(PeerEvent.CLOSE, onRClosed);
		r.on(PeerEvent.ERROR, onRError);
		if (offer != null)
			r.signal(offer.r);
		
		listen(PING_HEADER, onPing);
		listen(PONG_HEADER, onPong);
		
		this.autoPing = autoPing;
		
		#if (localTest && !forceRelay)
		minDelay = 90;
		maxDelay = 100;
		#end
	}
	
	public function signal(data:ConnectionSignal):Void {
		r.signal(data.r);
		u.signal(data.u);
	}
	
	public function destroy():Void {
		if (destroyed)
			return;
		
		r.destroy();
		u.destroy();
		r = u = null;
		
		onPingCB = null;
		for (key in listeners.keys())
			listeners.remove(key);
		
		if (instance == this)
			instance = null;
		
		if (onDestroyedCB != null) {
			onDestroyedCB();
			onDestroyedCB = null;
		}
		
		destroyed = true;
	}
	
	public inline function send(reliable:Bool, data:Dynamic):Void {
		(reliable ? r : u).send(data);
	}
	
	public function listen(header:Int, listener:ByteArray->Void):Void {
		if (listener == null)
			throw 'null listener';
		
		if (listeners.exists(header))
			throw 'This header ($header) is already added with another listener.';
		
		listeners.set(header, listener);
	}
	
	var _pingTimestamp:Float;
	var _pingTimer:Timer;
	public function ping():Void {
		_pingTimestamp = Timer.stamp();
		Sendable.n(PING_HEADER).send();
		_pingTimer = Timer.delay(ping, Math.round(pingTimeout * 1000));
	}
	
	function onReady():Void {
		if (autoPing)
			ping();
	}
	
	function onPing(bytes:ByteArray):Void {
		Sendable.n(PONG_HEADER).send();
	}
	
	function onPong(bytes:ByteArray):Void {
		lastLatency = Timer.stamp() - _pingTimestamp;
		if (onPingCB != null)
			onPingCB(lastLatency);
		
		if (autoPing)
			ping();
		
		if (_pingTimer != null) {
			_pingTimer.stop();
			_pingTimer = null;
		}
	}
	
	function onData(data:Dynamic):Void {
		var bytes = ByteArrayTools.fromArrayBuffer(data);
		var header = bytes.readByte();
		if (listeners.exists(header)) {
			var delay = Math.round(minDelay + Math.random() * (maxDelay - minDelay));
			if (delay <= 0)
				listeners.get(header)(bytes);
			else
				Timer.delay(function() listeners.get(header)(bytes), delay);
		} else {
			trace('Error: Received data with header ($header) without listener.');
		}
	}
	
	function onRClosed():Void {
		lastLatency = -1;
		
		rReady = false;
		if (!uReady)
			destroy();
	}
	
	function onUClosed():Void {
		uReady = false;
		if (!rReady)
			destroy();
	}
	
	function onRError(error:String):Void {
		trace(error);
	}
	
	function onUErrror(error:String):Void {
		trace(error);
	}
	
}