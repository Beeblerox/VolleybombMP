package control.net;

import haxe.Http;
import haxe.Resource;
import js.node.socketio.Client;
import room.RoomAnswer;
import room.RoomEvent;

class Room {
	
	static var http:Http;
	static var socket:Client;
	static var roomID:String;
	
	public static function create(onRoom:String->Void, onOtherJoined:Connection->Void):Void {
		cancel();
		
		var onIceFetched = function(iceServers):Void {
			http = null;
			
			var con:Connection;
			con = new Connection(null, iceServers,
				function(offer) {
					socket = new Client(Resource.getString('ServerURL') + ':' + Port.SOCKET);
					socket.on(RoomEvent.ROOM, function(id) {
						roomID = id;
						onRoom(roomID);
					});
					socket.on(RoomEvent.ANSWER, function(answer) {
						con.signal(answer);
					});
					socket.emit(RoomEvent.CREATE, offer);
				},
				function (rReady, uReady) {
					if (rReady && uReady) {
						socket.disconnect();
						socket = null;
						roomID = null;
						onOtherJoined(con);
					}
				}
			);
		}
		http = Connection.fetchIceServers(onIceFetched);
	}
	
	public static function join(roomID:String, onSuccess:Connection->Void, ?onFailed:String->Void):Void {
		cancel();
		
		socket = new Client(Resource.getString('ServerURL') + ':' + Port.SOCKET);
		socket.on(RoomEvent.OFFER, function(offer) {
			var con:Connection;
			con = new Connection(offer, null,
				function(signal) {
					var answer:RoomAnswer = { roomID: roomID, signal: signal };
					socket.emit(RoomEvent.ANSWER, answer);
				},
				function(rReady, uReady) {
					if (rReady && uReady) {
						socket.disconnect();
						socket = null;
						onSuccess(con);
					}
				}
			);
		});
		socket.on(RoomEvent.NOT_EXIST, function() {
			if (onFailed != null)
				onFailed('Room $roomID does not exist.');
			else
				trace('Room $roomID does not exist.');
		});
		socket.emit(RoomEvent.JOIN, roomID);
	}
	
	public static function cancel():Void {
		if (http != null) {
			http.cancel();
			http = null;
		}
		
		if (socket != null) {
			socket.disconnect();
			socket = null;
		}
	}
	
}