unit Murphy.Tests.RateLimit;

interface

uses
  DUnitX.TestFramework;

type

{ TRateLimitTests }

  [TestFixture]
  TRateLimitTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestRateLimitHandle;
    [Test]
    procedure TestAllowsCallsWithinLimit;
    [Test]
    procedure TestRejectsCallsBeyondLimit;
  end;

implementation

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Globals,
  Murphy.Policy.RateLimit;

{ TRateLimitTests }

procedure TRateLimitTests.Setup;
begin
  // Freezes the clock: the bucket never expires during tests.
  MurphyTestModeEnabled := True;
end;

procedure TRateLimitTests.TearDown;
begin
  MurphyTestModeEnabled := False;
end;

procedure TRateLimitTests.TestRateLimitHandle;
begin
  var LPolicy := TRateLimitBuilder
    .Handle([])
    .Allow(5)
    .Within(TTimeSpan.FromSeconds(1));
  Assert.IsNotNull(LPolicy);
end;

procedure TRateLimitTests.TestAllowsCallsWithinLimit;
begin
  var LPolicy := TRateLimitBuilder
    .Handle([])
    .Allow(3)
    .Within(TTimeSpan.FromSeconds(1));
  var LExecutedCalls := 0;
  for var LCallIndex := 1 to 3 do
    LPolicy.Execute(
      procedure
      begin
        Inc(LExecutedCalls);
      end);
  Assert.AreEqual(3, LExecutedCalls);
end;

procedure TRateLimitTests.TestRejectsCallsBeyondLimit;
begin
  var LPolicy := TRateLimitBuilder
    .Handle([])
    .Allow(2)
    .Within(TTimeSpan.FromSeconds(1));
  for var LCallIndex := 1 to 2 do
    LPolicy.Execute(
      procedure
      begin
      end);
  var LExecuted := False;
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          LExecuted := True;
        end);
    end, ERateLimitRejectedException
  );
  Assert.IsFalse(LExecuted, 'Action should not run when the rate limit is exceeded');
end;

initialization
  TDUnitX.RegisterTestFixture(TRateLimitTests);

end.
