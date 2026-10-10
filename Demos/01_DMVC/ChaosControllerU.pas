unit ChaosControllerU;

// Part of the chaos kit of this demo (see ChaosSettingsU).

interface

uses
  JsonDataObjects,
  MVCFramework,
  MVCFramework.Commons;

type

{ TChaosController }

  /// <summary>
  ///  Lets a dashboard or a script read and change the chaos settings at
  ///  runtime. It answers only to the local machine, since whoever reaches
  ///  it can inject failures into every request.
  /// </summary>
  /// <remarks>
  ///  The settings, as returned by GET and accepted by PUT:
  ///  { "enabled": true, "blastRadius": "marked" | "all",
  ///    "markerHeader": "X-Chaos", "targets": { "inbound": { "faultRate":
  ///    0.1, "latencyRate": 0.2, "latencyMinMs": 200, "latencyMaxMs": 800 },
  ///    ... } }
  ///  PUT changes only the values found in the body ("markerHeader" is read
  ///  only) and validates all of them before changing anything.
  /// </remarks>
  [MVCPath('/chaos')]
  TChaosController = class(TMVCController)
  protected
    procedure OnBeforeAction(AContext: TWebContext; const AActionName: string;
      var AHandled: Boolean); override;
  public
    [MVCPath]
    [MVCHTTPMethod([httpGET])]
    function GetSettings: TJsonObject;

    [MVCPath]
    [MVCHTTPMethod([httpPUT])]
    function UpdateSettings: TJsonObject;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  Web.HTTPApp,
  Murphy.Globals,
  ChaosMiddlewareU,
  ChaosSettingsU;

const
  BlastRadiusNames: array[TChaosBlastRadius] of string = ('marked', 'all');

function IsLocalRequest(AContext: TWebContext; out APeerAddress: string): Boolean;
begin
  // The address of the connection, not Request.ClientIp: up to DMVC 3.4
  // it trusts the X-Forwarded-For header, that any client can forge.
  // RawWebRequest is available with WebBroker; with the other hosts of
  // DMVC 3.5 use Request.PeerIp instead.
  APeerAddress := '';
  if Assigned(AContext.Request.RawWebRequest) then
    APeerAddress := AContext.Request.RawWebRequest.RemoteAddr;
  // Indy writes the IPv6 loopback address in full.
  Result := APeerAddress.StartsWith('127.') or (APeerAddress = '::1')
    or (APeerAddress = '0:0:0:0:0:0:0:1');
end;

function ParseBlastRadius(const AName: string): TChaosBlastRadius;
begin
  for var LValue := Low(TChaosBlastRadius) to High(TChaosBlastRadius) do
    if SameText(AName, BlastRadiusNames[LValue]) then
      Exit(LValue);
  raise EArgumentException.Create('The blast radius must be "marked" or "all"');
end;

{ TChaosController }

procedure TChaosController.OnBeforeAction(AContext: TWebContext;
  const AActionName: string; var AHandled: Boolean);
begin
  inherited;
  var LPeerAddress: string;
  if not IsLocalRequest(AContext, LPeerAddress) then
    raise EMVCException.CreateFmt(HTTP_STATUS.Forbidden,
      'The chaos settings can be read and changed only from the local machine, not from "%s"',
      [LPeerAddress]);
end;

function TChaosController.GetSettings: TJsonObject;
begin
  Result := TJsonObject.Create;
  try
    Result.B['enabled'] := MurphyChaosEnabled;
    Result.S['blastRadius'] := BlastRadiusNames[ChaosSettings.BlastRadius];
    Result.S['markerHeader'] := TChaosMiddleware.MarkerHeader;
    var LTargets := Result.O['targets'];
    for var LName in ChaosSettings.TargetNames do
    begin
      var LSettings := ChaosSettings.GetTarget(LName);
      var LTarget := LTargets.O[LName];
      LTarget.F['faultRate'] := LSettings.FaultRate;
      LTarget.F['latencyRate'] := LSettings.LatencyRate;
      LTarget.I['latencyMinMs'] := LSettings.LatencyMinMs;
      LTarget.I['latencyMaxMs'] := LSettings.LatencyMaxMs;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TChaosController.UpdateSettings: TJsonObject;
begin
  var LBody := StrToJSONObject(Context.Request.Body);
  if not Assigned(LBody) then
    raise EMVCException.Create(HTTP_STATUS.BadRequest, 'The body must be a JSON object');

  var LEnabled := MurphyChaosEnabled;
  var LBlastRadius := ChaosSettings.BlastRadius;
  var LTargets := TDictionary<string, TChaosTargetSettings>.Create;
  try
    // Everything is read and validated first: an invalid request leaves
    // all the settings as they were.
    try
      if LBody.Contains('enabled') then
      begin
        // B[] would read any other value as False.
        if LBody.Types['enabled'] <> jdtBool then
          raise EArgumentException.Create('"enabled" must be true or false');
        LEnabled := LBody.B['enabled'];
      end;
      if LBody.Contains('blastRadius') then
        LBlastRadius := ParseBlastRadius(LBody.S['blastRadius']);
      if LBody.Contains('targets') then
      begin
        var LTargetsJson := LBody.O['targets'];
        for var LIndex := 0 to LTargetsJson.Count - 1 do
        begin
          var LName := LTargetsJson.Names[LIndex];
          var LTargetJson := LTargetsJson.Items[LIndex].ObjectValue;
          var LSettings := ChaosSettings.GetTarget(LName);
          if LTargetJson.Contains('faultRate') then
            LSettings.FaultRate := LTargetJson.F['faultRate'];
          if LTargetJson.Contains('latencyRate') then
            LSettings.LatencyRate := LTargetJson.F['latencyRate'];
          if LTargetJson.Contains('latencyMinMs') then
            LSettings.LatencyMinMs := LTargetJson.I['latencyMinMs'];
          if LTargetJson.Contains('latencyMaxMs') then
            LSettings.LatencyMaxMs := LTargetJson.I['latencyMaxMs'];
          LSettings.Validate;
          LTargets.AddOrSetValue(LName, LSettings);
        end;
      end;
    except
      on E: Exception do
        raise EMVCException.Create(HTTP_STATUS.BadRequest, E.Message);
    end;

    MurphyChaosEnabled := LEnabled;
    ChaosSettings.BlastRadius := LBlastRadius;
    for var LPair in LTargets do
      ChaosSettings.SetTarget(LPair.Key, LPair.Value);
  finally
    LTargets.Free;
    LBody.Free;
  end;

  Result := GetSettings;
end;

end.
