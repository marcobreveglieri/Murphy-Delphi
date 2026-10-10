unit Murphy.Base.Chaos;

interface

uses
  System.SysUtils,
  Murphy.Base.Policy;

type

{ TChaosPolicy }

  /// <summary>
  ///  Represents the base class that share functionality with all the
  ///  chaos policies, that inject faults, latency, behaviors or fake
  ///  outcomes into executions to test the resilience of a system.
  /// </summary>
  /// <remarks>
  ///  Chaos policies do not filter exceptions: the exception types
  ///  received by the constructor are kept only to share the TPolicy
  ///  base, so chaos builders always pass an empty array.
  /// </remarks>
  TChaosPolicy = class abstract (TPolicy)
  private
    FEnabled: Boolean;
    FEnabledGenerator: TFunc<Boolean>;
    FInjectionRate: Double;
    FInjectionRateGenerator: TFunc<Double>;
    FRandomizer: TFunc<Double>;
  protected
    procedure SetEnabled(AValue: Boolean);
    procedure SetEnabledGenerator(AGenerator: TFunc<Boolean>);
    procedure SetInjectionRate(ARate: Double);
    procedure SetInjectionRateGenerator(AGenerator: TFunc<Double>);
    procedure SetRandomizer(AGenerator: TFunc<Double>);
    /// <summary>
    ///  Decides whether chaos must be injected into the current execution.
    /// </summary>
    function ShouldInject: Boolean;
  public
    constructor Create(AExceptionTypes: TArray<ExceptClass>); override;
  end;

implementation

uses
  System.Math,
  Murphy.Globals,
  Murphy.Resources.Strings,
  Murphy.Services.Randomizers;

{ TChaosPolicy }

constructor TChaosPolicy.Create(AExceptionTypes: TArray<ExceptClass>);
begin
  inherited Create(AExceptionTypes);
  FEnabled := True;
  // Same default injection rate as Polly.
  FInjectionRate := 0.001;
end;

procedure TChaosPolicy.SetEnabled(AValue: Boolean);
begin
  FEnabled := AValue;
end;

procedure TChaosPolicy.SetEnabledGenerator(AGenerator: TFunc<Boolean>);
begin
  FEnabledGenerator := AGenerator;
end;

procedure TChaosPolicy.SetInjectionRate(ARate: Double);
begin
  if (ARate < 0.0) or (ARate > 1.0) then
    raise EArgumentOutOfRangeException.Create(StrErrChaosInvalidInjectionRate);
  FInjectionRate := ARate;
end;

procedure TChaosPolicy.SetInjectionRateGenerator(AGenerator: TFunc<Double>);
begin
  FInjectionRateGenerator := AGenerator;
end;

procedure TChaosPolicy.SetRandomizer(AGenerator: TFunc<Double>);
begin
  FRandomizer := AGenerator;
end;

function TChaosPolicy.ShouldInject: Boolean;
begin
  // The master switch wins over any policy setting.
  if not MurphyChaosEnabled then
    Exit(False);

  // Generators are evaluated at every execution and win over values.
  var LEnabled := FEnabled;
  if Assigned(FEnabledGenerator) then
    LEnabled := FEnabledGenerator();
  if not LEnabled then
    Exit(False);

  var LRate := FInjectionRate;
  if Assigned(FInjectionRateGenerator) then
    LRate := EnsureRange(FInjectionRateGenerator(), 0.0, 1.0);

  // The bounds do not depend on the randomizer: a rate of 0 never
  // injects and a rate of 1 always does.
  if LRate <= 0.0 then
    Exit(False);
  if LRate >= 1.0 then
    Exit(True);

  var LValue: Double;
  if Assigned(FRandomizer) then
    LValue := FRandomizer()
  else
    LValue := Murphy.Services.Randomizers.Randomizer.NextDouble;
  Result := LValue < LRate;
end;

end.
