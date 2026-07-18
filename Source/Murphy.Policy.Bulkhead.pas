unit Murphy.Policy.Bulkhead;

interface

uses
  System.SysUtils,
  Murphy.Base.Policy;

type

{ EBulkheadRejectedException }

  /// <summary>
  ///  Exception raised when the bulkhead has no execution slots available.
  /// </summary>
  EBulkheadRejectedException = class(Exception);

{ IBulkheadPolicy }

  /// <summary>
  ///  Represents the interface of the "Bulkhead" policy pattern.
  /// </summary>
  IBulkheadPolicy = interface(IExecutablePolicy)
    ['{22323982-6EE4-47B9-851F-A11E8B4ABFB2}']
    function ExecutionCount: Integer;
    function Limit(AMaxParallelization: Integer): IBulkheadPolicy;
  end;

{ TBulkheadPolicy }

  /// <summary>
  ///  Represents the concrete implementation of "Bulkhead" policy pattern.
  /// </summary>
  TBulkheadPolicy = class(TPolicy, IBulkheadPolicy)
  private
    FExecutionCount: Integer;
    FMaxParallelization: Integer;
  public
    constructor Create(AExceptionTypes: TArray<ExceptClass>); override;
    procedure Execute(AProc: TProc);
    function ExecutionCount: Integer;
    function Limit(AMaxParallelization: Integer): IBulkheadPolicy;
  end;

{ TBulkheadBuilder }

  /// <summary>
  ///  Represents an helper to create "Bulkhead" policy instances.
  /// </summary>
  TBulkheadBuilder = class sealed (TPolicyBuilder<IBulkheadPolicy>)
  public
    /// <summary>
    ///  Creates a "Bulkhead" policy instance. Note that the exception
    ///  types passed here are currently not used by this policy: calls
    ///  are limited regardless of any exception filter, and exceptions
    ///  raised by the operation are re-raised as they are. When the
    ///  bulkhead is saturated, calls are rejected immediately without
    ///  queuing; combine with a "Retry" policy to wait and try again.
    /// </summary>
    class function Handle(AExceptionTypes: TArray<ExceptClass>): IBulkheadPolicy; override;
  end;

implementation

uses
  Murphy.Resources.Strings;

{ TBulkheadPolicy }

constructor TBulkheadPolicy.Create(AExceptionTypes: TArray<ExceptClass>);
begin
  inherited Create(AExceptionTypes);
  FMaxParallelization := 10;
end;

procedure TBulkheadPolicy.Execute(AProc: TProc);
begin
  // Acquires an execution slot or rejects the call immediately:
  // a rejected call never touches the execution counter.
  TMonitor.Enter(Self);
  try
    if FExecutionCount >= FMaxParallelization then
      raise EBulkheadRejectedException.Create(StrErrBulkheadRejected);
    Inc(FExecutionCount);
  finally
    TMonitor.Exit(Self);
  end;

  // The action runs outside the lock, otherwise no parallelism would
  // be possible; the slot is always released, even when the action
  // raises an exception (which is re-raised untouched).
  try
    AProc;
  finally
    TMonitor.Enter(Self);
    try
      Dec(FExecutionCount);
    finally
      TMonitor.Exit(Self);
    end;
  end;
end;

function TBulkheadPolicy.ExecutionCount: Integer;
begin
  TMonitor.Enter(Self);
  try
    Result := FExecutionCount;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TBulkheadPolicy.Limit(AMaxParallelization: Integer): IBulkheadPolicy;
begin
  FMaxParallelization := AMaxParallelization;
  Result := Self;
end;

{ TBulkheadBuilder }

class function TBulkheadBuilder.Handle(
  AExceptionTypes: TArray<ExceptClass>): IBulkheadPolicy;
begin
  Result := TBulkheadPolicy.Create(AExceptionTypes);
end;

end.
