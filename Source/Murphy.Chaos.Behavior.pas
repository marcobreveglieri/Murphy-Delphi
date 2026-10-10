unit Murphy.Chaos.Behavior;

interface

uses
  System.SysUtils,
  Murphy.Base.Chaos,
  Murphy.Base.Policy;

type

{ TChaosBehaviorContext }

  /// <summary>
  ///  Contains information about the behavior that has been injected.
  ///  It carries no data yet: it exists so that information can be
  ///  added later without changing the callback signature.
  /// </summary>
  TChaosBehaviorContext = class(TObject);

{ IChaosBehaviorPolicy }

  /// <summary>
  ///  Represents the interface of the "Chaos Behavior" policy, that runs
  ///  custom code (e.g. dropping a connection or clearing a cache) before
  ///  executing the action, which then runs normally. It is a proactive
  ///  chaos strategy: place it last (innermost) in a policy wrap. Use the
  ///  "Chaos Latency" policy to inject delays, not a sleeping behavior.
  /// </summary>
  IChaosBehaviorPolicy = interface(IExecutablePolicy)
    ['{CE37527F-CCCC-4793-BE22-45ABF6FDAEE8}']
    function Enabled(AValue: Boolean): IChaosBehaviorPolicy;
    function EnabledGenerator(AGenerator: TFunc<Boolean>): IChaosBehaviorPolicy;
    function InjectionRate(ARate: Double): IChaosBehaviorPolicy;
    function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosBehaviorPolicy;
    function Randomizer(AGenerator: TFunc<Double>): IChaosBehaviorPolicy;
    function Behavior(AProc: TProc): IChaosBehaviorPolicy;
    function OnBehaviorInjected(ACallback: TProc<TChaosBehaviorContext>): IChaosBehaviorPolicy;
  end;

{ TChaosBehaviorPolicy }

  /// <summary>
  ///  Represents the concrete implementation of "Chaos Behavior" policy.
  /// </summary>
  TChaosBehaviorPolicy = class(TChaosPolicy, IChaosBehaviorPolicy)
  private
    FBehavior: TProc;
    FOnBehaviorInjectedCallback: TProc<TChaosBehaviorContext>;
    procedure FireOnBehaviorInjected;
  public
    procedure Execute(AProc: TProc);
    function Enabled(AValue: Boolean): IChaosBehaviorPolicy;
    function EnabledGenerator(AGenerator: TFunc<Boolean>): IChaosBehaviorPolicy;
    function InjectionRate(ARate: Double): IChaosBehaviorPolicy;
    function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosBehaviorPolicy;
    function Randomizer(AGenerator: TFunc<Double>): IChaosBehaviorPolicy;
    function Behavior(AProc: TProc): IChaosBehaviorPolicy;
    function OnBehaviorInjected(ACallback: TProc<TChaosBehaviorContext>): IChaosBehaviorPolicy;
  end;

{ TChaosBehaviorBuilder }

  /// <summary>
  ///  Represents an helper to create "Chaos Behavior" policy instances.
  ///  Like every chaos builder, it does not derive from TPolicyBuilder:
  ///  the entry point is the injection rate.
  /// </summary>
  TChaosBehaviorBuilder = class sealed
  public
    /// <summary>
    ///  Creates a "Chaos Behavior" policy that injects the behavior in
    ///  the given fraction of executions (from 0 to 1).
    /// </summary>
    class function InjectionRate(ARate: Double): IChaosBehaviorPolicy;
    /// <summary>
    ///  Creates a "Chaos Behavior" policy whose injection rate is
    ///  computed by the generator at every execution.
    /// </summary>
    class function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosBehaviorPolicy;
  end;

implementation

{ TChaosBehaviorPolicy }

procedure TChaosBehaviorPolicy.Execute(AProc: TProc);
begin
  // Without a behavior there is nothing to inject. A behavior raising
  // an exception propagates it: the callback and the action are skipped.
  if Assigned(FBehavior) and ShouldInject then
  begin
    FBehavior();
    FireOnBehaviorInjected;
  end;
  AProc();
end;

procedure TChaosBehaviorPolicy.FireOnBehaviorInjected;
begin
  if not Assigned(FOnBehaviorInjectedCallback) then
    Exit;
  var LContext := TChaosBehaviorContext.Create;
  try
    FOnBehaviorInjectedCallback(LContext);
  finally
    LContext.Free;
  end;
end;

function TChaosBehaviorPolicy.Enabled(AValue: Boolean): IChaosBehaviorPolicy;
begin
  SetEnabled(AValue);
  Result := Self;
end;

function TChaosBehaviorPolicy.EnabledGenerator(AGenerator: TFunc<Boolean>): IChaosBehaviorPolicy;
begin
  SetEnabledGenerator(AGenerator);
  Result := Self;
end;

function TChaosBehaviorPolicy.InjectionRate(ARate: Double): IChaosBehaviorPolicy;
begin
  SetInjectionRate(ARate);
  Result := Self;
end;

function TChaosBehaviorPolicy.InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosBehaviorPolicy;
begin
  SetInjectionRateGenerator(AGenerator);
  Result := Self;
end;

function TChaosBehaviorPolicy.Randomizer(AGenerator: TFunc<Double>): IChaosBehaviorPolicy;
begin
  SetRandomizer(AGenerator);
  Result := Self;
end;

function TChaosBehaviorPolicy.Behavior(AProc: TProc): IChaosBehaviorPolicy;
begin
  FBehavior := AProc;
  Result := Self;
end;

function TChaosBehaviorPolicy.OnBehaviorInjected(
  ACallback: TProc<TChaosBehaviorContext>): IChaosBehaviorPolicy;
begin
  FOnBehaviorInjectedCallback := ACallback;
  Result := Self;
end;

{ TChaosBehaviorBuilder }

class function TChaosBehaviorBuilder.InjectionRate(ARate: Double): IChaosBehaviorPolicy;
begin
  // The local reference frees the policy if the rate is rejected.
  var LPolicy: IChaosBehaviorPolicy := TChaosBehaviorPolicy.Create([]);
  Result := LPolicy.InjectionRate(ARate);
end;

class function TChaosBehaviorBuilder.InjectionRateGenerator(
  AGenerator: TFunc<Double>): IChaosBehaviorPolicy;
begin
  var LPolicy: IChaosBehaviorPolicy := TChaosBehaviorPolicy.Create([]);
  Result := LPolicy.InjectionRateGenerator(AGenerator);
end;

end.
