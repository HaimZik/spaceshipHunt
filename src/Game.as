package
{
	import flash.geom.Point;
	import flash.media.SoundChannel;
	import flash.media.SoundTransform;
	import input.Key;
	import io.arkeus.ouya.ControllerInput;
	import nape.geom.Vec2;
	import spaceshiptHunt.controls.PlayerController;
	import spaceshiptHunt.entities.Player;
	import spaceshiptHunt.level.Environment;
	import starling.core.Starling;
	import starling.display.Image;
	import starling.display.Mesh;
	import starling.display.Sprite;
	import starling.events.*;
	import starling.geom.Polygon;
	import starling.rendering.VertexData;
	import starling.utils.Color;
	import starling.utils.Pool;
	
	CONFIG::debug
	{
		import spaceshiptHuntDevelopment.level.LevelEditor;
	}
	
	/**
	 * ...
	 * @author Haim Shnitzer
	 */
	public class Game extends Sprite
	{
		private var joystickRadios:Number;
		private var joystick:Sprite;
		private var analogStick:Mesh;
		private var shootButton:Image;
		private var joystickPosition:Point;
		private var touches:Vector.<Touch> = new Vector.<Touch>();
		private var backgroundMusic:SoundChannel;
		private var volume:Number = 0.08;
		private var gameEnvironment:Environment;
		private var background:Image;
		private var player:Player;
		private var playerController:PlayerController;
		
		public function Game()
		{
			init();
		}
		
//-----------------------------------------------------------------------------------------------------------------------------------------
		//initialization functions		
		public function init():void
		{
			CONFIG::debug
			{
				gameEnvironment = new LevelEditor(this);
			}
			CONFIG::release
			{
				gameEnvironment = new Environment(this);
			}
			drawJoystick();
			gameEnvironment.enqueueLevel("Level1Test");
			var atlaseNum:int = 1;
			for (var i:int = 0; i < atlaseNum; i++)
			{
				Environment.current.assetsLoader.enqueue("grp/textureAtlases" + i + ".xml");
				Environment.current.assetsLoader.enqueue("grp/textureAtlases" + i + ".atf");
			}
			Environment.current.assetsLoader.enqueue("grp/concrete_baked.atf");
			Environment.current.assetsLoader.enqueue("grp/concrete_baked_n.atf");
			gameEnvironment.startLoading(onFinishLoading);
		}
		
		public function onFocusReturn():void
		{
			Key.reset();
		}
		
		private function onFinishLoading():void
		{
			shootButton = new Image(Environment.current.assetsLoader.getTexture("shootButton"));
			addChild(shootButton);
			shootButton.alignPivot();
			background = new Image(Environment.current.assetsLoader.getTexture("stars"));
			background.tileGrid = Pool.getRectangle();
			addChildAt(background, 0);
			var backgroundRatio:Number = Math.ceil(Math.sqrt(stage.stageHeight * stage.stageHeight + stage.stageWidth * stage.stageWidth) / 512) * 2;
			background.scale = backgroundRatio * 2;
			Key.init(stage);
			ControllerInput.initialize(Starling.current.nativeStage);
			player = Player.current;
			playerController = new PlayerController(Player.current,analogStick);
			addEventListener(Event.ENTER_FRAME, enterFrame);
			addEventListener(TouchEvent.TOUCH, onTouch);
			Starling.current.stage.addEventListener(Event.RESIZE, stage_resize);
			Environment.current.assetsLoader.enqueueWithName("audio/Nihilore.mp3", "music");
			Environment.current.assetsLoader.loadQueue(function onProgress(ratio:Number):void
			{
				if (ratio == 1.0)
				{
					backgroundMusic = Environment.current.assetsLoader.getSound("music").play(0, 7);
					backgroundMusic.soundTransform = new SoundTransform(volume);
				}
			})
			addChild(Environment.current.light);
			this.setChildIndex(joystick, this.numChildren);
			//	PhysicsParticle.fill.cache();
		}
		
		private function drawJoystick():void
		{
			joystick = new Sprite();
			joystickRadios = Math.min(550, Starling.current.stage.stageWidth, Starling.current.stage.stageHeight) / 4;
			var joystickShape:Polygon = Polygon.createCircle(0, 0, joystickRadios);
			joystickPosition = new Point(joystickRadios * 2.5, Starling.current.stage.stageHeight - 15);
			var vertices:VertexData = new VertexData(null, joystickShape.numVertices);
			joystickShape.copyToVertexData(vertices);
			var joystickBase:Mesh = new Mesh(vertices, joystickShape.triangulate());
			analogStick = new Mesh(vertices, joystickShape.triangulate());
			analogStick.alpha = joystickBase.alpha = 0.3;
			analogStick.color = joystickBase.color = Color.WHITE;
			joystick.x = joystickPosition.x;
			joystick.y = joystickPosition.y;
			joystick.addChild(joystickBase);
			analogStick.scale = 0.6;
			joystick.addChild(analogStick);
			addChild(joystick);
			joystick.pivotY = joystick.pivotX = joystickRadios;
		}
		
//-----------------------------------------------------------------------------------------------------------------------------------------
		//event functions	
		
		private function onTouch(e:TouchEvent):void
		{
			e.getTouches(this, null, touches);
			while (touches.length > 0)
			{
				var touch:Touch = touches.pop();
				if (touch.target.parent == joystick)
				{
					if (touch.phase == TouchPhase.MOVED || touch.phase == TouchPhase.BEGAN)
					{
						var position:Point = Pool.getPoint();
						touch.getLocation(joystick, position);
						if (position.length > joystickRadios * 1.2)
						{
							position.normalize(joystickRadios * 1.2);
						}
						analogStick.x = position.x;
						analogStick.y = position.y;
						Pool.putPoint(position);
					}
					else if (touch.phase == TouchPhase.ENDED)
					{
						analogStick.x = 0;
						analogStick.y = 0;
					}
				}
				else if (touch.target == shootButton)
				{
					if (touch.phase == TouchPhase.ENDED)
					{
						player.stopShooting();
					}
					else if (touch.phase == TouchPhase.BEGAN)
					{
						player.startShooting();
					}
				}
				else
				{
					CONFIG::debug
					{
						(gameEnvironment as LevelEditor).handleTouch(e);
					}
				}
			}
		}
		
		private function stage_resize(e:ResizeEvent = null):void
		{
			stage.stageWidth = e.width;
			stage.stageHeight = e.height;
			Starling.current.viewPort.width = e.width;
			Starling.current.viewPort.height = e.height;
			joystickRadios = int(Math.min(800, e.width, e.height) / 5);
			joystick.width = joystick.height = joystickRadios * 2;
			joystick.pivotX = joystick.pivotY = joystickRadios;
			joystickPosition.setTo(joystickRadios * 2 + 20, e.height - 15);
		}
		
//-----------------------------------------------------------------------------------------------------------------------------------------
		//runtime functions
		
		private function enterFrame(event:EnterFrameEvent, passedTime:Number):void
		{
			//Starling.current.juggler.advanceTime(event.passedTime);
			if (event.passedTime > 0.010)
			{
				gameEnvironment.updatePhysics(passedTime);
				playerController.update();
				moveCam();
			}
		}
		
		private function moveCam():void
		{
			this.pivotX = this.x - stage.stageWidth / 2;
			this.pivotY = this.y + stage.stageHeight / 2;
			this.rotation -= (this.rotation + player.body.rotation) - player.body.angularVel / 17;
			var velocity:Vec2 = player.body.velocity.copy(true).rotate(rotation).muleq(0.2);
			var newScale:Number = 1 - velocity.length * velocity.length / 30000;
			this.scale += (newScale - this.scale) / 16;
			var position:Point = Pool.getPoint(player.body.position.x, player.body.position.y);
			this.localToGlobal(position, position);
			this.x -= position.x - velocity.x - stage.stageWidth / 2;
			this.y -= position.y - velocity.y - stage.stageHeight * 0.7;
			velocity.dispose();
			var parallaxRatio:Number = 0.5;
			background.x = player.body.position.x - (player.body.position.x * parallaxRatio) % 512 - background.width / 2;
			background.y = player.body.position.y - (player.body.position.y * parallaxRatio) % 512 - background.height / 2;
			
			this.globalToLocal(joystickPosition, position);
			joystick.x = position.x;
			joystick.y = position.y;
			joystick.scale = shootButton.scale = 1 / this.scale;
			joystick.rotation = shootButton.rotation = -this.rotation;
			position.copyFrom(joystickPosition);
			var shootIconWidth:Number = shootButton.texture.width;
			position.x += stage.stageWidth - joystickRadios * 2 - shootIconWidth / 2 - 30;
			position.y -= shootIconWidth / 2 - 5;
			this.globalToLocal(position, position);
			shootButton.x = position.x;
			shootButton.y = position.y;
			Pool.putPoint(position);
		}
	
	}
}