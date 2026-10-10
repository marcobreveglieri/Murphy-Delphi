unit Murphy.Tests.Hedging;

interface

uses
  DUnitX.TestFramework;

type

{ THedgingTests }

  [TestFixture]
  THedgingTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestHedgingHandle;
    [Test]
    procedure TestHedgingHandleWithConfig;
    [Test]
    procedure TestHedgingInvalidMaxAttempts;
    [Test]
    procedure TestPrimaryWinsNoHedge;
    [Test]
    procedure TestHedgeLaunchedAfterDelay;
    [Test]
    procedure TestHedgeWinsWhenPrimarySlow;
    [Test]
    procedure TestFailureTriggersImmediateHedge;
    [Test]
    procedure TestAllAttemptsFail;
    [Test]
    procedure TestUnhandledExceptionPropagatesImmediately;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.SyncObjs,
  System.SysUtils,
  System.TimeSpan,
  Murphy.Policy.Hedging,
  Murphy.Tests.Helpers;

// Note: these tests run with real time (short sleeps) instead of the
// mocked scheduler, because the hedging delay must be interruptible
// by attempt completions; the Timeout tests follow the same approach.

{ THedgingTests }

procedure THedgingTests.Setup;
begin
end;

procedure THedgingTests.TearDown;
begin
end;

procedure THedgingTests.TestHedgingHandle;
begin
  var LPolicy := THedgingBuilder
    .Handle([EInvalidOpException]);
  Assert.IsNotNull(LPolicy);
end;

procedure THedgingTests.TestHedgingHandleWithConfig;
begin
  var LPolicy := THedgingBuilder
    .Handle([EInvalidOpException])
    .MaxAttempts(3)
    .Delay(TTimeSpan.FromMilliseconds(100))
    .OnHedging(
      procedure(AContext: THedgingContext)
      begin
      end);
  Assert.IsNotNull(LPolicy);
end;

procedure THedgingTests.TestHedgingInvalidMaxAttempts;
begin
  Assert.WillRaise(
    procedure
    begin
      THedgingBuilder
        .Handle([EInvalidOpException])
        .MaxAttempts(-1);
    end, EArgumentException
  );
end;

procedure THedgingTests.TestPrimaryWinsNoHedge;
begin
  var LExecutionCount := 0;
  var LHedgeCount := 0;
  var LPolicy := THedgingBuilder
    .Handle([EInvalidOpException])
    .MaxAttempts(2)
    .Delay(TTimeSpan.FromMilliseconds(500))
    .OnHedging(
      procedure(AContext: THedgingContext)
      begin
        TInterlocked.Increment(LHedgeCount);
      end);
  LPolicy.Execute(
    procedure
    begin
      TInterlocked.Increment(LExecutionCount);
    end);
  Assert.AreEqual(1, LExecutionCount);
  Assert.AreEqual(0, LHedgeCount);
end;

procedure THedgingTests.TestHedgeLaunchedAfterDelay;
begin
  var LExecutionCount := 0;
  var LHedgeCount := 0;
  var LLastAttemptNumber := 0;
  var LPolicy := THedgingBuilder
    .Handle([EInvalidOpException])
    .MaxAttempts(1)
    .Delay(TTimeSpan.FromMilliseconds(100))
    .OnHedging(
      procedure(AContext: THedgingContext)
      begin
        TInterlocked.Increment(LHedgeCount);
        LLastAttemptNumber := AContext.AttemptNumber;
      end);
  LPolicy.Execute(
    procedure
    begin
      TInterlocked.Increment(LExecutionCount);
      TThread.Sleep(600);
    end);
  // Waits for the abandoned loser to finish counting.
  TThread.Sleep(700);
  Assert.AreEqual(2, LExecutionCount);
  Assert.AreEqual(1, LHedgeCount);
  Assert.AreEqual(1, LLastAttemptNumber);
end;

procedure THedgingTests.TestHedgeWinsWhenPrimarySlow;
begin
  var LAttemptIndex := 0;
  var LPolicy := THedgingBuilder
    .Handle([EInvalidOpException])
    .MaxAttempts(1)
    .Delay(TTimeSpan.FromMilliseconds(100));
  var LStopwatch := TStopwatch.StartNew;
  Assert.WillNotRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          // The primary attempt is slow, the hedged one is fast.
          if TInterlocked.Increment(LAttemptIndex) = 1 then
            TThread.Sleep(2000);
        end);
    end
  );
  Assert.IsTrue(LStopwatch.ElapsedMilliseconds < 1500,
    'Execute should return as soon as the hedged attempt wins');
  // Waits for the abandoned primary attempt to finish.
  TThread.Sleep(2100);
end;

procedure THedgingTests.TestFailureTriggersImmediateHedge;
begin
  var LAttemptIndex := 0;
  var LPolicy := THedgingBuilder
    .Handle([EInvalidOpException])
    .MaxAttempts(1)
    .Delay(TTimeSpan.FromSeconds(10));
  var LStopwatch := TStopwatch.StartNew;
  Assert.WillNotRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          // The primary attempt fails at once: the hedged attempt must
          // start immediately, without waiting for the 10s delay.
          if TInterlocked.Increment(LAttemptIndex) = 1 then
            raise EInvalidOpException.Create('Primary failure');
        end);
    end
  );
  Assert.IsTrue(LStopwatch.ElapsedMilliseconds < 5000,
    'A handled failure should trigger the hedged attempt immediately');
end;

procedure THedgingTests.TestAllAttemptsFail;
begin
  var LExecutionCount := 0;
  var LPolicy := THedgingBuilder
    .Handle([EFileNotFoundException])
    .MaxAttempts(2)
    .Delay(TTimeSpan.FromMilliseconds(100));
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          TInterlocked.Increment(LExecutionCount);
          raise EFileNotFoundException.Create('Attempt failure');
        end);
    end, EFileNotFoundException
  );
  Assert.AreEqual(3, LExecutionCount);
end;

procedure THedgingTests.TestUnhandledExceptionPropagatesImmediately;
begin
  var LExecutionCount := 0;
  var LHedgeCount := 0;
  var LPolicy := THedgingBuilder
    .Handle([EFileNotFoundException])
    .MaxAttempts(2)
    .Delay(TTimeSpan.FromMilliseconds(100))
    .OnHedging(
      procedure(AContext: THedgingContext)
      begin
        TInterlocked.Increment(LHedgeCount);
      end);
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      TInterlocked.Increment(LExecutionCount);
      raise EInvalidOpException.Create('Unhandled failure');
    end);
  Assert.AreEqual('EInvalidOpException', LFailure.ClassName);
  Assert.AreEqual(1, LExecutionCount);
  Assert.AreEqual(0, LHedgeCount);
end;

initialization
  TDUnitX.RegisterTestFixture(THedgingTests);

end.
