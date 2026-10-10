unit WebModuleU;

interface

uses
  System.Classes,
  System.SysUtils,
  Web.HTTPApp,
  MVCFramework;

type

{ TDemoWebModule }

  TDemoWebModule = class(TWebModule)
    procedure WebModuleCreate(Sender: TObject);
    procedure WebModuleDestroy(Sender: TObject);
  private
    FEngine: TMVCEngine;
  end;

var
  WebModuleClass: TComponentClass = TDemoWebModule;

implementation

{$R *.dfm}

uses
  System.IOUtils,
  MVCFramework.Commons,
  MVCFramework.Middleware.StaticFiles,
  ChaosControllerU,
  ChaosMiddlewareU,
  ShopControllerU;

function DashboardFolder: string;
begin
  // Next to the executable, or in the project folder when the executable
  // is in the output folder of the IDE (e.g. Win32\Debug).
  Result := TPath.Combine(AppPath, 'www');
  if not TDirectory.Exists(Result) then
    Result := TPath.GetFullPath(TPath.Combine(AppPath, '..\..\www'));
end;

{ TDemoWebModule }

procedure TDemoWebModule.WebModuleCreate(Sender: TObject);
begin
  FEngine := TMVCEngine.Create(Self,
    procedure(AConfig: TMVCConfig)
    begin
      AConfig[TMVCConfigKey.DefaultContentType] := TMVCMediaType.APPLICATION_JSON;
      AConfig[TMVCConfigKey.DefaultContentCharset] := TMVCConstants.DEFAULT_CONTENT_CHARSET;
    end);

  // WebBroker creates a web module, and so an engine, for every request
  // served at the same time: the middlewares keep no state, the shared
  // one lives in ChaosSettings and ExchangeRates. The dashboard does not
  // fall back to index.html (no SPA support), so the requests to the API
  // reach the controllers.
  FEngine
    .AddMiddleware(TMVCStaticFilesMiddleware.Create('/', DashboardFolder, 'index.html', False))
    .AddMiddleware(TChaosMiddleware.Create('/api'))
    .AddController(TShopController)
    .AddController(TChaosController);
end;

procedure TDemoWebModule.WebModuleDestroy(Sender: TObject);
begin
  FEngine.Free;
end;

end.
