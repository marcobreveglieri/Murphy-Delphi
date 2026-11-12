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

{ ICancellationToken }

  /// <summary>
  ///  Lets an operation run by the "Timeout" policy learn that its time
  ///  is over, so that it can stop (cooperative cancellation). The token
  ///  is cancelled when the timeout expires, never before.
  /// </summary>
  ICancellationToken = interface
    ['{6F2A9C41-B8D3-4E57-A1C6-3E9D5B7F0A28}']
    function IsCancellationRequested: Boolean;
    /// <summary>
    ///  Raises EOperationCancelled when the cancellation was requested:
    ///  call it at the safe points of a long operation to leave it.
    /// </summary>
    procedure ThrowIfCancellationRequested;
    /// <summary>
    ///  Registers a callback executed once when the cancellation is
    ///  requested, or at once (in the calling thread) when it has been
    ///  requested already. Use it to interrupt a blocking call, e.g. by
    ///  closing a connection. The callback runs in the thread that
    ///  waits for the timeout, so keep it short and thread-safe: an
    ///  exception raised by it is swallowed, since it must not hide the
    ///  timeout itself.
    /// </summary>
    procedure Register(ACallback: TProc);
  end;

{ ITimeoutPolicy }

  /// <summary>
  ///  Represents the interface of the "Timeout" policy pattern. The
  ///  operation runs in a separate task and the caller stops waiting for
  ///  it when the time is over. Delphi cannot stop a running task, so
  ///  the operation is abandoned, not cancelled: it goes on in the
  ///  background, occupying a thread of the pool, until it ends. Use the
  ///  overload with the cancellation token to let it stop by itself.
  /// </summary>
  ITimeoutPolicy = interface(IExecutablePolicy)
    ['{8B3E9F12-4A7C-4D1E-9B5A-2E8C7F6D4A91}']
    function After(ADuration: TTimeSpan): ITimeoutPolicy;
    function OnTimeout(ACallback: TProc<TTimeoutContext>): ITimeoutPolicy;
    /// <summary>
    ///  Executes the operation passing it a token that is cancelled when
    ///  the timeout expires. The caller still gets
    ///  ETimeoutRejectedException at once: the operation decides when to
    ///  react, by polling the token or by registering a callback. The
    ///  exceptions it raises after the timeout (including the
    ///  EOperationCancelled of ThrowIfCancellationRequested) are
    ///  discarded.
    /// </summary>
    procedure Execute(AProc: TProc<ICancellationToken>); overload;
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
    procedure Execute(AProc: TProc); overload;
    procedure Execute(AProc: TProc<ICancellationToken>); overload;
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

type

{ TCancellationToken }

  /// <summary>
  ///  Represents the concrete implementation of the cancellation token.
  ///  It is cancelled once, by the policy; the callbacks registered
  ///  before are run outside the lock, so they can use the token.
  /// </summary>
  TCancellationToken = class(TInterfacedObject, ICancellationToken)
  private
    FCallbacks: TArray<TProc>;
    FCancelled: Integer;
    FLock: TCriticalSection;
    class procedure RunCallback(const ACallback: TProc); static;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Cancel;
    function IsCancellationRequested: Boolean;
    procedure Register(ACallback: TProc);
    procedure ThrowIfCancellationRequested;
  end;

{ TCancellationToken }

constructor TCancellationToken.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TCancellationToken.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

class procedure TCancellationToken.RunCallback(const ACallback: TProc);
begin
  try
    ACallback();
  except
    // A failing callback must neither stop the other ones nor hide the
    // timeout that is being reported to the caller.
  end;
end;

procedure TCancellationToken.Cancel;
begin
  var LCallbacks: TArray<TProc>;
  FLock.Enter;
  try
    if FCancelled <> 0 then
      Exit;
    TInterlocked.Exchange(FCancelled, 1);
    LCallbacks := FCallbacks;
    FCallbacks := nil;
  finally
    FLock.Leave;
  end;
  for var LCallback in LCallbacks do
    RunCallback(LCallback);
end;

function TCancellationToken.IsCancellationRequested: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0;
end;

procedure TCancellationToken.Register(ACallback: TProc);
begin
  if not Assigned(ACallback) then
    Exit;
  FLock.Enter;
  try
    if FCancelled = 0 then
    begin
      FCallbacks := FCallbacks + [ACallback];
      Exit;
    end;
  finally
    FLock.Leave;
  end;
  // Already cancelled: nobody else will ever run it.
  RunCallback(ACallback);
end;

procedure TCancellationToken.ThrowIfCancellationRequested;
begin
  if IsCancellationRequested then
    raise EOperationCancelled.Create(StrErrOperationCancelled);
end;

{ TTimeoutPolicy }

constructor TTimeoutPolicy.Create(AExceptionTypes: TArray<ExceptClass>);
begin
  inherited Create(AExceptionTypes);
  FTimeoutDuration := TTimeSpan.FromSeconds(30);
end;

procedure TTimeoutPolicy.Execute(AProc: TProc);
begin
  Execute(
    procedure(AToken: ICancellationToken)
    begin
      AProc();
    end);
end;

procedure TTimeoutPolicy.Execute(AProc: TProc<ICancellationToken>);
const
  TaskRunning = 0;
  TaskAbandoned = 1;
  TaskFaulted = 2;
begin
  var LStopwatch := TStopwatch.StartNew;
  // The task keeps the token alive through its own reference, so it is
  // safe to cancel it even if the task outlives this call.
  var LCancellation := TCancellationToken.Create;
  var LToken: ICancellationToken := LCancellation;
  var LExceptionObj: TObject := nil;
  var LTaskState: Integer := TaskRunning;
  var LTask := TTask.Create(
    procedure
    begin
      try
        AProc(LToken);
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

    // Tell the abandoned operation that its time is over. This comes after
    // the state change above: an exception it raises because of the
    // cancellation finds the task abandoned and is destroyed by the task.
    LCancellation.Cancel;

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
