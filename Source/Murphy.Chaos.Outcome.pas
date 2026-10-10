unit Murphy.Chaos.Outcome;

interface

uses
  System.SysUtils,
  Murphy.Base.Chaos,
  Murphy.Base.Policy;

type

{ TChaosOutcomeContext<TResult> }

  /// <summary>
  ///  Contains information about the outcome being injected.
  /// </summary>
  TChaosOutcomeContext<TResult> = class(TObject)
  private
    FOutcome: TResult;
  public
    property Outcome: TResult read FOutcome;
  end;

{ IChaosOutcomePolicy<TResult> }

  /// <summary>
  ///  Represents the interface of the "Chaos Outcome" policy, that
  ///  returns a fake result instead of executing the function. Like the
  ///  Fallback and Cache policies it works on functions, so it cannot
  ///  join a policy wrap: call it inside the function executed by the
  ///  other policies. To inject exceptions use the "Chaos Fault" policy.
  /// </summary>
  IChaosOutcomePolicy<TResult> = interface(IPolicy)
    ['{5BA95FD0-7059-45A9-8FF2-EB98001F07D0}']
    function Execute(AFunc: TFunc<TResult>): TResult;
    function Enabled(AValue: Boolean): IChaosOutcomePolicy<TResult>;
    function EnabledGenerator(AGenerator: TFunc<Boolean>): IChaosOutcomePolicy<TResult>;
    function InjectionRate(ARate: Double): IChaosOutcomePolicy<TResult>;
    function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosOutcomePolicy<TResult>;
    function Randomizer(AGenerator: TFunc<Double>): IChaosOutcomePolicy<TResult>;
    function Outcome(AGenerator: TFunc<TResult>): IChaosOutcomePolicy<TResult>;
    function OnOutcomeInjected(ACallback: TProc<TChaosOutcomeContext<TResult>>): IChaosOutcomePolicy<TResult>;
  end;

{ TChaosOutcomePolicy<TResult> }

  /// <summary>
  ///  Represents the concrete implementation of "Chaos Outcome" policy.
  ///  When TResult is a class type the policy does not own the injected
  ///  instances: the generator must create a new instance at every call,
  ///  and the caller owns it as it would own the real result.
  /// </summary>
  TChaosOutcomePolicy<TResult> = class(TChaosPolicy, IChaosOutcomePolicy<TResult>)
  private
    FOutcomeGenerator: TFunc<TResult>;
    FOnOutcomeInjectedCallback: TProc<TChaosOutcomeContext<TResult>>;
    procedure FireOnOutcomeInjected(const AOutcome: TResult);
  public
    function Execute(AFunc: TFunc<TResult>): TResult;
    function Enabled(AValue: Boolean): IChaosOutcomePolicy<TResult>;
    function EnabledGenerator(AGenerator: TFunc<Boolean>): IChaosOutcomePolicy<TResult>;
    function InjectionRate(ARate: Double): IChaosOutcomePolicy<TResult>;
    function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosOutcomePolicy<TResult>;
    function Randomizer(AGenerator: TFunc<Double>): IChaosOutcomePolicy<TResult>;
    function Outcome(AGenerator: TFunc<TResult>): IChaosOutcomePolicy<TResult>;
    function OnOutcomeInjected(ACallback: TProc<TChaosOutcomeContext<TResult>>): IChaosOutcomePolicy<TResult>;
  end;

{ TChaosOutcomeBuilder<TResult> }

  /// <summary>
  ///  Represents an helper to create "Chaos Outcome" policy instances.
  ///  Like every chaos builder, it does not derive from TPolicyBuilder:
  ///  the entry point is the injection rate.
  /// </summary>
  TChaosOutcomeBuilder<TResult> = class sealed
  public
    /// <summary>
    ///  Creates a "Chaos Outcome" policy that injects the outcome in
    ///  the given fraction of executions (from 0 to 1).
    /// </summary>
    class function InjectionRate(ARate: Double): IChaosOutcomePolicy<TResult>;
    /// <summary>
    ///  Creates a "Chaos Outcome" policy whose injection rate is
    ///  computed by the generator at every execution.
    /// </summary>
    class function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosOutcomePolicy<TResult>;
  end;

implementation

{ TChaosOutcomePolicy<TResult> }

function TChaosOutcomePolicy<TResult>.Execute(AFunc: TFunc<TResult>): TResult;
begin
  // Without an outcome generator there is nothing to inject.
  if Assigned(FOutcomeGenerator) and ShouldInject then
  begin
    Result := FOutcomeGenerator();
    FireOnOutcomeInjected(Result);
    Exit;
  end;
  Result := AFunc();
end;

procedure TChaosOutcomePolicy<TResult>.FireOnOutcomeInjected(const AOutcome: TResult);
begin
  if not Assigned(FOnOutcomeInjectedCallback) then
    Exit;
  var LContext := TChaosOutcomeContext<TResult>.Create;
  try
    LContext.FOutcome := AOutcome;
    FOnOutcomeInjectedCallback(LContext);
  finally
    LContext.Free;
  end;
end;

function TChaosOutcomePolicy<TResult>.Enabled(AValue: Boolean): IChaosOutcomePolicy<TResult>;
begin
  SetEnabled(AValue);
  Result := Self;
end;

function TChaosOutcomePolicy<TResult>.EnabledGenerator(
  AGenerator: TFunc<Boolean>): IChaosOutcomePolicy<TResult>;
begin
  SetEnabledGenerator(AGenerator);
  Result := Self;
end;

function TChaosOutcomePolicy<TResult>.InjectionRate(ARate: Double): IChaosOutcomePolicy<TResult>;
begin
  SetInjectionRate(ARate);
  Result := Self;
end;

function TChaosOutcomePolicy<TResult>.InjectionRateGenerator(
  AGenerator: TFunc<Double>): IChaosOutcomePolicy<TResult>;
begin
  SetInjectionRateGenerator(AGenerator);
  Result := Self;
end;

function TChaosOutcomePolicy<TResult>.Randomizer(
  AGenerator: TFunc<Double>): IChaosOutcomePolicy<TResult>;
begin
  SetRandomizer(AGenerator);
  Result := Self;
end;

function TChaosOutcomePolicy<TResult>.Outcome(
  AGenerator: TFunc<TResult>): IChaosOutcomePolicy<TResult>;
begin
  FOutcomeGenerator := AGenerator;
  Result := Self;
end;

function TChaosOutcomePolicy<TResult>.OnOutcomeInjected(
  ACallback: TProc<TChaosOutcomeContext<TResult>>): IChaosOutcomePolicy<TResult>;
begin
  FOnOutcomeInjectedCallback := ACallback;
  Result := Self;
end;

{ TChaosOutcomeBuilder<TResult> }

class function TChaosOutcomeBuilder<TResult>.InjectionRate(
  ARate: Double): IChaosOutcomePolicy<TResult>;
begin
  // The local reference frees the policy if the rate is rejected.
  var LPolicy: IChaosOutcomePolicy<TResult> := TChaosOutcomePolicy<TResult>.Create([]);
  Result := LPolicy.InjectionRate(ARate);
end;

class function TChaosOutcomeBuilder<TResult>.InjectionRateGenerator(
  AGenerator: TFunc<Double>): IChaosOutcomePolicy<TResult>;
begin
  var LPolicy: IChaosOutcomePolicy<TResult> := TChaosOutcomePolicy<TResult>.Create([]);
  Result := LPolicy.InjectionRateGenerator(AGenerator);
end;

end.
