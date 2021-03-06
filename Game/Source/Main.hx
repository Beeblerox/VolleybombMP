package;

import control.GameController;
import control.Physics;
import control.local.PVCController;
import control.local.PVPController;
import control.net.GuestController;
import control.net.HostController;
import display.PerfDisplay;
import display.StateBase;
import display.game.GameState;
import display.menu.MenuState;
import haxe.Timer;
import js.Browser;
import openfl.display.Sprite;
import openfl.events.Event;
import room.RoomConfig;

@:access(display.StateBase)
@:access(control.GameController)
class Main extends Sprite {
	
	public static var instance(default, null):Main;
	public static var mobile(default, null):Bool;
	
	//
	
	public var state(default, set):StateBase;
	public var controller(default, set):GameController;
	
	var perfDisplay:PerfDisplay;
	var prvFrameTime:Float;
	var deltaTime:Float;
	
	public function new() {
		super();
		
		instance = this;
		
		var md = untyped __js__('new MobileDetect(window.navigator.userAgent)');
		mobile = md.mobile() != null;
		
		R.init();
		Sound.init();
		MenuState.init();
		GameState.init();
		Physics.init();
		PVPController.init();
		PVCController.init();
		HostController.init();
		GuestController.init();
		
		prvFrameTime = Timer.stamp();
		state = MenuState.instance;
		
		perfDisplay = new PerfDisplay();
		stage.addChild(perfDisplay);
		
		addEventListener(Event.ENTER_FRAME, onEnterFrame);
		stage.addEventListener(Event.RESIZE, onStageResized);
		
		//
		
		Save.load();
		resolveInvitationURL();
	}
	
	function resolveInvitationURL():Void {
		var href = Browser.location.href;
		var roomID = href.split('?')[1];
		if (roomID != null)
			roomID = roomID.split(';')[0];
		if (roomID != null && roomID.length == RoomConfig.ID_LENGTH && ~/^[0-9]*$/i.match(roomID)) {
			MenuState.instance.guestDialog.show();
			MenuState.instance.guestDialog.join(roomID);
		}
	}
	
	public function startGame(controller:GameController):Void {
		this.controller = controller;
		state = GameState.instance;
		stage.focus = GameState.instance;
	}
	
	public inline function playAgain():Void {
		startGame(controller);
	}
	
	function onEnterFrame(event:Event):Void {
		var crFrameTime = Timer.stamp();
		deltaTime = crFrameTime - prvFrameTime;
		prvFrameTime = crFrameTime;
		state.update(deltaTime);
	}
	
	function onStageResized(event:Event):Void {
		state.onStageResize(stage.stageWidth, stage.stage.stageHeight);
	}
	
	function set_state(value:StateBase):StateBase {
		if (state != null) {
			removeChild(state);
			state.onDeactivated();
		}
		
		addChild(state = value);
		state.onActivated();
		state.onStageResize(stage.stageWidth, stage.stageHeight);
		
		return state;
	}
	
	function set_controller(value:GameController):GameController {
		if (controller != null && controller != value)
			controller.onDeactivated();
		
		controller = value;
		if (value != null)
			controller.onActivated();
		
		return controller;
	}
	
}