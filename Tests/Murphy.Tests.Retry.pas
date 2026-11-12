unit Murphy.Tests.Retry;

interface

uses
  DUnitX.TestFramework;

type

{ TRetryTests }

  [TestFixture]
  TRetryTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestRetryHandle;
    [Test]
    procedure TestRetryHandleWithRetries;
    [Test]
    procedure TestRetryHandleWhenConditionThrowsException;
    [Test]
    procedure TestRetryHandleWhenConditionSkipsException;
    [Test]
    procedure TestOnRetryIsCalledBeforeEachRetry;
    [Test]
    procedure TestOnRetryIsNotCalledWhenFirstAttemptSucceeds;
    [Test]
    procedure TestOnRetryIsNotCalledForUnhandledException;
    [Test]
    procedure TestOnRetryIsNotCalledWhenConditionRejects;
    [Test]
    procedure TestOnRetryCanChangeWaitDelay;
    [Test]
    procedure TestOnRetryExceptionIsPropagated;
  end;

implementation

uses
  System.Diagnostics,
  System.TimeSpan,
  System.SysUtils,
  Murphy.Globals,
  Murphy.Policy.Retry,
  Murphy.Tests.Helpers;

{ TRetryTests }

procedure TRetryTests.Setup;
begin
  // Skips the real wait delays between retry attempts.
  MurphyTestModeEnabled := True;
end;

procedure TRetryTests.TearDown;
begin
  MurphyTestModeEnabled := False;
end;

procedure TRetryTests.TestRetryHandle;
begin
  var LPolicy := TRetryBuilder
    .Handle(EFileNotFoundException);
  Assert.IsNotNull(LPolicy);
end;

procedure TRetryTests.TestRetryHandleWithRetries;
begin
  var LPolicy := TRetryBuilder
    .Handle(EFileNotFoundException)
    .Retry(3);
  Assert.IsNotNull(LPolicy);
end;

procedure TRetryTests.TestRetryHandleWhenConditionThrowsException;
const
  ErrorCode = 123;
begin
  var LPolicy := TRetryBuilder.Handle(EFileNotFoundException)
    .When(
      function (C: TRetryContext): Boolean
      begin
        Result := EFileNotFoundException(C.Exception).ErrorCode <> ErrorCode;
      end
    );
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      var E := EFileNotFoundException.Create('Error Message');
      E.ErrorCode := 123;
      raise E;
    end);
  Assert.AreEqual('EFileNotFoundException', LFailure.ClassName);
end;

procedure TRetryTests.TestRetryHandleWhenConditionSkipsException;
begin
  var LErrorCode := 0;
  var LPolicy := TRetryBuilder.Handle(EFileNotFoundException)
    .When(
      function (C: TRetryContext): Boolean
      begin
        Result := EFileNotFoundException(C.Exception).ErrorCode = LErrorCode;
      end
    );
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      if LErrorCode > 0 then
        Exit;
      Inc(LErrorCode);
      var E := EFileNotFoundException.Create('Error Message');
      E.ErrorCode := LErrorCode;
      raise E;
    end);
  Assert.IsFalse(LFailure.Raised);
end;

procedure TRetryTests.TestOnRetryIsCalledBeforeEachRetry;
begin
  var LAttemptsSeen := '';
  var LExceptionSeen := '';
  var LExecutions := 0;
  var LPolicy := TRetryBuilder.Handle(EInvalidOpException)
    .Retry(3)
    .OnRetry(
      procedure(AContext: TRetryContext)
      begin
        LAttemptsSeen := LAttemptsSeen + AContext.Attempts.ToString + ',';
        LExceptionSeen := AContext.Exception.ClassName;
      end);
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutions);
      raise EInvalidOpException.Create('Test failure');
    end);
  // The last failure is not followed by another attempt: no callback.
  Assert.AreEqual(4, LExecutions);
  Assert.AreEqual('1,2,3,', LAttemptsSeen);
  Assert.AreEqual('EInvalidOpException', LExceptionSeen);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
end;

procedure TRetryTests.TestOnRetryIsNotCalledWhenFirstAttemptSucceeds;
begin
  var LCallbacks := 0;
  var LPolicy := TRetryBuilder.Handle(EInvalidOpException)
    .Retry(3)
    .OnRetry(
      procedure(AContext: TRetryContext)
      begin
        Inc(LCallbacks);
      end);
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      // Succeeds at once.
    end);
  Assert.IsFalse(LFailure.Raised);
  Assert.AreEqual(0, LCallbacks);
end;

procedure TRetryTests.TestOnRetryIsNotCalledForUnhandledException;
begin
  var LCallbacks := 0;
  var LPolicy := TRetryBuilder.Handle(EFileNotFoundException)
    .Retry(3)
    .OnRetry(
      procedure(AContext: TRetryContext)
      begin
        Inc(LCallbacks);
      end);
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      raise EInvalidOpException.Create('Not handled');
    end);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
  Assert.AreEqual(0, LCallbacks);
end;

procedure TRetryTests.TestOnRetryIsNotCalledWhenConditionRejects;
begin
  var LCallbacks := 0;
  var LPolicy := TRetryBuilder.Handle(EInvalidOpException)
    .Retry(3)
    .When(
      function(AContext: TRetryContext): Boolean
      begin
        Result := False;
      end)
    .OnRetry(
      procedure(AContext: TRetryContext)
      begin
        Inc(LCallbacks);
      end);
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      raise EInvalidOpException.Create('Rejected by the condition');
    end);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
  Assert.AreEqual(0, LCallbacks);
end;

procedure TRetryTests.TestOnRetryCanChangeWaitDelay;
begin
  // Needs the real scheduler, because the test one never waits.
  MurphyTestModeEnabled := False;
  var LExecutions := 0;
  var LPolicy := TRetryBuilder.Handle(EInvalidOpException)
    .Retry(1)
    .Wait(TTimeSpan.FromSeconds(5))
    .OnRetry(
      procedure(AContext: TRetryContext)
      begin
        AContext.WaitDelay := TTimeSpan.FromMilliseconds(10);
      end);
  var LStopwatch := TStopwatch.StartNew;
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutions);
      if LExecutions = 1 then
        raise EInvalidOpException.Create('First attempt fails');
    end);
  Assert.IsFalse(LFailure.Raised);
  Assert.AreEqual(2, LExecutions);
  Assert.IsTrue(LStopwatch.ElapsedMilliseconds < 2000,
    'The wait delay set by the callback should replace the configured one');
end;

procedure TRetryTests.TestOnRetryExceptionIsPropagated;
begin
  var LExecutions := 0;
  var LPolicy := TRetryBuilder.Handle(EFileNotFoundException)
    .Retry(3)
    .OnRetry(
      procedure(AContext: TRetryContext)
      begin
        raise EInvalidOpException.Create('Callback failure');
      end);
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      Inc(LExecutions);
      raise EFileNotFoundException.Create('Operation failure');
    end);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
  Assert.AreEqual('Callback failure', LFailure.Message);
  Assert.AreEqual(1, LExecutions, 'The retry must not go on after a callback failure');
end;

initialization
  TDUnitX.RegisterTestFixture(TRetryTests);

end.

