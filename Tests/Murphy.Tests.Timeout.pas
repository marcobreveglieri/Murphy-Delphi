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
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.TimeSpan,
  Murphy.Policy.Timeout,
  Murphy.Tests.Helpers;

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

initialization
  TDUnitX.RegisterTestFixture(TTimeoutTests);

end.
