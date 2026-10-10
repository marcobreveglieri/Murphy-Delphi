unit ChaosMiddlewareU;

// Part of the chaos kit of this demo (see ChaosSettingsU).

interface

uses
  MVCFramework,
  MVCFramework.Commons;

type

{ TChaosMiddleware }

  /// <summary>
  ///  DMVC middleware that decides whether each request is in the blast
  ///  radius (see TChaosScope), and injects faults and latency into the
  ///  controller actions under a path, with the settings of the "inbound"
  ///  target. A fault becomes an error response with the given status.
  /// </summary>
  TChaosMiddleware = class(TInterfacedObject, IMVCMiddleware)
  private
    FFaultStatusCode: Integer;
    FPathPrefix: string;
    function IsInBlastRadius(AContext: TWebContext): Boolean;
  protected
    procedure OnBeforeRouting(AContext: TWebContext; var AHandled: Boolean);
    procedure OnBeforeControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      var AHandled: Boolean);
    procedure OnAfterControllerAction(AContext: TWebContext;
      const AControllerQualifiedClassName: string; const AActionName: string;
      const AHandled: Boolean);
    procedure OnAfterRouting(AContext: TWebContext; const AHandled: Boolean);
  public
    const
      /// <summary>
      ///  The header that marks a request as part of the experiment.
      /// </summary>
      MarkerHeader = 'X-Chaos';
      /// <summary>
      ///  The header that tells which chaos a response received.
      /// </summary>
      InjectedHeader = 'X-Chaos-Injected';
      /// <summary>
      ///  The chaos target whose settings the middleware applies.
      /// </summary>
      TargetName = 'inbound';
    constructor Create(const APathPrefix: string = '/api';
      AFaultStatusCode: Integer = HTTP_STATUS.ServiceUnavailable);
  end;

implementation

uses
  System.SysUtils,
  MVCFramework.Logger,
  Murphy.Chaos.Fault,
  Murphy.Chaos.Latency,
  Murphy.Policy.Wrap,
  ChaosSettingsU;

{ TChaosMiddleware }

constructor TChaosMiddleware.Create(const APathPrefix: string;
  AFaultStatusCode: Integer);
begin
  inherited Create;
  FPathPrefix := APathPrefix;
  FFaultStatusCode := AFaultStatusCode;
end;

function TChaosMiddleware.IsInBlastRadius(AContext: TWebContext): Boolean;
begin
  Result := (ChaosSettings.BlastRadius = TChaosBlastRadius.AllRequests)
    or SameText(AContext.Request.Headers[MarkerHeader], 'on');
end;

procedure TChaosMiddleware.OnBeforeRouting(AContext: TWebContext;
  var AHandled: Boolean);
begin
  // Decided once, before any code of the application runs: the chaos
  // policies created while serving the request read it.
  TChaosScope.Enter(IsInBlastRadius(AContext));
end;

procedure TChaosMiddleware.OnBeforeControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName, AActionName: string;
  var AHandled: Boolean);
begin
  if not AContext.Request.PathInfo.StartsWith(FPathPrefix, True) then
    Exit;

  // The policies are created for every request, so they apply the
  // current settings and their callbacks can reach the request. DMVC
  // calls the controller action after this hook, so they execute an
  // empty action: the latency delays the request, while the fault
  // replaces its response.
  TPolicyWrapBuilder.Wrap([
    ChaosSettings.CreateFault(TargetName)
      .FaultGenerator(
        function: Exception
        begin
          // DMVC answers with the status code of an EMVCException.
          Result := EMVCException.Create(FFaultStatusCode, 'Chaos: fault injected');
        end)
      .OnFaultInjected(
        procedure(AFault: TChaosFaultContext)
        begin
          AContext.Response.SetCustomHeader(InjectedHeader, 'fault');
          LogW('Chaos: fault injected into ' + AContext.Request.PathInfo);
        end),
    ChaosSettings.CreateLatency(TargetName)
      .OnLatencyInjected(
        procedure(ALatency: TChaosLatencyContext)
        begin
          var LMilliseconds := Round(ALatency.Latency.TotalMilliseconds);
          AContext.Response.SetCustomHeader(InjectedHeader, 'latency=' + LMilliseconds.ToString);
          LogW(Format('Chaos: %d ms of latency injected into %s',
            [LMilliseconds, AContext.Request.PathInfo]));
        end)
  ]).Execute(
    procedure
    begin
      // The controller action runs after the hook.
    end);
end;

procedure TChaosMiddleware.OnAfterControllerAction(AContext: TWebContext;
  const AControllerQualifiedClassName, AActionName: string;
  const AHandled: Boolean);
begin
  // Nothing to do.
end;

procedure TChaosMiddleware.OnAfterRouting(AContext: TWebContext;
  const AHandled: Boolean);
begin
  // DMVC calls it also when the action fails, unlike OnAfterControllerAction.
  TChaosScope.Leave;
end;

end.
