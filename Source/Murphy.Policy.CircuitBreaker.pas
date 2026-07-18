unit Murphy.Policy.CircuitBreaker;

interface

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Base.Policy;

type

{ TCircuitState }

  /// <summary>
  /// Describes the possible states the circuit of a Circuit Breaker may be in.
  /// </summary>
  TCircuitState = (

    /// <summary>
    /// When the circuit is closed. Execution of actions is allowed.
    /// </summary>
    Closed,

    /// <summary>
    /// When the automated controller has opened the circuit (typically due to
    /// some failure threshold being exceeded by recent actions). Execution of
    /// actions is blocked.
    /// </summary>
    Open,

    /// <summary>
    /// Half-open - When the circuit is half-open, it is recovering from an open state.
    /// The duration of break of the preceding open state has typically passed.
    /// In the half-open state, actions may be executed, but the results of these actions may be treated with criteria different to normal operation,
    /// to decide if the circuit has recovered sufficiently to be placed back in to the closed state,
    /// or if continuing failures mean the circuit should revert to open perhaps more quickly than in normal operation.
    /// </summary>
    HalfOpen,

    /// <summary>
    /// Isolated - When the circuit has been placed into a fixed open state by the isolate call.
    /// This isolates the circuit manually, blocking execution of all actions until a reset call is made.
    /// </summary>
    Isolated
  );

{ EBrokenCircuitException }

  /// <summary>
  ///  Exception raised when a circuit is in open or isolated state.
  /// </summary>
  EBrokenCircuitException = class (Exception)
  private
    FInnerException: Exception;
  public
    constructor Create(const AMessage: string; AInnerException: Exception);
    property InnerException: Exception read FInnerException;
  end;

{ ICircuitBreakerPolicy }

  /// <summary>
  ///  Represents the interface of the "Circuit Breaker" policy pattern.
  /// </summary>
  ICircuitBreakerPolicy = interface (IPolicy)
    ['{79052D2E-9BE6-42BC-B2F2-C422E991A1F4}']
    function CircuitState: TCircuitState;
    procedure Execute(AProc: TProc);
    function Fail(ATimes: Integer = 2): ICircuitBreakerPolicy;
    procedure Isolate;
    procedure Reset;
    function Within(ADuration: TTimeSpan): ICircuitBreakerPolicy;
  end;

{ TCircuitBreakerPolicy }

  /// <summary>
  ///  Represents the concrete implementation of "Circuit Breaker" policy pattern.
  /// </summary>
  TCircuitBreakerPolicy = class (TPolicy, ICircuitBreakerPolicy)
  private
    FBrokenAt: TDateTime;
    FBrokenFor: Exception;
    FCircuitState: TCircuitState;
    FFailCount: Integer;
    FFailTimes: Integer;
    FWithinDuration: TTimeSpan;
  public
    constructor Create(AExceptionTypes: TArray<ExceptClass>); override;
    destructor Destroy; override;
    function CircuitState: TCircuitState;
    procedure Execute(AProc: TProc);
    function Fail(ATimes: Integer = 2): ICircuitBreakerPolicy;
    procedure Isolate;
    procedure Reset;
    function Within(ADuration: TTimeSpan): ICircuitBreakerPolicy;
  end;

{ TCircuitBreakerBuilder }

  /// <summary>
  ///  Represents an helper to create "Circuit Breaker" policy instances.
  /// </summary>
  TCircuitBreakerBuilder = class sealed (TPolicyBuilder<ICircuitBreakerPolicy>)
  public
    class function Handle(AExceptionTypes: TArray<ExceptClass>): ICircuitBreakerPolicy; override;
  end;

implementation

uses
  Murphy.Resources.Strings,
  Murphy.Services.Schedulers;

{ EBrokenCircuitException }

constructor EBrokenCircuitException.Create(const AMessage: string;
  AInnerException: Exception);
begin
  inherited Create(AMessage);
  FInnerException := AInnerException;
end;

{ TCircuitBreakerPolicy }

constructor TCircuitBreakerPolicy.Create(AExceptionTypes: TArray<ExceptClass>);
begin
  inherited Create(AExceptionTypes);
  FBrokenAt := MinDateTime;
  FCircuitState := TCircuitState.Closed;
  FFailTimes := 2;
  FWithinDuration := TTimeSpan.FromSeconds(30);
end;

destructor TCircuitBreakerPolicy.Destroy;
begin
  FBrokenFor.Free;
  inherited Destroy;
end;

procedure TCircuitBreakerPolicy.Execute(AProc: TProc);
begin
  TMonitor.Enter(Self);
  try
    // Checks if circuit has been manually isolated.
    if FCircuitState = TCircuitState.Isolated then
      raise EBrokenCircuitException.Create(StrErrCircuitBroken, FBrokenFor);

    // Checks if circuit is open and its time to try closing it again.
    if FCircuitState = TCircuitState.Open then
    begin
      var LDurationExpired := (FBrokenAt + FWithinDuration) < Scheduler.Now;
      if not LDurationExpired then
        raise EBrokenCircuitException.Create(StrErrCircuitBroken, FBrokenFor);
      FCircuitState := TCircuitState.HalfOpen;
    end;
  finally
    TMonitor.Exit(Self);
  end;

  // Executes the action submitted to the policy.
  try
    AProc;
  except
    on E: Exception do
    begin
      // Checks if the exception type must be handled.
      if not IsHandled(E) then
        raise;
      TMonitor.Enter(Self);
      try
        // Put the circuit in "open" state if required.
        Inc(FFailCount);
        if (FFailCount >= FFailTimes) or (FCircuitState = TCircuitState.HalfOpen) then
        begin
          FCircuitState := TCircuitState.Open;
          FBrokenAt := Scheduler.Now;
          // Keeps an owned copy of the failure: the original exception
          // is destroyed by the caller's exception handler.
          FBrokenFor.Free;
          FBrokenFor := ExceptClass(E.ClassType).Create(E.Message);
        end;
      finally
        TMonitor.Exit(Self);
      end;
      // Re-raise the handled exception.
      raise;
    end;
  end;
  TMonitor.Enter(Self);
  try
    // Restores the "closed" state for the circuit
    // and heals the failure count after a success.
    if FCircuitState = TCircuitState.HalfOpen then
      Reset
    else
      FFailCount := 0;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TCircuitBreakerPolicy.Fail(ATimes: Integer): ICircuitBreakerPolicy;
begin
  FFailTimes := ATimes;
  Result := Self;
end;

function TCircuitBreakerPolicy.CircuitState: TCircuitState;
begin
  TMonitor.Enter(Self);
  try
    Result := FCircuitState;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TCircuitBreakerPolicy.Isolate;
begin
  TMonitor.Enter(Self);
  try
    FCircuitState := TCircuitState.Isolated;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TCircuitBreakerPolicy.Reset;
begin
  TMonitor.Enter(Self);
  try
    FCircuitState := TCircuitState.Closed;
    FBrokenAt := MinDateTime;
    FreeAndNil(FBrokenFor);
    FFailCount := 0;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TCircuitBreakerPolicy.Within(ADuration: TTimeSpan): ICircuitBreakerPolicy;
begin
  FWithinDuration := ADuration;
  Result := Self;
end;

{ TCircuitBreakerBuilder }

class function TCircuitBreakerBuilder.Handle(
  AExceptionTypes: TArray<ExceptClass>): ICircuitBreakerPolicy;
begin
  Result := TCircuitBreakerPolicy.Create(AExceptionTypes);
end;

end.
