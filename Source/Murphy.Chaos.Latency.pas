unit Murphy.Chaos.Latency;

interface

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Base.Chaos,
  Murphy.Base.Policy;

type

{ TChaosLatencyContext }

  /// <summary>
  ///  Contains information about the latency being injected.
  /// </summary>
  TChaosLatencyContext = class(TObject)
  private
    FLatency: TTimeSpan;
  public
    property Latency: TTimeSpan read FLatency;
  end;

{ IChaosLatencyPolicy }

  /// <summary>
  ///  Represents the interface of the "Chaos Latency" policy, that adds
  ///  a delay before executing the action, which then runs normally. It
  ///  is a proactive chaos strategy: place it last (innermost) in a
  ///  policy wrap, so the resilience policies around it (e.g. Timeout)
  ///  can react to the injected latency.
  /// </summary>
  IChaosLatencyPolicy = interface(IExecutablePolicy)
    ['{1283ED38-8666-49BF-A9D5-75A9167EA3EC}']
    function Enabled(AValue: Boolean): IChaosLatencyPolicy;
    function EnabledGenerator(AGenerator: TFunc<Boolean>): IChaosLatencyPolicy;
    function InjectionRate(ARate: Double): IChaosLatencyPolicy;
    function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosLatencyPolicy;
    function Randomizer(AGenerator: TFunc<Double>): IChaosLatencyPolicy;
    function Latency(ADelay: TTimeSpan): IChaosLatencyPolicy;
    function LatencyGenerator(AGenerator: TFunc<TTimeSpan>): IChaosLatencyPolicy;
    function OnLatencyInjected(ACallback: TProc<TChaosLatencyContext>): IChaosLatencyPolicy;
  end;

{ TChaosLatencyPolicy }

  /// <summary>
  ///  Represents the concrete implementation of "Chaos Latency" policy.
  /// </summary>
  TChaosLatencyPolicy = class(TChaosPolicy, IChaosLatencyPolicy)
  private
    FLatency: TTimeSpan;
    FLatencyGenerator: TFunc<TTimeSpan>;
    FOnLatencyInjectedCallback: TProc<TChaosLatencyContext>;
    procedure FireOnLatencyInjected(ALatency: TTimeSpan);
  public
    constructor Create(AExceptionTypes: TArray<ExceptClass>); override;
    procedure Execute(AProc: TProc);
    function Enabled(AValue: Boolean): IChaosLatencyPolicy;
    function EnabledGenerator(AGenerator: TFunc<Boolean>): IChaosLatencyPolicy;
    function InjectionRate(ARate: Double): IChaosLatencyPolicy;
    function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosLatencyPolicy;
    function Randomizer(AGenerator: TFunc<Double>): IChaosLatencyPolicy;
    function Latency(ADelay: TTimeSpan): IChaosLatencyPolicy;
    function LatencyGenerator(AGenerator: TFunc<TTimeSpan>): IChaosLatencyPolicy;
    function OnLatencyInjected(ACallback: TProc<TChaosLatencyContext>): IChaosLatencyPolicy;
  end;

{ TChaosLatencyBuilder }

  /// <summary>
  ///  Represents an helper to create "Chaos Latency" policy instances.
  ///  Like every chaos builder, it does not derive from TPolicyBuilder:
  ///  the entry point is the injection rate.
  /// </summary>
  TChaosLatencyBuilder = class sealed
  public
    /// <summary>
    ///  Creates a "Chaos Latency" policy that injects latency in the
    ///  given fraction of executions (from 0 to 1).
    /// </summary>
    class function InjectionRate(ARate: Double): IChaosLatencyPolicy;
    /// <summary>
    ///  Creates a "Chaos Latency" policy whose injection rate is
    ///  computed by the generator at every execution.
    /// </summary>
    class function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosLatencyPolicy;
  end;

implementation

uses
  Murphy.Services.Schedulers;

{ TChaosLatencyPolicy }

constructor TChaosLatencyPolicy.Create(AExceptionTypes: TArray<ExceptClass>);
begin
  inherited Create(AExceptionTypes);
  // Same default latency as Polly.
  FLatency := TTimeSpan.FromSeconds(30);
end;

procedure TChaosLatencyPolicy.Execute(AProc: TProc);
begin
  if ShouldInject then
  begin
    var LLatency := FLatency;
    if Assigned(FLatencyGenerator) then
      LLatency := FLatencyGenerator();
    // A zero or negative latency is not injected.
    if LLatency > TTimeSpan.Zero then
    begin
      // Like Polly, the callback is notified before the delay.
      FireOnLatencyInjected(LLatency);
      Scheduler.WaitFor(LLatency);
    end;
  end;
  AProc();
end;

procedure TChaosLatencyPolicy.FireOnLatencyInjected(ALatency: TTimeSpan);
begin
  if not Assigned(FOnLatencyInjectedCallback) then
    Exit;
  var LContext := TChaosLatencyContext.Create;
  try
    LContext.FLatency := ALatency;
    FOnLatencyInjectedCallback(LContext);
  finally
    LContext.Free;
  end;
end;

function TChaosLatencyPolicy.Enabled(AValue: Boolean): IChaosLatencyPolicy;
begin
  SetEnabled(AValue);
  Result := Self;
end;

function TChaosLatencyPolicy.EnabledGenerator(AGenerator: TFunc<Boolean>): IChaosLatencyPolicy;
begin
  SetEnabledGenerator(AGenerator);
  Result := Self;
end;

function TChaosLatencyPolicy.InjectionRate(ARate: Double): IChaosLatencyPolicy;
begin
  SetInjectionRate(ARate);
  Result := Self;
end;

function TChaosLatencyPolicy.InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosLatencyPolicy;
begin
  SetInjectionRateGenerator(AGenerator);
  Result := Self;
end;

function TChaosLatencyPolicy.Randomizer(AGenerator: TFunc<Double>): IChaosLatencyPolicy;
begin
  SetRandomizer(AGenerator);
  Result := Self;
end;

function TChaosLatencyPolicy.Latency(ADelay: TTimeSpan): IChaosLatencyPolicy;
begin
  FLatency := ADelay;
  Result := Self;
end;

function TChaosLatencyPolicy.LatencyGenerator(AGenerator: TFunc<TTimeSpan>): IChaosLatencyPolicy;
begin
  FLatencyGenerator := AGenerator;
  Result := Self;
end;

function TChaosLatencyPolicy.OnLatencyInjected(
  ACallback: TProc<TChaosLatencyContext>): IChaosLatencyPolicy;
begin
  FOnLatencyInjectedCallback := ACallback;
  Result := Self;
end;

{ TChaosLatencyBuilder }

class function TChaosLatencyBuilder.InjectionRate(ARate: Double): IChaosLatencyPolicy;
begin
  // The local reference frees the policy if the rate is rejected.
  var LPolicy: IChaosLatencyPolicy := TChaosLatencyPolicy.Create([]);
  Result := LPolicy.InjectionRate(ARate);
end;

class function TChaosLatencyBuilder.InjectionRateGenerator(
  AGenerator: TFunc<Double>): IChaosLatencyPolicy;
begin
  var LPolicy: IChaosLatencyPolicy := TChaosLatencyPolicy.Create([]);
  Result := LPolicy.InjectionRateGenerator(AGenerator);
end;

end.
