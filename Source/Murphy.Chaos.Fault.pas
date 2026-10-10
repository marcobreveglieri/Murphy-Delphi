unit Murphy.Chaos.Fault;

interface

uses
  System.SysUtils,
  Murphy.Base.Chaos,
  Murphy.Base.Policy;

type

{ EChaosFaultException }

  /// <summary>
  ///  Exception injected by a "Chaos Fault" policy when no other
  ///  fault has been configured.
  /// </summary>
  EChaosFaultException = class(Exception);

{ TChaosFaultContext }

  /// <summary>
  ///  Contains information about the fault being injected.
  /// </summary>
  TChaosFaultContext = class(TObject)
  private
    FFault: Exception;
  public
    /// <summary>
    ///  The exception that is going to be raised. It is owned by the
    ///  policy: do not free it and do not keep references to it.
    /// </summary>
    property Fault: Exception read FFault;
  end;

{ IChaosFaultPolicy }

  /// <summary>
  ///  Represents the interface of the "Chaos Fault" policy, that raises
  ///  an exception instead of executing the action. It is a proactive
  ///  chaos strategy: place it last (innermost) in a policy wrap, so the
  ///  resilience policies around it can react to the injected faults.
  /// </summary>
  IChaosFaultPolicy = interface(IExecutablePolicy)
    ['{D63B0124-EC23-41BB-B0C9-0101DC054E8F}']
    function Enabled(AValue: Boolean): IChaosFaultPolicy;
    function EnabledGenerator(AGenerator: TFunc<Boolean>): IChaosFaultPolicy;
    function InjectionRate(ARate: Double): IChaosFaultPolicy;
    function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosFaultPolicy;
    function Randomizer(AGenerator: TFunc<Double>): IChaosFaultPolicy;
    function Fault(AExceptionType: ExceptClass; const AMessage: string = ''): IChaosFaultPolicy;
    function FaultGenerator(AGenerator: TFunc<Exception>): IChaosFaultPolicy;
    function OnFaultInjected(ACallback: TProc<TChaosFaultContext>): IChaosFaultPolicy;
  end;

{ TChaosFaultPolicy }

  /// <summary>
  ///  Represents the concrete implementation of "Chaos Fault" policy.
  /// </summary>
  TChaosFaultPolicy = class(TChaosPolicy, IChaosFaultPolicy)
  private
    FFaultGenerator: TFunc<Exception>;
    FOnFaultInjectedCallback: TProc<TChaosFaultContext>;
    procedure FireOnFaultInjected(AFault: Exception);
  public
    procedure Execute(AProc: TProc);
    function Enabled(AValue: Boolean): IChaosFaultPolicy;
    function EnabledGenerator(AGenerator: TFunc<Boolean>): IChaosFaultPolicy;
    function InjectionRate(ARate: Double): IChaosFaultPolicy;
    function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosFaultPolicy;
    function Randomizer(AGenerator: TFunc<Double>): IChaosFaultPolicy;
    function Fault(AExceptionType: ExceptClass; const AMessage: string = ''): IChaosFaultPolicy;
    function FaultGenerator(AGenerator: TFunc<Exception>): IChaosFaultPolicy;
    function OnFaultInjected(ACallback: TProc<TChaosFaultContext>): IChaosFaultPolicy;
  end;

{ TChaosFaultBuilder }

  /// <summary>
  ///  Represents an helper to create "Chaos Fault" policy instances.
  ///  Note that this builder does not derive from TPolicyBuilder:
  ///  chaos policies do not filter exceptions, so the entry point is
  ///  the injection rate instead of the handled exception types.
  /// </summary>
  TChaosFaultBuilder = class sealed
  public
    /// <summary>
    ///  Creates a "Chaos Fault" policy that injects a fault in the given
    ///  fraction of executions (from 0 to 1).
    /// </summary>
    class function InjectionRate(ARate: Double): IChaosFaultPolicy;
    /// <summary>
    ///  Creates a "Chaos Fault" policy whose injection rate is computed
    ///  by the generator at every execution.
    /// </summary>
    class function InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosFaultPolicy;
  end;

implementation

uses
  Murphy.Resources.Strings;

{ TChaosFaultPolicy }

procedure TChaosFaultPolicy.Execute(AProc: TProc);
begin
  if ShouldInject then
  begin
    // Without a generator the default fault is injected; a generator
    // returning nil means that no fault is injected this time.
    var LFault: Exception;
    if Assigned(FFaultGenerator) then
      LFault := FFaultGenerator()
    else
      LFault := EChaosFaultException.Create(StrErrChaosFaultInjected);
    if Assigned(LFault) then
    begin
      try
        FireOnFaultInjected(LFault);
      except
        // The fault is never raised, so it must be destroyed here.
        LFault.Free;
        raise;
      end;
      // Raising transfers the fault ownership to the RTL.
      raise LFault;
    end;
  end;
  AProc();
end;

procedure TChaosFaultPolicy.FireOnFaultInjected(AFault: Exception);
begin
  if not Assigned(FOnFaultInjectedCallback) then
    Exit;
  var LContext := TChaosFaultContext.Create;
  try
    LContext.FFault := AFault;
    FOnFaultInjectedCallback(LContext);
  finally
    LContext.Free;
  end;
end;

function TChaosFaultPolicy.Enabled(AValue: Boolean): IChaosFaultPolicy;
begin
  SetEnabled(AValue);
  Result := Self;
end;

function TChaosFaultPolicy.EnabledGenerator(AGenerator: TFunc<Boolean>): IChaosFaultPolicy;
begin
  SetEnabledGenerator(AGenerator);
  Result := Self;
end;

function TChaosFaultPolicy.InjectionRate(ARate: Double): IChaosFaultPolicy;
begin
  SetInjectionRate(ARate);
  Result := Self;
end;

function TChaosFaultPolicy.InjectionRateGenerator(AGenerator: TFunc<Double>): IChaosFaultPolicy;
begin
  SetInjectionRateGenerator(AGenerator);
  Result := Self;
end;

function TChaosFaultPolicy.Randomizer(AGenerator: TFunc<Double>): IChaosFaultPolicy;
begin
  SetRandomizer(AGenerator);
  Result := Self;
end;

function TChaosFaultPolicy.Fault(AExceptionType: ExceptClass;
  const AMessage: string): IChaosFaultPolicy;
begin
  var LMessage := AMessage;
  if LMessage = '' then
    LMessage := StrErrChaosFaultInjected;
  // Exception constructors are not virtual: the instance is of the
  // requested class, but only Exception.Create runs. Use a generator
  // for exception classes that need their own constructor.
  FFaultGenerator :=
    function: Exception
    begin
      Result := AExceptionType.Create(LMessage);
    end;
  Result := Self;
end;

function TChaosFaultPolicy.FaultGenerator(AGenerator: TFunc<Exception>): IChaosFaultPolicy;
begin
  FFaultGenerator := AGenerator;
  Result := Self;
end;

function TChaosFaultPolicy.OnFaultInjected(ACallback: TProc<TChaosFaultContext>): IChaosFaultPolicy;
begin
  FOnFaultInjectedCallback := ACallback;
  Result := Self;
end;

{ TChaosFaultBuilder }

class function TChaosFaultBuilder.InjectionRate(ARate: Double): IChaosFaultPolicy;
begin
  // The local reference frees the policy if the rate is rejected.
  var LPolicy: IChaosFaultPolicy := TChaosFaultPolicy.Create([]);
  Result := LPolicy.InjectionRate(ARate);
end;

class function TChaosFaultBuilder.InjectionRateGenerator(
  AGenerator: TFunc<Double>): IChaosFaultPolicy;
begin
  var LPolicy: IChaosFaultPolicy := TChaosFaultPolicy.Create([]);
  Result := LPolicy.InjectionRateGenerator(AGenerator);
end;

end.
