package ufront.app;

#if macro
	import haxe.macro.Expr;
#else
	import thx.core.error.NullArgument;
	import ufront.app.HttpApplication;
	import haxe.ds.StringMap;
	import minject.Injector;
	import haxe.web.Dispatch.DispatchConfig;
	import ufront.log.*;
	import ufront.api.UFApiContext;
	import ufront.handler.*;
	import ufront.view.TemplatingEngines;
	import ufront.view.UFViewEngine;
	import ufront.web.context.HttpContext;
	import ufront.web.Dispatch;
	import ufront.web.session.*;
	import ufront.web.url.filter.*;
	import ufront.web.Controller;
	import ufront.web.UfrontConfiguration;
	import ufront.web.session.UFHttpSession;
	import ufront.auth.*;
	import ufront.api.UFApi;
	#if ufront_easyauth
		import ufront.auth.EasyAuth;
	#end
	using Objects;
#end

/**
	Similar to `ufront.app.UfrontApplication`, but uses `DispatchHandler` instead of `RoutingHandler`.

	This is flagged for possible deprecation, please consider using `UfrontApplication` instead.

	@author Jason O'Neil
	@author Andreas Soderlund
	@author Franco Ponticelli
**/
@:deprecated
class DispatchApplication extends HttpApplication
{
	#if !macro

		/**
			The configuration that was used when setting up the application.

			This is set during the constructor.  Changing values of this object is not guaranteed to have any effect.
		**/
		public var configuration(default,null):UfrontConfiguration;

		/**
			The dispatch handler used for this application.

			This is mostly made accessible for unit testing and logging purposes.  You are unlikely to need to access it for anything else.
		**/
		public var dispatchHandler(default,null):DispatchHandler;

		/**
			The remoting handler used for this application.

			It is automatically set up if a `UFApiContext` class is supplied
		**/
		public var remotingHandler(default,null):RemotingHandler;

		/**
			The view engine being used with this application

			It is configured using the `viewEngine` property on your `UfrontConfiguration`.
		**/
		public var viewEngine(default,null):UFViewEngine;

		/**
			Initialize a new UfrontApplication with the given configurations.

			@param	?optionsIn		Options for UfrontApplication.  See `DefaultUfrontConfiguration` for details.  Any missing values will imply defaults should be used.

			Example usage:

			```
			var routes = new MyRoutes();
			var dispatchConfig = ufront.web.Dispatch.make( routes );
			var configuration = new UfrontConfiguration(false);
			var ufrontApp = new UfrontApplication({
				dispatchConfig: Dispatch.make( new MyRoutes() );
			} , configuration, myapp.Api );
			ufrontApp.execute();
			```

			This will redirect `haxe.Log.trace` to a local function which adds trace messages to the `messages` property of this application.  You will need to use an appropriate tracing module to view these.
		**/
		public function new( ?optionsIn:UfrontConfiguration ) {
			super();

			configuration = DefaultUfrontConfiguration.get();
			configuration.merge( optionsIn );

			dispatchHandler = new DispatchHandler();
			remotingHandler = new RemotingHandler();

			// Map some default injector rules

			for ( controller in configuration.controllers )
				dispatchHandler.injector.mapClass( controller, controller );

			for ( api in configuration.apis ) {
				injector.mapClass( api, api );
				dispatchHandler.injector.mapClass( api, api );
			}

			// Set up handlers and middleware
			addRequestMiddleware( configuration.requestMiddleware );
			addRequestHandler( [remotingHandler,dispatchHandler] );
			addResponseMiddleware( configuration.responseMiddleware );
			addErrorHandler( configuration.errorHandlers );

			// Add log handlers according to configuration
			if ( !configuration.disableBrowserTrace ) {
				addLogHandler( new BrowserConsoleLogger() );
				addLogHandler( new RemotingLogger() );
			}
			if ( null!=configuration.logFile ) {
				addLogHandler( new FileLogger(configuration.logFile) );
			}

			// Add URL filter for basePath, if it is not "/"
			var path = Strings.trim( configuration.basePath, "/" );
			if ( path.length>0 )
				super.addUrlFilter( new DirectoryUrlFilter(path) );

			// Unless mod_rewrite is used, filter out index.php/index.n from the urls.
			if ( configuration.urlRewrite!=true )
				super.addUrlFilter( new PathInfoUrlFilter() );

			// Save the session / auth factories for later, when we're building requests
			inject( UFHttpSession, configuration.sessionImplementation );
			inject( UFAuthHandler, configuration.authImplementation );
		}

		/**
			Execute the current request.

			The first time this runs, `initOnFirstExecute()` will be called, which runs some more initialization that requires the HttpContext to be ready before running.
		**/
		override public function execute( httpContext:HttpContext ) {
			NullArgument.throwIfNull( httpContext );

			if ( firstRun ) initOnFirstExecute( httpContext );

			// execute
			return super.execute( httpContext );
		}

		static var firstRun = true;
		function initOnFirstExecute( httpContext:HttpContext ) {
			firstRun = false;

			inject( String, httpContext.request.scriptDirectory, "scriptDirectory" );
			inject( String, httpContext.contentDirectory, "contentDirectory" );

			// Make the UFViewEngine available (and inject into it, in case it needs anything)
			try
				viewEngine = injector.getInstance( configuration.viewEngine )
			catch (e:Dynamic)
				httpContext.ufWarn( 'Failed to load view engine: $viewEngine' );
			inject( UFViewEngine, viewEngine );
			inject( String, configuration.viewPath, "viewPath" );
		}

		/**
			Shortcut for `remotingHandler.loadApi()`

			Returns itself so chaining is enabled
		**/
		public inline function loadApi( apiContext:Class<UFApiContext> ) {
			remotingHandler.loadApi( apiContext );
			return this;
		}

		/**
			Shortcut for `dispatchHandler.loadApi()`

			Returns itself so chaining is enabled
		**/
		public inline function loadRoutesConfig( dispatchConfig:DispatchConfig ) {
			dispatchHandler.loadRoutesConfig( dispatchConfig );
			return this;
		}

		/**
			Add support for a templating engine to your view engine.

			Some ready-to-go templating engines are included `ufront.view.TemplatingEngines`.
		**/
		public inline function addTemplatingEngine( engine:TemplatingEngine ) {
			viewEngine.addTemplatingEngine( engine );
			return this;
		}

		override public function inject<T>( cl:Class<T>, ?val:T, ?cl2:Class<T>, ?singleton=false, ?named:String ):DispatchApplication {
			return cast super.inject( cl, val, cl2, singleton, named );
		}

	#else
		/**
			Shortcut for `dispatchHandler.loadRoutes()`

			Returns itself so chaining is enabled
		**/
			macro public function loadRoutes( ethis:Expr, obj:ExprOf<{}> ):ExprOf<DispatchApplication> {
				var dispatchConf:Expr = ufront.web.Dispatch.makeConfig( obj );
				return macro $ethis.loadRoutesConfig( $dispatchConf );
			}
	#end
}
