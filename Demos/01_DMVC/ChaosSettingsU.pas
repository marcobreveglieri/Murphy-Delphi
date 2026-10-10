unit ChaosSettingsU;

// Part of the chaos kit of this demo, with ChaosMiddlewareU and
// ChaosControllerU: copy the three units into a DMVC application to
// inject chaos controlled at runtime. This unit does not use DMVC, so
// the clients of the dependencies can use it as well.

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  Murphy.Chaos.Fault,
  Murphy.Chaos.Latency;

type

{ TChaosTargetSettings }

  /// <summary>
  ///  Contains the settings of the chaos injected into a target: the
  ///  incoming requests, or a dependency called by the application.
  /// </summary>
  TChaosTargetSettings = record
    FaultRate: Double;
    LatencyRate: Double;
    LatencyMinMs: Integer;
    LatencyMaxMs: Integer;
    constructor Create(AFaultRate, ALatencyRate: Double;
      ALatencyMinMs, ALatencyMaxMs: Integer);
    /// <summary>
    ///  Raises EArgumentOutOfRangeException when a setting is invalid.
    /// </summary>
    procedure Validate;
  end;

{ TChaosBlastRadius }

  /// <summary>
  ///  Describes the requests the chaos is injected into.
  /// </summary>
  TChaosBlastRadius = (

    /// <summary>
    ///  Only the requests marked by the chaos header: the rest of the
    ///  traffic is left untouched.
    /// </summary>
    MarkedRequests,

    /// <summary>
    ///  Every request.
    /// </summary>
    AllRequests
  );

{ TChaosSettings }

  /// <summary>
  ///  Holds the chaos settings of the application. The chaos controller
  ///  changes them at runtime while the requests read them, so every
  ///  access is synchronized. The master switch is the MurphyChaosEnabled
  ///  global variable of the library.
  /// </summary>
  TChaosSettings = class
  private
    FBlastRadius: TChaosBlastRadius;
    FTargets: TDictionary<string, TChaosTargetSettings>;
    function GetBlastRadius: TChaosBlastRadius;
    procedure SetBlastRadius(AValue: TChaosBlastRadius);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>
    ///  Creates a "Chaos Fault" policy with the current settings of the
    ///  target; the caller chooses the fault. Create it for every request,
    ///  on the thread that serves it: the policy is enabled only if the
    ///  request is in the blast radius (see TChaosScope).
    /// </summary>
    function CreateFault(const ATarget: string): IChaosFaultPolicy;
    /// <summary>
    ///  Creates a "Chaos Latency" policy with the current settings of the
    ///  target, that waits a random time within the latency range. Create
    ///  it for every request, as CreateFault.
    /// </summary>
    function CreateLatency(const ATarget: string): IChaosLatencyPolicy;
    function GetTarget(const AName: string): TChaosTargetSettings;
    /// <summary>
    ///  Adds a target or changes its settings, after validating them.
    /// </summary>
    procedure SetTarget(const AName: string; const ASettings: TChaosTargetSettings);
    function TargetNames: TArray<string>;
    property BlastRadius: TChaosBlastRadius read GetBlastRadius write SetBlastRadius;
  end;

{ TChaosScope }

  /// <summary>
  ///  Tells whether the request served by the current thread is in the
  ///  blast radius. The chaos middleware enters the scope before the
  ///  routing of every request and leaves it at the end.
  /// </summary>
  /// <remarks>
  ///  The state is kept in a thread variable, so it is visible only on the
  ///  thread that serves the request, while e.g. a Timeout policy runs its
  ///  action on a pool thread. That is why the chaos policies created by
  ///  TChaosSettings read it when they are created, not when they run.
  /// </remarks>
  TChaosScope = record
  public
    class procedure Enter(AInBlastRadius: Boolean); static;
    class function InBlastRadius: Boolean; static;
    class procedure Leave; static;
  end;

/// <summary>
///  Returns the chaos settings shared by the whole application.
/// </summary>
function ChaosSettings: TChaosSettings;

implementation

uses
  System.TimeSpan,
  Murphy.Services.Randomizers;

threadvar
  GInBlastRadius: Boolean;

var
  GChaosSettings: TChaosSettings;

function ChaosSettings: TChaosSettings;
begin
  Result := GChaosSettings;
end;

{ TChaosTargetSettings }

constructor TChaosTargetSettings.Create(AFaultRate, ALatencyRate: Double;
  ALatencyMinMs, ALatencyMaxMs: Integer);
begin
  FaultRate := AFaultRate;
  LatencyRate := ALatencyRate;
  LatencyMinMs := ALatencyMinMs;
  LatencyMaxMs := ALatencyMaxMs;
end;

procedure TChaosTargetSettings.Validate;
begin
  if (FaultRate < 0.0) or (FaultRate > 1.0) then
    raise EArgumentOutOfRangeException.Create('The fault rate must be between 0 and 1');
  if (LatencyRate < 0.0) or (LatencyRate > 1.0) then
    raise EArgumentOutOfRangeException.Create('The latency rate must be between 0 and 1');
  if (LatencyMinMs < 0) or (LatencyMaxMs < LatencyMinMs) then
    raise EArgumentOutOfRangeException.Create('The latency range must satisfy 0 <= min <= max');
end;

{ TChaosSettings }

constructor TChaosSettings.Create;
begin
  inherited Create;
  FBlastRadius := TChaosBlastRadius.MarkedRequests;
  FTargets := TDictionary<string, TChaosTargetSettings>.Create;
end;

destructor TChaosSettings.Destroy;
begin
  FTargets.Free;
  inherited Destroy;
end;

function TChaosSettings.CreateFault(const ATarget: string): IChaosFaultPolicy;
begin
  var LSettings := GetTarget(ATarget);
  Result := TChaosFaultBuilder
    .InjectionRate(LSettings.FaultRate)
    .Enabled(TChaosScope.InBlastRadius);
end;

function TChaosSettings.CreateLatency(const ATarget: string): IChaosLatencyPolicy;
begin
  var LSettings := GetTarget(ATarget);
  Result := TChaosLatencyBuilder
    .InjectionRate(LSettings.LatencyRate)
    .Enabled(TChaosScope.InBlastRadius)
    .LatencyGenerator(
      function: TTimeSpan
      begin
        // The randomizer of the library is thread-safe, unlike Random.
        var LRange := LSettings.LatencyMaxMs - LSettings.LatencyMinMs;
        Result := TTimeSpan.FromMilliseconds(
          LSettings.LatencyMinMs + Round(Randomizer.NextDouble * LRange));
      end);
end;

function TChaosSettings.GetBlastRadius: TChaosBlastRadius;
begin
  TMonitor.Enter(Self);
  try
    Result := FBlastRadius;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TChaosSettings.GetTarget(const AName: string): TChaosTargetSettings;
begin
  TMonitor.Enter(Self);
  try
    if not FTargets.TryGetValue(AName, Result) then
      raise EArgumentException.CreateFmt('Unknown chaos target "%s"', [AName]);
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TChaosSettings.SetBlastRadius(AValue: TChaosBlastRadius);
begin
  TMonitor.Enter(Self);
  try
    FBlastRadius := AValue;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TChaosSettings.SetTarget(const AName: string;
  const ASettings: TChaosTargetSettings);
begin
  ASettings.Validate;
  TMonitor.Enter(Self);
  try
    FTargets.AddOrSetValue(AName, ASettings);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TChaosSettings.TargetNames: TArray<string>;
begin
  TMonitor.Enter(Self);
  try
    Result := FTargets.Keys.ToArray;
  finally
    TMonitor.Exit(Self);
  end;
  TArray.Sort<string>(Result);
end;

{ TChaosScope }

class procedure TChaosScope.Enter(AInBlastRadius: Boolean);
begin
  GInBlastRadius := AInBlastRadius;
end;

class function TChaosScope.InBlastRadius: Boolean;
begin
  Result := GInBlastRadius;
end;

class procedure TChaosScope.Leave;
begin
  GInBlastRadius := False;
end;

initialization

  GChaosSettings := TChaosSettings.Create;

finalization

  GChaosSettings.Free;

end.
