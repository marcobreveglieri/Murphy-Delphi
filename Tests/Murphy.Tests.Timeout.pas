unit Murphy.Tests.Timeout;

interface

uses
  DUnitX.TestFramework;

type

{ TTimeoutTests }

  [TestFixture]
  TTimeoutTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestTimeoutHandle;
    [Test]
    procedure TestTimeoutHandleWithDuration;
    [Test]
    procedure TestTimeoutNotExceeded;
    [Test]
    procedure TestTimeoutExceeded;
    [Test]
    procedure TestTimeoutCallback;
    [Test]
    procedure TestTimeoutWithTaskException;
    [Test]
    procedure TestTokenIsNotCancelledWhenOperationIsInTime;
    [Test]
    procedure TestTokenIsCancelledWhenTimeoutExpires;
    [Test]
    procedure TestTokenCallbackRunsWhenTimeoutExpires;
    [Test]
    procedure TestTokenCallbackIsNotRunWhenOperationIsInTime;
    [Test]
    procedure TestTokenCallbackRegisteredAfterCancellationRunsAtOnce;
    [Test]
    procedure TestTokenCallbackFailureDoesNotHideTimeout;
    [Test]
    procedure TestTokenThrowIfCancellationRequestedStopsOperation;
    [Test]
    procedure TestTokenOperationExceptionAfterTimeoutIsDiscarded;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  System.TimeSpan,
  Murphy.Policy.Timeout,
  Murphy.Tests.Helpers;

/// <summary>
///  Waits until a flag set by an abandoned operation (in another thread)
///  becomes 1, for at most two seconds.
/// </summary>
function WaitForFlag(var AFlag: Integer): Boolean;
begin
  for var I := 1 to 200 do
  begin
    if TInterlocked.CompareExchange(AFlag, 0, 0) = 1 then
      Exit(True);
    TThread.Sleep(10);
  end;
  Result := False;
end;

/// <summary>
///  Runs the operation through a policy that times out after 200 ms and
///  returns True when the caller got the timeout exception.
/// </summary>
function TimesOut(const AProc: TProc<ICancellationToken>): Boolean;
begin
  var LPolicy := TTimeoutBuilder
    .Handle([])
    .After(TTimeSpan.FromMilliseconds(200));
  Result := False;
  try
    LPolicy.Execute(AProc);
  except
    on ETimeoutRejectedException do
      Result := True;
  end;
end;

{ TTimeoutTests }

procedure TTimeoutTests.Setup;
begin
end;

procedure TTimeoutTests.TearDown;
begin
end;

procedure TTimeoutTests.TestTimeoutHandle;
begin
  var LPolicy := TTimeoutBuilder
    .Handle([ETimeoutRejectedException]);
  Assert.IsNotNull(LPolicy);
end;

procedure TTimeoutTests.TestTimeoutHandleWithDuration;
begin
  var LPolicy := TTimeoutBuilder
    .Handle([ETimeoutRejectedException])
    .After(TTimeSpan.FromSeconds(5));
  Assert.IsNotNull(LPolicy);
end;

procedure TTimeoutTests.TestTimeoutNotExceeded;
begin
  var LPolicy := TTimeoutBuilder
    .Handle([ETimeoutRejectedException])
    .After(TTimeSpan.FromSeconds(2));
  Assert.WillNotRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          // Fast operation - should complete before timeout
          TThread.Sleep(100);
        end);
    end
  );
end;

procedure TTimeoutTests.TestTimeoutExceeded;
begin
  var LPolicy := TTimeoutBuilder
    .Handle([ETimeoutRejectedException])
    .After(TTimeSpan.FromMilliseconds(200));
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          // Slow operation - should exceed timeout
          TThread.Sleep(1000);
        end);
    end, ETimeoutRejectedException
  );
end;

procedure TTimeoutTests.TestTimeoutCallback;
begin
  var LCallbackExecuted := False;
  var LPolicy := TTimeoutBuilder
    .Handle([ETimeoutRejectedException])
    .After(TTimeSpan.FromMilliseconds(200))
    .OnTimeout(
      procedure(AContext: TTimeoutContext)
      begin
        LCallbackExecuted := True;
        Assert.IsNotNull(AContext);
        Assert.IsTrue(AContext.ElapsedTime > TTimeSpan.Zero);
        Assert.AreEqual(200.0, AContext.TimeoutDuration.TotalMilliseconds, 0.1);
      end);
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      TThread.Sleep(1000);
    end);
  Assert.AreEqual('ETimeoutRejectedException', LFailure.ClassName);
  Assert.IsTrue(LCallbackExecuted, 'OnTimeout callback should have been executed');
end;

procedure TTimeoutTests.TestTimeoutWithTaskException;
begin
  var LPolicy := TTimeoutBuilder
    .Handle([ETimeoutRejectedException])
    .After(TTimeSpan.FromSeconds(2));
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          // Task throws exception before timeout
          raise EInvalidOpException.Create('Test exception');
        end);
    end, EInvalidOpException
  );
end;

procedure TTimeoutTests.TestTokenIsNotCancelledWhenOperationIsInTime;
begin
  var LToken: ICancellationToken := nil;
  var LPolicy := TTimeoutBuilder
    .Handle([])
    .After(TTimeSpan.FromSeconds(2));
  LPolicy.Execute(
    procedure(AToken: ICancellationToken)
    begin
      LToken := AToken;
    end);
  Assert.IsNotNull(LToken);
  Assert.IsFalse(LToken.IsCancellationRequested);
end;

procedure TTimeoutTests.TestTokenIsCancelledWhenTimeoutExpires;
begin
  var LCancelled := 0;
  var LTimedOut := TimesOut(
    procedure(AToken: ICancellationToken)
    begin
      // A cooperative operation: it polls the token and stops.
      for var I := 1 to 200 do
      begin
        if AToken.IsCancellationRequested then
        begin
          TInterlocked.Exchange(LCancelled, 1);
          Exit;
        end;
        TThread.Sleep(10);
      end;
    end);
  Assert.IsTrue(LTimedOut, 'The caller must get the timeout');
  Assert.IsTrue(WaitForFlag(LCancelled), 'The operation must see the cancellation');
end;

procedure TTimeoutTests.TestTokenCallbackRunsWhenTimeoutExpires;
begin
  var LCallbacks := 0;
  var LTimedOut := TimesOut(
    procedure(AToken: ICancellationToken)
    begin
      AToken.Register(
        procedure
        begin
          TInterlocked.Increment(LCallbacks);
        end);
      TThread.Sleep(600);
    end);
  Assert.IsTrue(LTimedOut);
  // The callback runs in the caller thread before the exception reaches it.
  Assert.AreEqual(1, TInterlocked.CompareExchange(LCallbacks, 0, 0));
end;

procedure TTimeoutTests.TestTokenCallbackIsNotRunWhenOperationIsInTime;
begin
  var LCallbacks := 0;
  var LPolicy := TTimeoutBuilder
    .Handle([])
    .After(TTimeSpan.FromSeconds(2));
  LPolicy.Execute(
    procedure(AToken: ICancellationToken)
    begin
      AToken.Register(
        procedure
        begin
          Inc(LCallbacks);
        end);
    end);
  Assert.AreEqual(0, LCallbacks);
end;

procedure TTimeoutTests.TestTokenCallbackRegisteredAfterCancellationRunsAtOnce;
begin
  var LRanAtOnce := 0;
  var LTimedOut := TimesOut(
    procedure(AToken: ICancellationToken)
    begin
      while not AToken.IsCancellationRequested do
        TThread.Sleep(10);
      var LRan := False;
      AToken.Register(
        procedure
        begin
          LRan := True;
        end);
      // Registered after the cancellation: it must have run by now.
      if LRan then
        TInterlocked.Exchange(LRanAtOnce, 1);
    end);
  Assert.IsTrue(LTimedOut);
  Assert.IsTrue(WaitForFlag(LRanAtOnce));
end;

procedure TTimeoutTests.TestTokenCallbackFailureDoesNotHideTimeout;
begin
  var LSecondRan := 0;
  var LTimedOut := TimesOut(
    procedure(AToken: ICancellationToken)
    begin
      AToken.Register(
        procedure
        begin
          raise EInvalidOpException.Create('Callback failure');
        end);
      AToken.Register(
        procedure
        begin
          TInterlocked.Exchange(LSecondRan, 1);
        end);
      TThread.Sleep(600);
    end);
  Assert.IsTrue(LTimedOut, 'The caller must still get the timeout');
  Assert.AreEqual(1, TInterlocked.CompareExchange(LSecondRan, 0, 0),
    'A failing callback must not stop the following ones');
end;

procedure TTimeoutTests.TestTokenThrowIfCancellationRequestedStopsOperation;
begin
  var LEnded := 0;
  var LTimedOut := TimesOut(
    procedure(AToken: ICancellationToken)
    begin
      try
        // Never ends by itself: only the cancellation can stop it.
        while True do
        begin
          AToken.ThrowIfCancellationRequested;
          TThread.Sleep(10);
        end;
      finally
        TInterlocked.Exchange(LEnded, 1);
      end;
    end);
  Assert.IsTrue(LTimedOut);
  Assert.IsTrue(WaitForFlag(LEnded), 'The abandoned operation must stop by itself');
end;

procedure TTimeoutTests.TestTokenOperationExceptionAfterTimeoutIsDiscarded;
begin
  var LEnded := 0;
  var LTimedOut := TimesOut(
    procedure(AToken: ICancellationToken)
    begin
      try
        TThread.Sleep(400);
        raise EInvalidOpException.Create('Failure of an abandoned operation');
      finally
        TInterlocked.Exchange(LEnded, 1);
      end;
    end);
  Assert.IsTrue(LTimedOut);
  Assert.IsTrue(WaitForFlag(LEnded));
end;

initialization
  TDUnitX.RegisterTestFixture(TTimeoutTests);

end.
