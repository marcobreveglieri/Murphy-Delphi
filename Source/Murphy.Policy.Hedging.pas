unit Murphy.Policy.Hedging;

interface

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Base.Policy;

type

{ THedgingContext }

  /// <summary>
  ///  Contains information about the hedged attempt being launched.
  /// </summary>
  THedgingContext = class(TObject)
  private
    FAttemptNumber: Integer;
  public
    /// <summary>
    ///  The 1-based index of the hedged (extra) attempt being launched.
    /// </summary>
    property AttemptNumber: Integer read FAttemptNumber;
  end;

{ IHedgingPolicy }

  /// <summary>
  ///  Represents the interface of the "Hedging" policy pattern.
  ///  The primary attempt is launched immediately; when it does not
  ///  complete within the hedging delay (or fails with a handled
  ///  exception), an additional parallel attempt is launched, and the
  ///  first attempt that succeeds wins. Note that losing attempts are
  ///  abandoned but keep running in background, so hedged actions
  ///  should be idempotent.
  /// </summary>
  IHedgingPolicy = interface(IExecutablePolicy)
    ['{5F746C39-BE24-4544-823E-FC7B7A4955D0}']
    function Delay(ADelay: TTimeSpan): IHedgingPolicy;
    function MaxAttempts(ACount: Integer): IHedgingPolicy;
    function OnHedging(ACallback: TProc<THedgingContext>): IHedgingPolicy;
  end;

{ THedgingPolicy }

  /// <summary>
  ///  Represents the concrete implementation of "Hedging" policy pattern.
  /// </summary>
  THedgingPolicy = class(TPolicy, IHedgingPolicy)
  private
    FHedgingDelay: TTimeSpan;
    FMaxAttempts: Integer;
    FOnHedgingCallback: TProc<THedgingContext>;
    procedure FireOnHedging(AAttemptNumber: Integer);
  public
    constructor Create(AExceptionTypes: TArray<ExceptClass>); override;
    procedure Execute(AProc: TProc);
    function Delay(ADelay: TTimeSpan): IHedgingPolicy;
    function MaxAttempts(ACount: Integer): IHedgingPolicy;
    function OnHedging(ACallback: TProc<THedgingContext>): IHedgingPolicy;
  end;

{ THedgingBuilder }

  /// <summary>
  ///  Represents an helper to create "Hedging" policy instances.
  /// </summary>
  THedgingBuilder = class sealed (TPolicyBuilder<IHedgingPolicy>)
  public
    /// <summary>
    ///  Creates a "Hedging" policy instance. An attempt failing with
    ///  a handled exception triggers the next parallel attempt
    ///  immediately; an unhandled exception is propagated at once.
    ///  When every attempt fails, the most recent failure is raised.
    /// </summary>
    class function Handle(AExceptionTypes: TArray<ExceptClass>): IHedgingPolicy; override;
  end;

implementation

uses
  System.SyncObjs,
  System.Threading,
  Murphy.Resources.Strings;

type

{ THedgingExecution }

  /// <summary>
  ///  Shared coordination state for a single hedged execution. It is
  ///  reference counted because abandoned attempts can outlive the
  ///  coordinator: the last party to release it (coordinator or
  ///  straggler task) frees it.
  /// </summary>
  THedgingExecution = class
  private
    FCompletedCount: Integer;
    FCompletionEvent: TEvent;
    FLastError: TObject;
    FRefCount: Integer;
    FWinnerFlag: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddRef;
    procedure Release;
    function CompletedCount: Integer;
    function HasWinner: Boolean;
    procedure SignalCompletion;
    procedure StoreError(AError: TObject);
    function TakeError: TObject;
    function TryWin: Boolean;
    function WaitForCompletion(ATimeout: Cardinal): TWaitResult; overload;
    function WaitForCompletion: TWaitResult; overload;
  end;

constructor THedgingExecution.Create;
begin
  inherited Create;
  FCompletionEvent := TEvent.Create(nil, False, False, '');
  FRefCount := 1;
end;

destructor THedgingExecution.Destroy;
begin
  // Frees a leftover error stored by a losing attempt after the
  // coordinator already exited (e.g. when another attempt won).
  FLastError.Free;
  FCompletionEvent.Free;
  inherited Destroy;
end;

procedure THedgingExecution.AddRef;
begin
  TInterlocked.Increment(FRefCount);
end;

procedure THedgingExecution.Release;
begin
  if TInterlocked.Decrement(FRefCount) = 0 then
    Free;
end;

function THedgingExecution.CompletedCount: Integer;
begin
  Result := TInterlocked.CompareExchange(FCompletedCount, 0, 0);
end;

function THedgingExecution.HasWinner: Boolean;
begin
  Result := TInterlocked.CompareExchange(FWinnerFlag, 0, 0) <> 0;
end;

procedure THedgingExecution.SignalCompletion;
begin
  // The winner flag and the error slot are always set BEFORE this
  // signal, so the coordinator sees a consistent state on wake up.
  TInterlocked.Increment(FCompletedCount);
  FCompletionEvent.SetEvent;
end;

procedure THedgingExecution.StoreError(AError: TObject);
begin
  // Keeps only the most recent failure: the displaced error (if any)
  // is destroyed here, preserving the single-owner invariant.
  var LOldError := TInterlocked.Exchange(FLastError, AError);
  LOldError.Free;
end;

function THedgingExecution.TakeError: TObject;
begin
  Result := TInterlocked.Exchange(FLastError, nil);
end;

function THedgingExecution.TryWin: Boolean;
begin
  Result := TInterlocked.CompareExchange(FWinnerFlag, 1, 0) = 0;
end;

function THedgingExecution.WaitForCompletion(ATimeout: Cardinal): TWaitResult;
begin
  Result := FCompletionEvent.WaitFor(ATimeout);
end;

function THedgingExecution.WaitForCompletion: TWaitResult;
begin
  Result := FCompletionEvent.WaitFor;
end;

{ THedgingPolicy }

constructor THedgingPolicy.Create(AExceptionTypes: TArray<ExceptClass>);
begin
  inherited Create(AExceptionTypes);
  FHedgingDelay := TTimeSpan.FromSeconds(2);
  FMaxAttempts := 1;
end;

procedure LaunchAttempt(AExec: THedgingExecution; AProc: TProc);
begin
  AExec.AddRef;
  TTask.Run(
    procedure
    begin
      try
        try
          AProc;
          AExec.TryWin;
        except
          // Acquires the exception object (takes ownership) so it can
          // outlive this thread's handler and be re-raised by the
          // coordinator; the shared slot becomes the new owner.
          AExec.StoreError(AcquireExceptionObject);
        end;
        AExec.SignalCompletion;
      finally
        // Abandoned attempts release the shared state last.
        AExec.Release;
      end;
    end);
end;

procedure THedgingPolicy.Execute(AProc: TProc);
begin
  var LExec := THedgingExecution.Create;
  try
    var LMaxLaunches := 1 + FMaxAttempts;
    var LLaunched := 1;
    var LProcessed := 0;
    LaunchAttempt(LExec, AProc);

    while True do
    begin
      var LWaitResult: TWaitResult;
      if LLaunched < LMaxLaunches then
        LWaitResult := LExec.WaitForCompletion(Cardinal(Trunc(FHedgingDelay.TotalMilliseconds)))
      else
        LWaitResult := LExec.WaitForCompletion;

      if LExec.HasWinner then
        Exit;

      // The completion event is auto-reset, so two attempts finishing
      // between waits coalesce into a single wake up: the count delta
      // absorbs every unprocessed completion, and without a winner
      // each of them is a failure.
      var LCompleted := LExec.CompletedCount;
      if LCompleted > LProcessed then
      begin
        LProcessed := LCompleted;
        var LError := LExec.TakeError;
        if Assigned(LError) then
        begin
          // An unhandled exception is propagated immediately; the
          // last launched attempt failing means everything failed.
          // Raising transfers the error ownership to the RTL.
          if not IsHandled(Exception(LError)) then
            raise LError;
          if LProcessed >= LMaxLaunches then
            raise LError;
          FreeAndNil(LError);
        end;
        // A handled failure triggers the next attempt immediately.
        if LLaunched < LMaxLaunches then
        begin
          FireOnHedging(LLaunched);
          LaunchAttempt(LExec, AProc);
          Inc(LLaunched);
        end;
      end
      else if (LWaitResult = TWaitResult.wrTimeout) and (LLaunched < LMaxLaunches) then
      begin
        // The hedging delay elapsed with nothing finished yet:
        // launches the next parallel attempt.
        FireOnHedging(LLaunched);
        LaunchAttempt(LExec, AProc);
        Inc(LLaunched);
      end;
    end;
  finally
    LExec.Release;
  end;
end;

procedure THedgingPolicy.FireOnHedging(AAttemptNumber: Integer);
begin
  if not Assigned(FOnHedgingCallback) then
    Exit;
  var LContext := THedgingContext.Create;
  try
    LContext.FAttemptNumber := AAttemptNumber;
    FOnHedgingCallback(LContext);
  finally
    LContext.Free;
  end;
end;

function THedgingPolicy.Delay(ADelay: TTimeSpan): IHedgingPolicy;
begin
  FHedgingDelay := ADelay;
  Result := Self;
end;

function THedgingPolicy.MaxAttempts(ACount: Integer): IHedgingPolicy;
begin
  if ACount < 0 then
    raise EArgumentException.Create(StrErrHedgingInvalidAttempts);
  FMaxAttempts := ACount;
  Result := Self;
end;

function THedgingPolicy.OnHedging(ACallback: TProc<THedgingContext>): IHedgingPolicy;
begin
  FOnHedgingCallback := ACallback;
  Result := Self;
end;

{ THedgingBuilder }

class function THedgingBuilder.Handle(
  AExceptionTypes: TArray<ExceptClass>): IHedgingPolicy;
begin
  Result := THedgingPolicy.Create(AExceptionTypes);
end;

end.
