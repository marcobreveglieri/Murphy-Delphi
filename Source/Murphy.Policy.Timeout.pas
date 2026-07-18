unit Murphy.Policy.Timeout;

interface

uses
  System.Classes,
  System.SysUtils,
  System.TimeSpan,
  System.Threading,
  Murphy.Base.Policy;

type

{ ETimeoutRejectedException }

  /// <summary>
  ///  Exception raised when an operation exceeds its timeout duration.
  /// </summary>
  ETimeoutRejectedException = class(Exception);

{ TTimeoutContext }

  /// <summary>
  ///  Contains information about the timeout that occurred,
  ///  including elapsed time and configured timeout duration.
  /// </summary>
  TTimeoutContext = class(TObject)
  private
    FElapsedTime: TTimeSpan;
    FTimeoutDuration: TTimeSpan;
  public
    property ElapsedTime: TTimeSpan read FElapsedTime;
    property TimeoutDuration: TTimeSpan read FTimeoutDuration;
  end;

{ ITimeoutPolicy }

  /// <summary>
  ///  Represents the interface of the "Timeout" policy pattern.
  /// </summary>
  ITimeoutPolicy = interface(IPolicy)
    ['{8B3E9F12-4A7C-4D1E-9B5A-2E8C7F6D4A91}']
    procedure Execute(AProc: TProc);
    function After(ADuration: TTimeSpan): ITimeoutPolicy;
    function OnTimeout(ACallback: TProc<TTimeoutContext>): ITimeoutPolicy;
  end;

{ TTimeoutPolicy }

  /// <summary>
  ///  Represents the concrete implementation of "Timeout" policy pattern.
  /// </summary>
  TTimeoutPolicy = class(TPolicy, ITimeoutPolicy)
  private
    FTimeoutDuration: TTimeSpan;
    FOnTimeoutCallback: TProc<TTimeoutContext>;
  public
    constructor Create(AExceptionTypes: TArray<ExceptClass>); override;
    procedure Execute(AProc: TProc);
    function After(ADuration: TTimeSpan): ITimeoutPolicy;
    function OnTimeout(ACallback: TProc<TTimeoutContext>): ITimeoutPolicy;
  end;

{ TTimeoutBuilder }

  /// <summary>
  ///  Represents an helper to create "Timeout" policy instances.
  /// </summary>
  TTimeoutBuilder = class sealed (TPolicyBuilder<ITimeoutPolicy>)
  public
    /// <summary>
    ///  Creates a "Timeout" policy instance. Note that the exception
    ///  types passed here are currently not used by this policy: any
    ///  exception raised by the operation is re-raised as it is, and
    ///  the timeout applies regardless of any exception filter.
    /// </summary>
    class function Handle(AExceptionTypes: TArray<ExceptClass>): ITimeoutPolicy; override;
  end;

implementation

uses
  System.Diagnostics,
  System.SyncObjs,
  Murphy.Resources.Strings;

{ TTimeoutPolicy }

constructor TTimeoutPolicy.Create(AExceptionTypes: TArray<ExceptClass>);
begin
  inherited Create(AExceptionTypes);
  FTimeoutDuration := TTimeSpan.FromSeconds(30);
end;

procedure TTimeoutPolicy.Execute(AProc: TProc);
const
  TaskRunning = 0;
  TaskAbandoned = 1;
  TaskFaulted = 2;
begin
  var LStopwatch := TStopwatch.StartNew;
  var LExceptionObj: TObject := nil;
  var LTaskState: Integer := TaskRunning;
  var LTask := TTask.Create(
    procedure
    begin
      try
        AProc;
      except
        // Acquire the exception object (takes ownership) so it can be
        // re-raised on the calling thread. When the call has already
        // timed out nobody is listening anymore, so the exception must
        // be destroyed here to avoid leaking it.
        LExceptionObj := AcquireExceptionObject;
        if TInterlocked.CompareExchange(LTaskState, TaskFaulted, TaskRunning) <> TaskRunning then
          FreeAndNil(LExceptionObj);
      end;
    end);
  LTask.Start;

  if not LTask.Wait(FTimeoutDuration) then
  begin
    // The task is abandoned: from now on it cleans up after itself.
    // If it already stored an exception, ownership is back here.
    if TInterlocked.CompareExchange(LTaskState, TaskAbandoned, TaskRunning) = TaskFaulted then
      FreeAndNil(LExceptionObj);

    // Execute timeout callback if assigned
    if Assigned(FOnTimeoutCallback) then
    begin
      var LContext := TTimeoutContext.Create;
      try
        LContext.FElapsedTime := LStopwatch.Elapsed;
        LContext.FTimeoutDuration := FTimeoutDuration;
        FOnTimeoutCallback(LContext);
      finally
        LContext.Free;
      end;
    end;

    // Raise timeout exception
    raise ETimeoutRejectedException.Create(StrErrTimeoutExceeded);
  end;

  // Task completed within the timeout - check if there was an exception
  if Assigned(LExceptionObj) then
  begin
    // Re-raise the task exception
    // Note: Handle() filtering is not applied to timeout monitoring itself,
    // only to exceptions that emerge from the operation
    raise LExceptionObj;
  end;
end;

function TTimeoutPolicy.After(ADuration: TTimeSpan): ITimeoutPolicy;
begin
  FTimeoutDuration := ADuration;
  Result := Self;
end;

function TTimeoutPolicy.OnTimeout(ACallback: TProc<TTimeoutContext>): ITimeoutPolicy;
begin
  FOnTimeoutCallback := ACallback;
  Result := Self;
end;

{ TTimeoutBuilder }

class function TTimeoutBuilder.Handle(AExceptionTypes: TArray<ExceptClass>): ITimeoutPolicy;
begin
  Result := TTimeoutPolicy.Create(AExceptionTypes);
end;

end.
