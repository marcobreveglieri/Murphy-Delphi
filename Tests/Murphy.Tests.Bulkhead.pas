unit Murphy.Tests.Bulkhead;

interface

uses
  DUnitX.TestFramework;

type

{ TBulkheadTests }

  [TestFixture]
  TBulkheadTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestBulkheadHandle;
    [Test]
    procedure TestBulkheadAllowsUpToLimit;
    [Test]
    procedure TestBulkheadRejectsWhenFull;
    [Test]
    procedure TestBulkheadReleasesSlotAfterSuccess;
    [Test]
    procedure TestBulkheadReleasesSlotAfterException;
    [Test]
    procedure TestBulkheadExceptionPropagatesUnchanged;
    [Test]
    procedure TestBulkheadConcurrentThreads;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  System.Threading,
  Murphy.Globals,
  Murphy.Policy.Bulkhead;

{ TBulkheadTests }

procedure TBulkheadTests.Setup;
begin
  MurphyTestModeEnabled := True;
end;

procedure TBulkheadTests.TearDown;
begin
  MurphyTestModeEnabled := False;
end;

procedure TBulkheadTests.TestBulkheadHandle;
begin
  var LPolicy := TBulkheadBuilder
    .Handle([])
    .Limit(5);
  Assert.IsNotNull(LPolicy);
  Assert.AreEqual(0, LPolicy.ExecutionCount);
end;

procedure TBulkheadTests.TestBulkheadAllowsUpToLimit;
begin
  var LPolicy := TBulkheadBuilder
    .Handle([])
    .Limit(2);
  var LInnerExecuted := False;
  // A nested Execute on the same policy occupies a second slot,
  // so saturation can be observed without spawning threads.
  LPolicy.Execute(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          LInnerExecuted := True;
          Assert.AreEqual(2, LPolicy.ExecutionCount);
        end);
    end);
  Assert.IsTrue(LInnerExecuted);
  Assert.AreEqual(0, LPolicy.ExecutionCount);
end;

procedure TBulkheadTests.TestBulkheadRejectsWhenFull;
begin
  var LPolicy := TBulkheadBuilder
    .Handle([])
    .Limit(1);
  var LInnerExecuted := False;
  var LOuterCompleted := False;
  LPolicy.Execute(
    procedure
    begin
      Assert.WillRaise(
        procedure
        begin
          LPolicy.Execute(
            procedure
            begin
              LInnerExecuted := True;
            end);
        end, EBulkheadRejectedException
      );
      LOuterCompleted := True;
    end);
  Assert.IsFalse(LInnerExecuted, 'Action should not run when the bulkhead is full');
  Assert.IsTrue(LOuterCompleted);
end;

procedure TBulkheadTests.TestBulkheadReleasesSlotAfterSuccess;
begin
  var LPolicy := TBulkheadBuilder
    .Handle([])
    .Limit(1);
  var LExecutedCalls := 0;
  for var LCallIndex := 1 to 2 do
    LPolicy.Execute(
      procedure
      begin
        Inc(LExecutedCalls);
      end);
  Assert.AreEqual(2, LExecutedCalls);
  Assert.AreEqual(0, LPolicy.ExecutionCount);
end;

procedure TBulkheadTests.TestBulkheadReleasesSlotAfterException;
begin
  var LPolicy := TBulkheadBuilder
    .Handle([])
    .Limit(1);
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          raise EInvalidOpException.Create('Test exception');
        end);
    end, EInvalidOpException
  );
  Assert.WillNotRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
        end);
    end
  );
  Assert.AreEqual(0, LPolicy.ExecutionCount);
end;

procedure TBulkheadTests.TestBulkheadExceptionPropagatesUnchanged;
begin
  // The exception filter is not used by this policy: any exception
  // raised by the action is re-raised as it is.
  var LPolicy := TBulkheadBuilder
    .Handle([ENotImplemented])
    .Limit(1);
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          raise EInvalidOpException.Create('Test exception');
        end);
    end, EInvalidOpException
  );
end;

procedure TBulkheadTests.TestBulkheadConcurrentThreads;
begin
  var LPolicy := TBulkheadBuilder
    .Handle([])
    .Limit(2);
  var LGate := TEvent.Create(nil, True, False, '');
  try
    var LTasks: TArray<ITask>;
    SetLength(LTasks, 2);
    for var LTaskIndex := 0 to 1 do
      LTasks[LTaskIndex] := TTask.Run(
        procedure
        begin
          LPolicy.Execute(
            procedure
            begin
              LGate.WaitFor(5000);
            end);
        end);

    // Waits (bounded) until both tasks hold a bulkhead slot.
    var LElapsed := 0;
    while (LPolicy.ExecutionCount < 2) and (LElapsed < 2000) do
    begin
      TThread.Sleep(10);
      Inc(LElapsed, 10);
    end;
    Assert.AreEqual(2, LPolicy.ExecutionCount, 'Both tasks should hold a slot');

    Assert.WillRaise(
      procedure
      begin
        LPolicy.Execute(
          procedure
          begin
          end);
      end, EBulkheadRejectedException
    );

    LGate.SetEvent;
    TTask.WaitForAll(LTasks);
    Assert.AreEqual(0, LPolicy.ExecutionCount);
  finally
    LGate.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBulkheadTests);

end.
