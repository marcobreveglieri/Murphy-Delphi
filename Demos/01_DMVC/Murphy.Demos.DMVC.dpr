program Murphy.Demos.DMVC;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  IdHTTPWebBrokerBridge,
  Web.WebBroker,
  Web.WebReq,
  ChaosControllerU in 'ChaosControllerU.pas',
  ChaosMiddlewareU in 'ChaosMiddlewareU.pas',
  ChaosSettingsU in 'ChaosSettingsU.pas',
  ExchangeRatesU in 'ExchangeRatesU.pas',
  ShopControllerU in 'ShopControllerU.pas',
  WebModuleU in 'WebModuleU.pas' {DemoWebModule: TWebModule};

const
  Port = 8080;

procedure ConfigureChaos;
begin
  // The experiment starts limited to the requests marked by the header;
  // the dashboard changes every setting at runtime.
  ChaosSettings.BlastRadius := TChaosBlastRadius.MarkedRequests;
  ChaosSettings.SetTarget(TChaosMiddleware.TargetName,
    TChaosTargetSettings.Create(0.1, 0.2, 200, 800));
  // The latency exceeds the 1 second timeout of the client.
  ChaosSettings.SetTarget(TExchangeRatesClient.TargetName,
    TChaosTargetSettings.Create(0.2, 0.2, 1500, 2500));
end;

procedure RunServer;
begin
  var LServer := TIdHTTPWebBrokerBridge.Create(nil);
  try
    LServer.DefaultPort := Port;
    LServer.Active := True;
    Writeln('Murphy - Chaos engineering with DelphiMVCFramework');
    Writeln;
    Writeln(Format('Dashboard: http://localhost:%d/', [Port]));
    Writeln('Press ENTER to stop the server');
    Writeln;
    Readln;
  finally
    LServer.Free;
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  IsMultiThread := True;
  try
    ConfigureChaos;
    if WebRequestHandler <> nil then
      WebRequestHandler.WebModuleClass := WebModuleClass;
    WebRequestHandlerProc.MaxConnections := 1024;
    RunServer;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
